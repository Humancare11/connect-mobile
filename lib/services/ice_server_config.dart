// ICE server (STUN/TURN) configuration, fetched from the backend at call
// start — ported from `frontend/src/pages/VideoCall.jsx`'s ICE-config effect,
// NOT from the older, static-credential pattern in `rtcIceConfig.js` (used
// only by the web app's no-login Direct Video Call flow).
//
// VideoCall.jsx's own header comment explains why: TURN credentials baked
// into a shipped build (env vars inlined at build time) are readable by
// anyone who decompiles/inspects the app and can be used to relay traffic
// through the TURN server indefinitely. The backend instead mints a
// short-lived, per-request TURN credential (coturn's "TURN REST API"
// convention) behind an authenticated endpoint — GET /api/rtc/ice-servers —
// so nothing long-lived ever ships in the app. This file fetches that
// endpoint the same way, with the same retry policy VideoCall.jsx uses.

import 'package:flutter/foundation.dart';

import 'api_service.dart';

bool _isTurnUrl(String url) =>
    RegExp(r'^turns?:', caseSensitive: false).hasMatch(url);

bool _isSupportedIceUrl(String url) =>
    RegExp(r'^(stun|stuns|turn|turns):', caseSensitive: false).hasMatch(url);

List<String> _normalizeIceUrls(dynamic urls) {
  if (urls is List) return urls.map((u) => u.toString()).toList();
  if (urls == null) return const [];
  return [urls.toString()];
}

/// Result of building the ICE configuration: `config` is the map to pass to
/// `createPeerConnection`, `error` is a non-empty validation message if the
/// resolved server list is unusable (mirrors `iceConfigError` in React).
class IceServerSetup {
  final Map<String, dynamic> config;
  final String error;
  final bool hasTurn;

  const IceServerSetup({
    required this.config,
    required this.error,
    required this.hasTurn,
  });

  bool get isUsable => error.isEmpty && config.isNotEmpty;
}

const IceServerSetup kEmptyIceServerSetup = IceServerSetup(
  config: {},
  error: '',
  hasTurn: false,
);

Map<String, dynamic>? _sanitizeServer(dynamic server) {
  if (server is! Map) return null;
  final urls = _normalizeIceUrls(server['urls']).where(_isSupportedIceUrl).toList();
  if (urls.isEmpty) return null;

  final sanitized = <String, dynamic>{
    'urls': urls.length == 1 ? urls.first : urls,
  };
  final username = server['username']?.toString().trim();
  final credential = server['credential']?.toString().trim();
  if (username != null && username.isNotEmpty) sanitized['username'] = username;
  if (credential != null && credential.isNotEmpty) {
    sanitized['credential'] = credential;
  }
  final credentialType = server['credentialType'];
  if (credentialType == 'password' || credentialType == 'oauth') {
    sanitized['credentialType'] = credentialType;
  }
  return sanitized;
}

List<Map<String, dynamic>> _sanitizeIceServers(dynamic iceServers) {
  if (iceServers is! List) return const [];
  final result = <Map<String, dynamic>>[];
  for (final server in iceServers) {
    final sanitized = _sanitizeServer(server);
    if (sanitized != null) result.add(sanitized);
  }
  return result;
}

/// Mirrors `validateIceServers` in VideoCall.jsx: a TURN url without a
/// username/credential means the server responded but is misconfigured —
/// that's reported immediately rather than retried (see fetchIceServerConfig).
String _validateIceServers(List<Map<String, dynamic>> iceServers) {
  if (iceServers.isEmpty) {
    return 'No ICE servers were returned by the server.';
  }

  for (final server in iceServers) {
    final urls = _normalizeIceUrls(server['urls']);
    for (final url in urls) {
      if (_isTurnUrl(url)) {
        final username = server['username'];
        final credential = server['credential'];
        if (username == null ||
            credential == null ||
            username.toString().isEmpty ||
            credential.toString().isEmpty) {
          return 'A TURN server is missing its credential.';
        }
      }
    }
  }
  return '';
}

bool _hasTurnServer(List<Map<String, dynamic>> iceServers) => iceServers.any(
      (server) => _normalizeIceUrls(server['urls']).any(_isTurnUrl),
    );

const List<int> _kRetryDelaysMs = [1000, 2000]; // before the 2nd/3rd attempt

/// Fetches ICE servers from the backend, retrying only on request failure
/// (network blip) — same policy as VideoCall.jsx's `attemptFetch`. A response
/// that arrives but fails validation indicates a persistent server-side
/// config problem, not a blip, so it's reported immediately without retrying.
Future<IceServerSetup> fetchIceServerConfig() async {
  Object? lastError;

  for (var attempt = 0; attempt <= _kRetryDelaysMs.length; attempt++) {
    try {
      final data = await ApiService.instance.get('/api/rtc/ice-servers');
      final iceServers = _sanitizeIceServers(
        data is Map ? data['iceServers'] : null,
      );
      final error = _validateIceServers(iceServers);
      if (error.isNotEmpty) {
        return IceServerSetup(config: const {}, error: error, hasTurn: false);
      }

      final hasTurn = _hasTurnServer(iceServers);
      if (!hasTurn) {
        debugPrint(
          '[ice-config] No TURN server configured. Same-network calls may '
          'work, but calls across strict NATs can fail.',
        );
      }

      return IceServerSetup(
        config: {
          'iceServers': iceServers,
          'iceCandidatePoolSize': 10,
          'bundlePolicy': 'max-bundle',
          'rtcpMuxPolicy': 'require',
        },
        error: '',
        hasTurn: hasTurn,
      );
    } catch (err) {
      lastError = err;
      if (attempt < _kRetryDelaysMs.length) {
        await Future.delayed(Duration(milliseconds: _kRetryDelaysMs[attempt]));
      }
    }
  }

  return IceServerSetup(
    config: const {},
    error: lastError?.toString() ?? 'Could not fetch video call configuration.',
    hasTurn: false,
  );
}

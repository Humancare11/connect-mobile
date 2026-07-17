// ICE server (STUN/TURN) configuration, ported 1:1 from the environment-driven
// config the web app builds in frontend/src/pages/VideoCall.jsx
// (buildIceServerConfig / sanitizeIceServers / validateIceServers /
// hasTurnServer). Uses the SAME env var names as frontend/.env* so ops can
// copy the existing TURN block into connect-mobile/.env* verbatim.
//
// Env vars read (via flutter_dotenv):
//   VITE_RTC_ICE_SERVERS_JSON        - optional full override, JSON array or
//                                       {"iceServers": [...]}
//   VITE_RTC_STUN_URLS               - comma-separated STUN urls
//   VITE_RTC_TURN_URLS               - comma-separated TURN urls
//   VITE_RTC_TURN_USERNAME           - TURN username
//   VITE_RTC_TURN_CREDENTIAL         - TURN credential
//   VITE_RTC_ICE_CANDIDATE_POOL_SIZE - default 10

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

const List<String> kFallbackStunUrls = [
  'stun:stun.l.google.com:19302',
  'stun:stun1.l.google.com:19302',
  'stun:stun2.l.google.com:19302',
  'stun:stun3.l.google.com:19302',
  'stun:stun4.l.google.com:19302',
];

List<String> _parseCsv(String? value) => (value ?? '')
    .split(',')
    .map((item) => item.trim())
    .where((item) => item.isNotEmpty)
    .toList();

bool _isTurnUrl(String url) =>
    RegExp(r'^turns?:', caseSensitive: false).hasMatch(url);

bool _isSupportedIceUrl(String url) =>
    RegExp(r'^(stun|stuns|turn|turns):', caseSensitive: false).hasMatch(url);

List<String> _normalizeIceUrls(dynamic urls) {
  if (urls is List) return urls.map((u) => u.toString()).toList();
  return _parseCsv(urls?.toString());
}

/// Result of building the ICE configuration: `config` is the map to pass to
/// `createPeerConnection`, `error` is a non-empty validation message if the
/// resolved server list is unusable (mirrors RTC_CONFIG_ERROR in React).
class IceServerSetup {
  final Map<String, dynamic> config;
  final String error;
  final bool hasTurn;

  const IceServerSetup({
    required this.config,
    required this.error,
    required this.hasTurn,
  });
}

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

List<Map<String, dynamic>> _sanitizeIceServers(List<dynamic> iceServers) {
  final result = <Map<String, dynamic>>[];
  for (final server in iceServers) {
    final sanitized = _sanitizeServer(server);
    if (sanitized != null) result.add(sanitized);
  }
  return result;
}

String _validateIceServers(List<Map<String, dynamic>> iceServers) {
  if (iceServers.isEmpty) return 'No ICE servers are configured.';

  for (final server in iceServers) {
    final urls = _normalizeIceUrls(server['urls']);
    if (urls.isEmpty) return 'An ICE server is missing urls.';
    for (final url in urls) {
      if (_isTurnUrl(url)) {
        final username = server['username'];
        final credential = server['credential'];
        if (username == null ||
            credential == null ||
            username.toString().isEmpty ||
            credential.toString().isEmpty) {
          return 'TURN servers require username and credential.';
        }
      }
    }
  }
  return '';
}

bool _hasTurnServer(List<Map<String, dynamic>> iceServers) => iceServers.any(
      (server) => _normalizeIceUrls(server['urls']).any(_isTurnUrl),
    );

int _envInt(String key, int fallback) {
  final raw = dotenv.env[key];
  if (raw == null || raw.trim().isEmpty) return fallback;
  return int.tryParse(raw.trim()) ?? fallback;
}

/// Builds the ICE server configuration exactly the way VideoCall.jsx does:
/// prefer a full JSON override, else assemble from STUN/TURN CSV env vars,
/// else fall back to public STUN. Warns (does not fail) when no TURN server
/// is configured, mirroring the React `console.warn` in production builds.
IceServerSetup buildIceServerConfig() {
  final poolSize = _envInt('VITE_RTC_ICE_CANDIDATE_POOL_SIZE', 10);

  Map<String, dynamic> baseConfig(List<Map<String, dynamic>> iceServers) => {
        'iceServers': iceServers,
        'iceCandidatePoolSize': poolSize,
        'bundlePolicy': 'max-bundle',
        'rtcpMuxPolicy': 'require',
      };

  final jsonConfig = dotenv.env['VITE_RTC_ICE_SERVERS_JSON'];
  if (jsonConfig != null && jsonConfig.trim().isNotEmpty) {
    try {
      final parsed = jsonDecode(jsonConfig);
      final rawList = parsed is List
          ? parsed
          : (parsed is Map ? parsed['iceServers'] as List<dynamic>? : null);
      final iceServers = _sanitizeIceServers(rawList ?? []);
      if (iceServers.isNotEmpty) {
        final error = _validateIceServers(iceServers);
        final hasTurn = _hasTurnServer(iceServers);
        if (!hasTurn) {
          debugPrint(
            '[ice-config] No TURN server configured. Same-network calls may '
            'work, but calls across strict NATs can fail.',
          );
        }
        return IceServerSetup(
          config: baseConfig(iceServers),
          error: error,
          hasTurn: hasTurn,
        );
      }
      debugPrint('[ice-config] VITE_RTC_ICE_SERVERS_JSON did not contain iceServers.');
    } catch (err) {
      return IceServerSetup(
        config: const {},
        error: 'Invalid VITE_RTC_ICE_SERVERS_JSON: $err',
        hasTurn: false,
      );
    }
  }

  final stunUrls = _parseCsv(dotenv.env['VITE_RTC_STUN_URLS']);
  final turnUrls = _parseCsv(dotenv.env['VITE_RTC_TURN_URLS']);
  final turnUsername = dotenv.env['VITE_RTC_TURN_USERNAME'] ?? '';
  final turnCredential = dotenv.env['VITE_RTC_TURN_CREDENTIAL'] ?? '';

  final iceServers = <Map<String, dynamic>>[
    for (final url in (stunUrls.isNotEmpty ? stunUrls : kFallbackStunUrls))
      {'urls': url},
  ];

  if (turnUrls.isNotEmpty && turnUsername.isNotEmpty && turnCredential.isNotEmpty) {
    iceServers.add({
      'urls': turnUrls,
      'username': turnUsername,
      'credential': turnCredential,
    });
  } else if (turnUrls.isNotEmpty) {
    debugPrint(
      '[ice-config] VITE_RTC_TURN_URLS is set, but TURN username/credential '
      'is missing. Continuing with STUN-only ICE.',
    );
  }

  final error = _validateIceServers(iceServers);
  final hasTurn = _hasTurnServer(iceServers);
  if (!hasTurn) {
    debugPrint(
      '[ice-config] No TURN server configured. Same-network calls may work, '
      'but calls across strict NATs can fail.',
    );
  }

  return IceServerSetup(
    config: baseConfig(iceServers),
    error: error,
    hasTurn: hasTurn,
  );
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/api_result.dart';
import 'idle_session_timer.dart';
import 'loading_service.dart';
import 'session_expired_service.dart';
import 'token_storage_service.dart';

class ApiClient {
  ApiClient({http.Client? client, TokenStorageService? tokenStorage})
    : _client = client ?? http.Client(),
      _tokenStorage = tokenStorage ?? const TokenStorageService();

  final http.Client _client;
  final TokenStorageService _tokenStorage;

  // Static (not per-instance) because every call site constructs its own
  // `ApiClient()` (see api_service.dart, auth_service.dart, etc.) — without
  // this being shared across instances, several requests 401ing at the same
  // moment would each kick off their own `/api/auth/refresh` call. Besides
  // the wasted requests, racing refreshes is actively harmful if the backend
  // rotates the refresh token on use: the second call's refresh token would
  // already be stale by the time it lands, turning a single legitimate
  // expiry into a spurious logout. Coalescing means every concurrent 401
  // waits on the one in-flight refresh instead.
  static Future<bool>? _refreshInFlight;

  // debugPrint() (unlike assert) still runs in release builds, and request/
  // response bodies here carry patient PII/medical data beyond what
  // _redactSecrets covers (only token/secret/authorization keys are
  // redacted). Gating on kDebugMode keeps these logs for local development
  // without writing that data to the release build's system log (readable
  // via `adb logcat`).
  void _log(String message) {
    if (kDebugMode) debugPrint(message);
  }

  Future<ApiResult<Map<String, dynamic>>> post(
    String path,
    Map<String, dynamic> body, {
    bool silent = false,
  }) async {
    IdleSessionTimer.instance.registerActivity();
    if (!silent) LoadingService.instance.show();
    try {
      // Attach auth token if available (using secure storage)
      final token = await _tokenStorage.getToken() ?? '';

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      _log(
        'POST $uri authToken=${token.isNotEmpty ? "present" : "missing"} '
        'body=${jsonEncode(_redactSecrets(body))}',
      );

      final response = await _client
          .post(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      return await _handleResponse(
        'POST',
        path,
        response,
        authAttached: token.isNotEmpty,
        retryWithToken: token.isEmpty
            ? null
            : (newToken) => _client
                  .post(
                    uri,
                    headers: {...headers, 'Authorization': 'Bearer $newToken'},
                    body: jsonEncode(body),
                  )
                  .timeout(const Duration(seconds: 30)),
      );
    } catch (error, stackTrace) {
      return _handleError('POST', path, error, stackTrace);
    } finally {
      if (!silent) LoadingService.instance.hide();
    }
  }

  Future<ApiResult<Map<String, dynamic>>> get(
    String path, [
    Map<String, String>? params,
    bool silent = false,
  ]) async {
    IdleSessionTimer.instance.registerActivity();
    if (!silent) LoadingService.instance.show();
    try {
      final token = await _tokenStorage.getToken() ?? '';

      final headers = <String, String>{
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      var uri = Uri.parse('${ApiConfig.baseUrl}$path');
      if (params != null && params.isNotEmpty) {
        uri = uri.replace(queryParameters: params);
      }
      _log('GET $uri');

      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      return await _handleResponse(
        'GET',
        path,
        response,
        authAttached: token.isNotEmpty,
        retryWithToken: token.isEmpty
            ? null
            : (newToken) => _client
                  .get(uri, headers: {...headers, 'Authorization': 'Bearer $newToken'})
                  .timeout(const Duration(seconds: 30)),
      );
    } catch (error, stackTrace) {
      return _handleError('GET', path, error, stackTrace);
    } finally {
      if (!silent) LoadingService.instance.hide();
    }
  }

  Future<ApiResult<Map<String, dynamic>>> put(
    String path,
    Map<String, dynamic> body, {
    bool silent = false,
  }) async {
    IdleSessionTimer.instance.registerActivity();
    if (!silent) LoadingService.instance.show();
    try {
      final token = await _tokenStorage.getToken() ?? '';

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      _log('PUT $uri');

      final response = await _client
          .put(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      return await _handleResponse(
        'PUT',
        path,
        response,
        authAttached: token.isNotEmpty,
        retryWithToken: token.isEmpty
            ? null
            : (newToken) => _client
                  .put(
                    uri,
                    headers: {...headers, 'Authorization': 'Bearer $newToken'},
                    body: jsonEncode(body),
                  )
                  .timeout(const Duration(seconds: 30)),
      );
    } catch (error, stackTrace) {
      return _handleError('PUT', path, error, stackTrace);
    } finally {
      if (!silent) LoadingService.instance.hide();
    }
  }

  Future<ApiResult<Map<String, dynamic>>> patch(
    String path,
    Map<String, dynamic> body, {
    bool silent = false,
  }) async {
    IdleSessionTimer.instance.registerActivity();
    if (!silent) LoadingService.instance.show();
    try {
      final token = await _tokenStorage.getToken() ?? '';

      final headers = {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        if (token.isNotEmpty) 'Authorization': 'Bearer $token',
      };

      final uri = Uri.parse('${ApiConfig.baseUrl}$path');
      _log('PATCH $uri');

      final response = await _client
          .patch(uri, headers: headers, body: jsonEncode(body))
          .timeout(const Duration(seconds: 30));

      return await _handleResponse(
        'PATCH',
        path,
        response,
        authAttached: token.isNotEmpty,
        retryWithToken: token.isEmpty
            ? null
            : (newToken) => _client
                  .patch(
                    uri,
                    headers: {...headers, 'Authorization': 'Bearer $newToken'},
                    body: jsonEncode(body),
                  )
                  .timeout(const Duration(seconds: 30)),
      );
    } catch (error, stackTrace) {
      return _handleError('PATCH', path, error, stackTrace);
    } finally {
      if (!silent) LoadingService.instance.hide();
    }
  }

  /// Refreshes the access token using the stored refresh token, persisting
  /// the rotated pair on success. This is the only call in the app that
  /// sends the refresh token as a bearer credential — every other request
  /// keeps using the access token via [get]/[post]/[put]/[patch], unchanged.
  /// Non-fatal on any failure (missing/expired refresh token, network
  /// error): callers proceed with whatever's already in storage.
  Future<bool> refreshAccessToken(String role) async {
    final refreshToken = await _tokenStorage.getRefreshToken();
    if (refreshToken == null || refreshToken.isEmpty) return false;

    try {
      // ApiConfig.baseUrl already ends in `/api` (see api_config.dart) —
      // every other call site in this file builds its URL the same way
      // ('${ApiConfig.baseUrl}$path' with a path like '/auth/login', no
      // leading /api). This one previously hardcoded an extra '/api'
      // prefix, doubling it to '.../api/api/auth/refresh' and 404ing on
      // every call — silently breaking token refresh entirely, which meant
      // every user got forced back to the login screen roughly every 15
      // minutes (the access token TTL) instead of being transparently
      // refreshed.
      final uri = Uri.parse('${ApiConfig.baseUrl}/auth/refresh');
      final response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'Authorization': 'Bearer $refreshToken',
              'X-Auth-Role': role,
            },
            body: jsonEncode({'role': role}),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode < 200 || response.statusCode >= 300) {
        return false;
      }

      final data = _asMap(
        response.body.isNotEmpty ? jsonDecode(response.body) : {},
      );
      final newAccessToken = data['accessToken']?.toString() ?? '';
      if (newAccessToken.isEmpty) return false;

      await _tokenStorage.saveToken(newAccessToken);
      final newRefreshToken = data['refreshToken']?.toString() ?? '';
      if (newRefreshToken.isNotEmpty) {
        await _tokenStorage.saveRefreshToken(newRefreshToken);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reacts to a completed HTTP exchange, transparently recovering from an
  /// expired access token before handing back to the caller.
  ///
  /// [authAttached] is true when this request actually carried a bearer
  /// token — a `401` from an endpoint called with no token (e.g. a failed
  /// login attempt) is a normal auth failure, not a dead session, so it must
  /// never trigger [SessionExpiredService]; that guard also prevents a
  /// redirect loop where a stray 401 on the login screen itself re-opens the
  /// "session expired" gate.
  ///
  /// On a genuine `401` with a token attached: attempts one coalesced
  /// refresh (see [_refreshInFlight]) and, if it succeeds, retries the
  /// original request exactly once via [retryWithToken]. If the refresh
  /// fails, there's no refresh token, or the retried request is *still*
  /// `401` (refresh token revoked server-side, account disabled, etc.), the
  /// session is declared dead: stored tokens are cleared and
  /// [SessionExpiredService] is triggered. Either way this still returns an
  /// [ApiResult] describing what actually happened to the *original* call,
  /// so existing per-screen error handling (toasts, inline messages) keeps
  /// working unchanged alongside the new global gate.
  Future<ApiResult<Map<String, dynamic>>> _handleResponse(
    String method,
    String path,
    http.Response response, {
    required bool authAttached,
    Future<http.Response> Function(String newAccessToken)? retryWithToken,
  }) async {
    if (response.statusCode != 401 || !authAttached) {
      return _parseResponse(method, path, response);
    }

    final refreshedToken = await _refreshOnUnauthorized();
    if (refreshedToken != null && retryWithToken != null) {
      try {
        final retryResponse = await retryWithToken(refreshedToken);
        _log(
          '$method $path retried after token refresh, status: '
          '${retryResponse.statusCode}',
        );
        if (retryResponse.statusCode != 401) {
          return _parseResponse(method, path, retryResponse);
        }
      } catch (error, stackTrace) {
        _log('$method $path retry after refresh failed: $error');
        _log('$stackTrace');
        // Fall through and treat the original 401 below as the session
        // being dead — the refreshed token itself couldn't complete a
        // request, so there's nothing left to try.
      }
    }

    await _handleSessionExpired();
    return _parseResponse(method, path, response);
  }

  /// Attempts a single, coalesced token refresh in reaction to a `401`. If a
  /// refresh triggered by another concurrent request is already in flight,
  /// this awaits that same attempt instead of starting a second one — racing
  /// independent refresh calls is actively harmful if the backend rotates
  /// the refresh token on use, since the loser's refresh token would already
  /// be stale by the time it's sent. Returns the new access token on
  /// success, or `null` if refresh wasn't possible/failed.
  Future<String?> _refreshOnUnauthorized() async {
    final existing = _refreshInFlight;
    final bool refreshed;
    if (existing != null) {
      refreshed = await existing;
    } else {
      final attempt = _performRefresh();
      _refreshInFlight = attempt;
      try {
        refreshed = await attempt;
      } finally {
        if (identical(_refreshInFlight, attempt)) {
          _refreshInFlight = null;
        }
      }
    }

    if (!refreshed) return null;
    final token = await _tokenStorage.getToken();
    return (token != null && token.isNotEmpty) ? token : null;
  }

  Future<bool> _performRefresh() async {
    final profile = await _tokenStorage.getUserProfile();
    final role = profile['role']?.trim() ?? '';
    return refreshAccessToken(role.isEmpty ? 'user' : role);
  }

  /// Declares the session dead: clears stored tokens (so no further request
  /// keeps trying to use them), stops the idle timer (nothing left to time
  /// out), and flips the global gate. Idempotent — safe to reach from
  /// several requests that all 401'd around the same moment.
  Future<void> _handleSessionExpired() async {
    if (SessionExpiredService.instance.isExpired) return;
    IdleSessionTimer.instance.stop();
    await _tokenStorage.clearAll();
    SessionExpiredService.instance.trigger();
  }

  /// Parses a completed HTTP exchange (any status code) into an [ApiResult].
  ApiResult<Map<String, dynamic>> _parseResponse(
    String method,
    String path,
    http.Response response,
  ) {
    _log('$method $path status: ${response.statusCode}');
    _log(
      '$method $path raw response: ${_redactedResponseBody(response.body)}',
    );

    try {
      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};
      final data = _asMap(decoded);
      final message = _messageFrom(data, 'Request failed.');
      final success = _isSuccessfulResponse(response.statusCode, data);

      return ApiResult<Map<String, dynamic>>(
        success: success,
        message: message,
        data: data,
        raw: data,
        statusCode: response.statusCode,
      );
    } on FormatException catch (error) {
      _log('$method $path invalid JSON: $error');
      return ApiResult<Map<String, dynamic>>(
        success: false,
        message: _unexpectedResponseMessage(response),
        statusCode: response.statusCode,
      );
    }
  }

  String _unexpectedResponseMessage(http.Response response) {
    final contentType = response.headers['content-type']?.toLowerCase() ?? '';
    final body = response.body.toLowerCase();

    if (response.statusCode == 405 ||
        contentType.contains('text/html') ||
        body.contains('<html')) {
      return 'The API is not returning backend JSON. Please check server '
          'routing for /api on ${ApiConfig.baseUrl}.';
    }

    return 'Unexpected response from the server (${response.statusCode}).';
  }

  /// Maps a thrown exception (connectivity, timeout, TLS, etc.) into a
  /// user-friendly [ApiResult] while logging the underlying cause for
  /// debugging.
  ApiResult<Map<String, dynamic>> _handleError(
    String method,
    String path,
    Object error,
    StackTrace stackTrace,
  ) {
    _log('$method $path failed: $error');
    _log('$stackTrace');

    return ApiResult<Map<String, dynamic>>(
      success: false,
      message: _friendlyErrorMessage(error),
    );
  }

  String _friendlyErrorMessage(Object error) {
    if (error is TimeoutException) {
      return 'The server took too long to respond. Please check your '
          'connection and try again.';
    }

    if (error is SocketException) {
      final detail = '${error.message} ${error.osError?.message ?? ''}'
          .toLowerCase();
      if (error.osError?.errorCode == 7 ||
          detail.contains('failed host lookup') ||
          detail.contains('no address associated with hostname')) {
        return 'Cannot reach the server. Please check your internet '
            'connection (DNS lookup failed).';
      }
      if (detail.contains('connection refused')) {
        return 'The API server refused the connection at ${ApiConfig.baseUrl}.';
      }
      if (detail.contains('network is unreachable') ||
          detail.contains('no route to host')) {
        return 'Cannot reach the API server at ${ApiConfig.baseUrl}. Please '
            'check this device\'s network access.';
      }
      return 'Unable to connect to ${ApiConfig.baseUrl}. Please check that '
          'the API host is reachable from this device.';
    }

    if (error is HandshakeException || error is TlsException) {
      return 'Secure connection to the server failed. Please try again.';
    }

    if (error is http.ClientException) {
      final detail = error.message.toLowerCase();
      if (detail.contains('failed host lookup') ||
          detail.contains('no address associated with hostname')) {
        return 'Cannot reach the server. Please check your internet '
            'connection (DNS lookup failed).';
      }
      if (detail.contains('connection closed') ||
          detail.contains('connection reset')) {
        return 'The connection to the server was interrupted. Please try '
            'again.';
      }
      if (kIsWeb) {
        // On Flutter web every network/CORS failure surfaces as an opaque
        // ClientException with no detail. The production API only sends
        // Access-Control-Allow-Origin for its own domain, so a browser build
        // served from any other origin (e.g. `flutter run -d chrome` on
        // localhost) is blocked before the request completes. Native
        // Android/iOS builds send no Origin header and are unaffected.
        return 'Could not reach ${ApiConfig.baseUrl} from this web build. '
            'The API only accepts browser requests from its own domain — '
            'run the app on an Android/iOS device or emulator instead.';
      }
      return 'Unable to connect to ${ApiConfig.baseUrl}. Please check that '
          'the API host is reachable from this device.';
    }

    if (error is StateError) {
      // e.g. API_BASE_URL missing from .env
      return 'App is not configured correctly. Please contact support.';
    }

    return 'Something went wrong. Please try again.';
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    if (value is List) {
      return {'data': value};
    }

    return <String, dynamic>{};
  }

  bool _isSuccessfulResponse(int statusCode, Map<String, dynamic> data) {
    if (statusCode < 200 || statusCode >= 300) return false;

    for (final key in ['success', 'status', 'ok']) {
      final value = data[key];
      if (value is bool) return value;
      if (value is String) {
        final normalized = value.trim().toLowerCase();
        if (normalized == 'false' || normalized == 'failed') return false;
        if (normalized == 'true' || normalized == 'success') return true;
      }
    }

    return true;
  }

  String _messageFrom(Map<String, dynamic> data, String fallback) {
    final responseData = _asMap(data['data']);

    for (final value in [
      data['msg'],
      data['message'],
      data['error'],
      data['detail'],
      responseData['msg'],
      responseData['message'],
      responseData['error'],
      responseData['detail'],
      fallback,
    ]) {
      final text = value?.toString().trim() ?? '';

      if (text.isNotEmpty) {
        return text;
      }
    }

    return fallback;
  }

  String _redactedResponseBody(String body) {
    if (body.isEmpty) return body;

    try {
      return jsonEncode(_redactSecrets(jsonDecode(body)));
    } catch (_) {
      return body;
    }
  }

  dynamic _redactSecrets(dynamic value) {
    if (value is Map) {
      return value.map((key, mapValue) {
        final normalizedKey = key.toString().toLowerCase();
        if (normalizedKey.contains('token') ||
            normalizedKey.contains('secret') ||
            normalizedKey == 'authorization') {
          return MapEntry(key.toString(), _redactSecretValue(mapValue));
        }

        return MapEntry(key.toString(), _redactSecrets(mapValue));
      });
    }

    if (value is List) {
      return value.map(_redactSecrets).toList();
    }

    return value;
  }

  String _redactSecretValue(Object? value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty) return '(empty)';
    final marker = text.indexOf('_secret_');
    if (marker > 0) return '${text.substring(0, marker)}_secret_...';
    if (text.length <= 12) return '...';
    return '${text.substring(0, 6)}...${text.substring(text.length - 4)}';
  }
}

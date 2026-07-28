import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/api_result.dart';
import 'token_storage_service.dart';

class ApiClient {
  ApiClient({http.Client? client, TokenStorageService? tokenStorage})
    : _client = client ?? http.Client(),
      _tokenStorage = tokenStorage ?? const TokenStorageService();

  final http.Client _client;
  final TokenStorageService _tokenStorage;

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
    Map<String, dynamic> body,
  ) async {
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

      return _handleResponse('POST', path, response);
    } catch (error, stackTrace) {
      return _handleError('POST', path, error, stackTrace);
    }
  }

  Future<ApiResult<Map<String, dynamic>>> get(
    String path, [
    Map<String, String>? params,
  ]) async {
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

      return _handleResponse('GET', path, response);
    } catch (error, stackTrace) {
      return _handleError('GET', path, error, stackTrace);
    }
  }

  Future<ApiResult<Map<String, dynamic>>> put(
    String path,
    Map<String, dynamic> body,
  ) async {
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

      return _handleResponse('PUT', path, response);
    } catch (error, stackTrace) {
      return _handleError('PUT', path, error, stackTrace);
    }
  }

  Future<ApiResult<Map<String, dynamic>>> patch(
    String path,
    Map<String, dynamic> body,
  ) async {
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

      return _handleResponse('PATCH', path, response);
    } catch (error, stackTrace) {
      return _handleError('PATCH', path, error, stackTrace);
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
      final uri = Uri.parse('${ApiConfig.baseUrl}/api/auth/refresh');
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

  /// Parses a successful HTTP exchange (any status code) into an [ApiResult].
  ApiResult<Map<String, dynamic>> _handleResponse(
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
      return 'UAT API is not returning backend JSON. Please check server '
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
            'check network access to this UAT host.';
      }
      return 'Unable to connect to ${ApiConfig.baseUrl}. Please check that '
          'the UAT API host is reachable from this device.';
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
      return 'Unable to connect to ${ApiConfig.baseUrl}. Please check that '
          'the UAT API host is reachable from this device.';
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

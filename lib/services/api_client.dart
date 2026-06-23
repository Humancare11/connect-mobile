import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/api_config.dart';
import '../models/api_result.dart';
import 'token_storage_service.dart';

class ApiClient {
  ApiClient({http.Client? client, TokenStorageService? tokenStorage})
    : _client = client ?? http.Client(),
      _tokenStorage = tokenStorage ?? const TokenStorageService();

  final http.Client _client;
  final TokenStorageService _tokenStorage;

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
      debugPrint('POST $uri');

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
      debugPrint('GET $uri');

      final response = await _client
          .get(uri, headers: headers)
          .timeout(const Duration(seconds: 30));

      return _handleResponse('GET', path, response);
    } catch (error, stackTrace) {
      return _handleError('GET', path, error, stackTrace);
    }
  }

  /// Parses a successful HTTP exchange (any status code) into an [ApiResult].
  ApiResult<Map<String, dynamic>> _handleResponse(
    String method,
    String path,
    http.Response response,
  ) {
    debugPrint('$method $path status: ${response.statusCode}');
    debugPrint('$method $path raw response: ${response.body}');

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
      debugPrint('$method $path invalid JSON: $error');
      return ApiResult<Map<String, dynamic>>(
        success: false,
        message:
            'Unexpected response from the server (${response.statusCode}).',
        statusCode: response.statusCode,
      );
    }
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
    debugPrint('$method $path failed: $error');
    debugPrint('$stackTrace');

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
        return 'The server refused the connection. Please try again later.';
      }
      if (detail.contains('network is unreachable') ||
          detail.contains('no route to host')) {
        return 'No internet connection. Please check your network and '
            'try again.';
      }
      return 'Unable to connect. Please check your internet connection.';
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
      return 'Unable to connect. Please check your internet connection.';
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
}

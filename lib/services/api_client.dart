import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../models/api_result.dart';

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<ApiResult<Map<String, dynamic>>> post(
    String path,
    Map<String, dynamic> body,
  ) async {
    try {
      final response = await _client.post(
        Uri.parse('${ApiConfig.baseUrl}$path'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );

      debugPrint('POST $path status: ${response.statusCode}');
      debugPrint('POST $path raw response: ${response.body}');

      final decoded = response.body.isNotEmpty
          ? jsonDecode(response.body)
          : <String, dynamic>{};
      final data = _asMap(decoded);
      final message = _messageFrom(data, 'Request failed.');

      return ApiResult<Map<String, dynamic>>(
        success: response.statusCode >= 200 && response.statusCode < 300,
        message: message,
        data: data,
        raw: data,
        statusCode: response.statusCode,
      );
    } on FormatException catch (error) {
      debugPrint('POST $path invalid JSON: $error');
      return const ApiResult<Map<String, dynamic>>(
        success: false,
        message: 'Invalid server response. Please try again.',
      );
    } catch (error) {
      debugPrint('POST $path failed: $error');
      return const ApiResult<Map<String, dynamic>>(
        success: false,
        message: 'Unable to connect. Please try again.',
      );
    }
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }

    return <String, dynamic>{};
  }

  String _messageFrom(Map<String, dynamic> data, String fallback) {
    for (final value in [
      data['msg'],
      data['message'],
      data['error'],
      data['detail'],
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

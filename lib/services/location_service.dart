import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../models/api_result.dart';
import '../models/location_model.dart';

/// Fetches country/state/city data from the public countriesnow.space API.
class LocationService {
  LocationService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://countriesnow.space/api/v0.1/countries';

  final http.Client _client;

  Future<ApiResult<List<Country>>> getCountries() async {
    try {
      final uri = Uri.parse('$_baseUrl/positions');
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));

      final decoded = _decode(response);
      if (decoded == null) {
        return ApiResult(
          success: false,
          message: _unexpectedMessage(response),
          statusCode: response.statusCode,
        );
      }
      if (_hasError(decoded)) {
        return ApiResult(
          success: false,
          message: _errorMessage(decoded),
          statusCode: response.statusCode,
        );
      }

      final raw = decoded['data'];
      final countries = raw is List
          ? raw
              .whereType<Map>()
              .map((e) => Country.fromJson(_stringKeyed(e)))
              .where((c) => c.name.isNotEmpty)
              .toList()
          : <Country>[];
      countries.sort((a, b) => a.name.compareTo(b.name));

      return ApiResult(
        success: true,
        message: 'OK',
        data: countries,
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiResult(success: false, message: _friendlyError(error));
    }
  }

  Future<ApiResult<List<StateItem>>> getStates(String country) async {
    try {
      final uri = Uri.parse('$_baseUrl/states');
      final response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'country': country}),
          )
          .timeout(const Duration(seconds: 20));

      final decoded = _decode(response);
      if (decoded == null) {
        return ApiResult(
          success: false,
          message: _unexpectedMessage(response),
          statusCode: response.statusCode,
        );
      }
      if (_hasError(decoded)) {
        return ApiResult(
          success: false,
          message: _errorMessage(decoded),
          statusCode: response.statusCode,
        );
      }

      final data = decoded['data'];
      final rawStates = data is Map ? data['states'] : null;
      final states = rawStates is List
          ? rawStates
              .whereType<Map>()
              .map((e) => StateItem.fromJson(_stringKeyed(e)))
              .where((s) => s.name.isNotEmpty)
              .toList()
          : <StateItem>[];

      return ApiResult(
        success: true,
        message: 'OK',
        data: states,
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiResult(success: false, message: _friendlyError(error));
    }
  }

  Future<ApiResult<List<String>>> getCities(String country, String state) async {
    try {
      final uri = Uri.parse('$_baseUrl/state/cities');
      final response = await _client
          .post(
            uri,
            headers: const {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({'country': country, 'state': state}),
          )
          .timeout(const Duration(seconds: 20));

      final decoded = _decode(response);
      if (decoded == null) {
        return ApiResult(
          success: false,
          message: _unexpectedMessage(response),
          statusCode: response.statusCode,
        );
      }
      if (_hasError(decoded)) {
        return ApiResult(
          success: false,
          message: _errorMessage(decoded),
          statusCode: response.statusCode,
        );
      }

      final raw = decoded['data'];
      final cities = raw is List
          ? raw.map((e) => e?.toString() ?? '').where((s) => s.isNotEmpty).toList()
          : <String>[];

      return ApiResult(
        success: true,
        message: 'OK',
        data: cities,
        statusCode: response.statusCode,
      );
    } catch (error) {
      return ApiResult(success: false, message: _friendlyError(error));
    }
  }

  Map<String, dynamic> _stringKeyed(Map value) =>
      value.map((key, value) => MapEntry(key.toString(), value));

  Map<String, dynamic>? _decode(http.Response response) {
    if (response.body.isEmpty) return null;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is Map ? _stringKeyed(decoded) : null;
    } on FormatException {
      return null;
    }
  }

  bool _hasError(Map<String, dynamic> decoded) => decoded['error'] == true;

  String _errorMessage(Map<String, dynamic> decoded) {
    final msg = decoded['msg']?.toString().trim() ?? '';
    return msg.isNotEmpty ? msg : 'Request failed.';
  }

  String _unexpectedMessage(http.Response response) =>
      'Unexpected response from location service (${response.statusCode}).';

  String _friendlyError(Object error) {
    if (error is TimeoutException) {
      return 'The location service took too long to respond. Please try again.';
    }
    if (error is SocketException) {
      return 'Cannot reach the location service. Please check your internet connection.';
    }
    if (error is HandshakeException || error is TlsException) {
      return 'Secure connection to the location service failed.';
    }
    if (error is http.ClientException) {
      return 'Unable to connect to the location service.';
    }
    return 'Something went wrong while fetching location data.';
  }
}

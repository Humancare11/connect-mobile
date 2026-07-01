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
  static const _dialCodeDataUrl = 'https://raw.githubusercontent.com/mledoze/countries/master/countries.json';

  final http.Client _client;
  final Map<String, String> _dialCodeCache = {};

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

  Future<ApiResult<String>> getDialCode(String country, {String? iso2}) async {
    final cacheKey = '${country.trim().toLowerCase()}::${(iso2 ?? '').trim().toLowerCase()}';
    final cached = _dialCodeCache[cacheKey];
    if (cached != null && cached.isNotEmpty) {
      return ApiResult(success: true, message: 'OK', data: cached);
    }

    try {
      final response = await _client
          .get(Uri.parse(_dialCodeDataUrl), headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return ApiResult(success: false, message: 'Unable to fetch country dial codes.');
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! List) {
        return ApiResult(success: false, message: 'Unexpected country dial code response.');
      }

      final normalizedCountry = _normalizeCountryText(country);
      for (final entry in decoded) {
        if (entry is! Map) continue;
        final item = _stringKeyed(entry);
        final cca2 = item['cca2']?.toString() ?? '';
        final cca3 = item['cca3']?.toString() ?? '';
        final idd = item['idd'];
        final root = idd is Map ? idd['root']?.toString() ?? '' : '';
        final suffixes = idd is Map ? idd['suffixes'] : null;
        final suffix = suffixes is List
            ? suffixes.whereType<Object>().map((e) => e.toString()).join()
            : '';

        final names = <String>{};
        final nameMap = item['name'];
        if (nameMap is Map) {
          names.addAll([
            nameMap['common']?.toString() ?? '',
            nameMap['official']?.toString() ?? '',
          ]);
        }
        final altSpellings = item['altSpellings'];
        if (altSpellings is List) {
          for (final value in altSpellings) {
            if (value is String && value.isNotEmpty) {
              names.add(value);
            }
          }
        }

        final normalizedIso2 = _normalizeCountryText(iso2 ?? '');
        final hasIsoMatch = normalizedIso2.isNotEmpty &&
            (normalizedIso2 == _normalizeCountryText(cca2) || normalizedIso2 == _normalizeCountryText(cca3));

        final matchesCountry = normalizedCountry.isEmpty
            ? hasIsoMatch
            : names.any((name) => _countryNameMatches(name, normalizedCountry)) ||
                hasIsoMatch ||
                (cca2.isNotEmpty && _countryNameMatches(cca2, normalizedCountry)) ||
                (cca3.isNotEmpty && _countryNameMatches(cca3, normalizedCountry));

        if (matchesCountry && root.isNotEmpty) {
          final dialCode = root + suffix;
          _dialCodeCache[cacheKey] = dialCode;
          return ApiResult(success: true, message: 'OK', data: dialCode);
        }
      }

      return ApiResult(success: false, message: 'Unable to determine country dial code.');
    } catch (error) {
      return ApiResult(success: false, message: _friendlyError(error));
    }
  }

  Map<String, dynamic> _stringKeyed(Map value) =>
      value.map((key, value) => MapEntry(key.toString(), value));

  String _normalizeCountryText(String value) {
    final buffer = StringBuffer();
    for (final rune in value.toLowerCase().runes) {
      if (rune >= 0x0300 && rune <= 0x036F) continue;
      if (rune >= 0x1AB0 && rune <= 0x1AFF) continue;
      if (rune >= 0x1DC0 && rune <= 0x1DFF) continue;
      if (rune >= 0x20D0 && rune <= 0x20FF) continue;
      if (rune >= 0xFE20 && rune <= 0xFE2F) continue;
      buffer.write(String.fromCharCode(rune));
    }
    return buffer.toString().replaceAll(RegExp(r"[^a-z0-9\s]"), ' ').replaceAll(RegExp(r"\s+"), ' ').trim();
  }

  bool _countryNameMatches(String value, String target) {
    final current = _normalizeCountryText(value);
    final expected = _normalizeCountryText(target);
    if (current.isEmpty || expected.isEmpty) return false;
    if (current == expected) return true;
    return current.contains(expected) || expected.contains(current);
  }

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

import '../models/api_result.dart';
import 'api_client.dart';

class ApiService {
  ApiService._();

  static final ApiService instance = ApiService._();

  final ApiClient _client = ApiClient();

  Future<dynamic> get(String path, {bool silent = false}) async {
    final result = await _client.get(_normalizePath(path), null, silent);
    return _unwrap(result);
  }

  Future<dynamic> post(
    String path,
    Map<String, dynamic> body, {
    bool silent = false,
  }) async {
    final result = await _client.post(_normalizePath(path), body, silent: silent);
    return _unwrap(result);
  }

  Future<dynamic> put(
    String path,
    Map<String, dynamic> body, {
    bool silent = false,
  }) async {
    final result = await _client.put(_normalizePath(path), body, silent: silent);
    return _unwrap(result);
  }

  /// See [ApiClient.refreshAccessToken] — the only call in the app that
  /// authenticates with the refresh token instead of the access token.
  Future<bool> refreshAccessToken(String role) =>
      _client.refreshAccessToken(role);

  String _normalizePath(String path) {
    final normalized = path.trim();
    if (normalized.startsWith('/api/')) {
      return normalized.substring(4);
    }
    return normalized;
  }

  dynamic _unwrap(ApiResult<Map<String, dynamic>> result) {
    if (!result.success) {
      throw Exception(result.message);
    }

    final data = result.data ?? <String, dynamic>{};
    final nestedData = _asMap(data['data']);
    if (nestedData.isNotEmpty) return nestedData;

    final appointment = _asMap(data['appointment']);
    if (appointment.isNotEmpty) return appointment;

    return data;
  }

  Map<String, dynamic> _asMap(dynamic value) {
    if (value is Map) {
      return value.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }
}

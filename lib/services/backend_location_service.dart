import '../models/api_result.dart';
import 'api_client.dart';

/// Country / state / city lists from the app's own backend
/// (`/api/locations/...`) — the same source, and the same names, the web
/// profile page uses. The backend validates a saved country/state against
/// this exact list, so profile screens must pick from it rather than
/// accepting free text.
class BackendLocationService {
  BackendLocationService({ApiClient? client}) : _client = client ?? ApiClient();

  final ApiClient _client;

  Future<ApiResult<List<BackendCountry>>> countries() async {
    final result = await _client.get('/locations/countries', null, true);
    if (!result.success) return _failure(result);
    final raw = result.data?['countries'];
    final list = raw is List
        ? raw
              .whereType<Map>()
              .map(
                (m) => BackendCountry(
                  name: m['name']?.toString() ?? '',
                  isoCode: m['isoCode']?.toString() ?? '',
                ),
              )
              .where((c) => c.name.isNotEmpty)
              .toList()
        : <BackendCountry>[];
    return ApiResult(success: true, message: '', data: list);
  }

  Future<ApiResult<List<String>>> states(String country) async {
    final result = await _client.get(
      '/locations/states/${Uri.encodeComponent(country)}',
      null,
      true,
    );
    if (!result.success) return _failure(result);
    final raw = result.data?['states'];
    final list = raw is List
        ? raw
              .whereType<Map>()
              .map((m) => m['name']?.toString() ?? '')
              .where((n) => n.isNotEmpty)
              .toList()
        : <String>[];
    return ApiResult(success: true, message: '', data: list);
  }

  Future<ApiResult<List<String>>> cities(String country, String state) async {
    final result = await _client.get(
      '/locations/cities/${Uri.encodeComponent(country)}/${Uri.encodeComponent(state)}',
      null,
      true,
    );
    if (!result.success) return _failure(result);
    final raw = result.data?['cities'];
    final list = raw is List
        ? raw.map((c) => c.toString()).where((n) => n.isNotEmpty).toList()
        : <String>[];
    return ApiResult(success: true, message: '', data: list);
  }

  ApiResult<List<T>> _failure<T>(ApiResult<Map<String, dynamic>> result) {
    return ApiResult<List<T>>(
      success: false,
      message: result.message,
      statusCode: result.statusCode,
    );
  }
}

class BackendCountry {
  const BackendCountry({required this.name, required this.isoCode});

  final String name;
  final String isoCode;
}

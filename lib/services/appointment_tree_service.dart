import '../models/api_result.dart';
import '../models/appointment_tree_model.dart';
import 'api_client.dart';

class AppointmentTreeService {
  AppointmentTreeService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;

  // Shared across instances — every call site constructs its own
  // AppointmentTreeService() — so callers that mount around the same time
  // (the Home screen's specialties row and booking card both fetch this on
  // build) reuse one in-flight/cached request instead of firing duplicate
  // GETs for data that rarely changes. Only successful responses are
  // cached, so a failed fetch never gets "stuck" — the next call (e.g. a
  // Retry tap) always goes to the network again.
  static ApiResult<List<AppointmentTreeCategory>>? _cachedResult;
  static DateTime? _cachedAt;
  static Future<ApiResult<List<AppointmentTreeCategory>>>? _inFlight;
  static const _cacheTtl = Duration(minutes: 2);

  // Drops the cached tree so the next fetchTree() call always hits the
  // network. Used when a category/specialty turns out to be stale — e.g.
  // the backend rejects a booking's priceRef as unrecognized because the
  // category was renamed/removed after this cache was populated — so the
  // "go back and reselect" recovery path actually picks up current data
  // instead of replaying the same stale (and now-invalid) tree.
  static void invalidateCache() {
    _cachedResult = null;
    _cachedAt = null;
  }

  Future<ApiResult<List<AppointmentTreeCategory>>> fetchTree() {
    final cached = _cachedResult;
    final cachedAt = _cachedAt;
    if (cached != null &&
        cachedAt != null &&
        DateTime.now().difference(cachedAt) < _cacheTtl) {
      return Future.value(cached);
    }

    return _inFlight ??= _fetchAndCache();
  }

  Future<ApiResult<List<AppointmentTreeCategory>>> _fetchAndCache() async {
    try {
      final result = await _apiClient.get('/appointment-tree');
      if (!result.success) {
        return ApiResult<List<AppointmentTreeCategory>>(
          success: false,
          message: result.message,
          statusCode: result.statusCode,
          raw: result.raw,
        );
      }

      final categories = parseAppointmentTree(result.data ?? result.raw);
      final parsed = ApiResult<List<AppointmentTreeCategory>>(
        success: true,
        message: result.message,
        data: categories,
        raw: result.raw,
        statusCode: result.statusCode,
      );
      _cachedResult = parsed;
      _cachedAt = DateTime.now();
      return parsed;
    } finally {
      _inFlight = null;
    }
  }
}

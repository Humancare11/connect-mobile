import 'dart:typed_data';

import '../models/api_result.dart';
import '../models/visit_note_models.dart';
import 'api_client.dart';
import 'backend_location_service.dart';
import 'document_signature_service.dart';

/// The patient's own finalised Visit Notes. Read only — the doctor writes and
/// signs them (and adds amendments) on the web.
///
/// Endpoints (all patient-scoped on the server; someone else's id is a 404):
///  * `GET /consultation-reports/mine`               -> `{ reports, pending }`
///  * `GET /consultation-reports/mine/:id`           -> `{ report }`
///  * `GET /consultation-reports/mine/:id/signature` -> PNG bytes
class VisitNotesService {
  VisitNotesService({
    ApiClient? apiClient,
    BackendLocationService? locations,
  }) : _apiClient = apiClient ?? ApiClient(),
       _locations = locations ?? BackendLocationService();

  final ApiClient _apiClient;
  final BackendLocationService _locations;

  // The image never changes for a report, so it is kept (in memory only: the
  // backend marks it `no-store`) for the life of this object.
  final Map<String, Uint8List> _signatures = {};
  final Map<String, Future<Uint8List?>> _signaturesInFlight = {};
  Map<String, String>? _countryNames;

  static String _id(String id) => Uri.encodeComponent(id.trim());

  Future<ApiResult<VisitNotesSnapshot>> fetchMine({bool silent = false}) async {
    final result = await _apiClient.get(
      '/consultation-reports/mine',
      null,
      silent,
    );
    if (!result.success) {
      return ApiResult<VisitNotesSnapshot>(
        success: false,
        message: result.statusCode == 401
            ? 'Session expired. Please log in again.'
            : (result.message.isNotEmpty
                  ? result.message
                  : 'Could not load your Visit Notes.'),
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }
    return ApiResult<VisitNotesSnapshot>(
      success: true,
      message: result.message,
      data: VisitNotesSnapshot.fromJson(result.data ?? result.raw),
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<VisitNoteReport>> fetchOne(
    String id, {
    bool silent = false,
  }) async {
    final result = await _apiClient.get(
      '/consultation-reports/mine/${_id(id)}',
      null,
      silent,
    );
    final body = result.data ?? result.raw;
    if (!result.success || body['report'] is! Map) {
      return ApiResult<VisitNoteReport>(
        success: false,
        message: result.message,
        raw: result.raw,
        statusCode: result.success ? 404 : result.statusCode,
      );
    }
    return ApiResult<VisitNoteReport>(
      success: true,
      message: result.message,
      data: VisitNoteReport.fromJson(body['report']),
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  /// The signature already loaded for this report, if any.
  Uint8List? cachedSignature(String id) => _signatures[id];

  /// Loads (or returns the cached) signature; `null` when unavailable. Every
  /// failure — 404, network error, a body that is not a PNG — is `null`, and
  /// only successes are cached, so a failed load can simply be retried.
  Future<Uint8List?> fetchSignature(String id) {
    final hit = _signatures[id];
    if (hit != null) return Future.value(hit);
    return _signaturesInFlight[id] ??= _loadSignature(id).whenComplete(() {
      _signaturesInFlight.remove(id);
    });
  }

  /// One more attempt if the first one failed.
  Future<Uint8List?> fetchSignatureWithRetry(String id) async =>
      await fetchSignature(id) ?? await fetchSignature(id);

  Future<Uint8List?> _loadSignature(String id) async {
    if (id.trim().isEmpty) return null;
    final result = await _apiClient.getBytes(
      '/consultation-reports/mine/${_id(id)}/signature',
    );
    if (!result.success || !DocumentSignatureService.isValidPng(result.bytes)) {
      return null;
    }
    _signatures[id] = result.bytes;
    return result.bytes;
  }

  /// Web shows the physician's country as a name (ISO code -> name). The app
  /// resolves it from the same backend country list the profile screen uses;
  /// if that is unavailable, or the value is not a known code, the value is
  /// shown as it is.
  Future<String> countryName(String value) async {
    final code = value.trim();
    if (code.isEmpty) return '';
    if (code.length != 2) return code;
    try {
      var names = _countryNames;
      if (names == null) {
        final result = await _locations.countries();
        final list = result.data;
        if (!result.success || list == null) return code;
        names = {
          for (final c in list)
            if (c.isoCode.isNotEmpty) c.isoCode.toUpperCase(): c.name,
        };
        _countryNames = names;
      }
      return names[code.toUpperCase()] ?? code;
    } catch (_) {
      return code;
    }
  }
}

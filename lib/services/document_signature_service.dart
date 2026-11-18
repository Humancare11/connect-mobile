import 'dart:typed_data';

import 'api_client.dart';

enum SignedDocumentKind { prescription, certificate }

/// Loads a doctor's signature image for one of the patient's own signed
/// prescriptions or certificates
/// (`GET /medical/my-prescriptions/:id/signature`, `/my-certificates/:id/signature`).
///
/// The backend answers with a PNG (at most 1 MB), or 404 for an unsigned
/// document. Every failure — 404, network error, or a body that is not a PNG —
/// is reported as `null`. Only successes are cached (in memory, for the life
/// of this object): the backend marks the image `no-store`, so nothing is
/// written to disk, and a failed load can simply be retried.
class DocumentSignatureService {
  DocumentSignatureService({ApiClient? apiClient})
    : _apiClient = apiClient ?? ApiClient();

  static const int maxBytes = 1024 * 1024;
  static const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

  final ApiClient _apiClient;
  final Map<String, Uint8List> _cache = {};
  final Map<String, Future<Uint8List?>> _inFlight = {};

  static String _key(SignedDocumentKind kind, String id) => '${kind.name}:$id';

  static String _path(SignedDocumentKind kind, String id) {
    final segment = kind == SignedDocumentKind.prescription
        ? 'my-prescriptions'
        : 'my-certificates';
    return '/medical/$segment/${Uri.encodeComponent(id)}/signature';
  }

  /// The signature already loaded for this document, if any.
  Uint8List? cached(SignedDocumentKind kind, String id) =>
      _cache[_key(kind, id)];

  /// Loads (or returns the cached) signature; `null` when unavailable.
  Future<Uint8List?> fetch(SignedDocumentKind kind, String id) {
    final key = _key(kind, id);
    final hit = _cache[key];
    if (hit != null) return Future.value(hit);
    return _inFlight[key] ??= _load(kind, id, key).whenComplete(() {
      _inFlight.remove(key);
    });
  }

  /// Like [fetch], with one more attempt if the first one failed — used
  /// before exporting a PDF, where a signed document must never silently
  /// lose its signature.
  Future<Uint8List?> fetchWithRetry(SignedDocumentKind kind, String id) async {
    return await fetch(kind, id) ?? await fetch(kind, id);
  }

  Future<Uint8List?> _load(SignedDocumentKind kind, String id, String key) async {
    if (id.trim().isEmpty) return null;

    final result = await _apiClient.getBytes(_path(kind, id));
    if (!result.success || !isValidPng(result.bytes)) return null;

    _cache[key] = result.bytes;
    return result.bytes;
  }

  /// True for a non-empty PNG within the backend's size limit.
  static bool isValidPng(Uint8List bytes) {
    if (bytes.length <= _pngMagic.length || bytes.length > maxBytes) {
      return false;
    }
    for (var i = 0; i < _pngMagic.length; i++) {
      if (bytes[i] != _pngMagic[i]) return false;
    }
    return true;
  }
}

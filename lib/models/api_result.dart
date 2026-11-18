import 'dart:typed_data';

class ApiResult<T> {
  const ApiResult({
    required this.success,
    required this.message,
    this.data,
    this.raw = const <String, dynamic>{},
    this.statusCode = 0,
  });

  final bool success;
  final String message;
  final T? data;
  final Map<String, dynamic> raw;
  final int statusCode;
}

/// Result of a binary GET (see `ApiClient.getBytes`), e.g. an image.
class ApiBytesResult {
  const ApiBytesResult({
    required this.statusCode,
    required this.bytes,
    this.contentType = '',
    this.message = '',
  });

  final int statusCode;
  final Uint8List bytes;
  final String contentType;
  final String message;

  bool get success => statusCode >= 200 && statusCode < 300;
}

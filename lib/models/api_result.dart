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

class ServiceModel {
  const ServiceModel({
    required this.id,
    required this.name,
    required this.description,
    required this.icon,
    required this.price,
    this.priceEur,
    this.priceGbp,
  });

  final String id;
  final String name;
  final String description;
  final String icon;
  final num price;

  // The service's own EUR / GBP prices (`GET /services` adds them while
  // multi-currency is on). Null = not set, so the USD `price` applies.
  final num? priceEur;
  final num? priceGbp;

  factory ServiceModel.fromJson(Map<String, dynamic> json) {
    return ServiceModel(
      id: _firstString(json, const ['id', '_id', 'slug', 'key']),
      name: _firstString(json, const [
        'name',
        'title',
        'serviceName',
        'label',
      ]),
      description: _firstString(json, const [
        'description',
        'desc',
        'subtitle',
        'details',
      ]),
      icon: _firstString(json, const ['icon', 'emoji', 'iconUrl', 'image']),
      price: _firstNum(json, const [
        'price',
        'cost',
        'amount',
        'consultationPrice',
        'servicePrice',
      ]),
      priceEur: _optionalNum(json['priceEur']),
      priceGbp: _optionalNum(json['priceGbp']),
    );
  }

  static num? _optionalNum(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }
}

List<ServiceModel> parseServices(dynamic response) {
  final items = _extractServiceList(response);
  return items
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .map(ServiceModel.fromJson)
      .where((service) => service.name.isNotEmpty)
      .toList();
}

List<dynamic> _extractServiceList(dynamic value) {
  if (value is List) return value;
  if (value is! Map) return const [];

  final json = value.map((key, value) => MapEntry(key.toString(), value));
  for (final key in const ['services', 'items', 'results']) {
    final list = json[key];
    if (list is List) return list;
  }

  final data = json['data'];
  if (data is List) return data;
  if (data is Map) return _extractServiceList(data);

  return const [];
}

String _firstString(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null) continue;
    final text = value.toString().trim();
    if (text.isNotEmpty) return text;
  }
  return '';
}

num _firstNum(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value;
    final parsed = num.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return 0;
}

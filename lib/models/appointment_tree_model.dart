class AppointmentTreeCategory {
  const AppointmentTreeCategory({
    required this.id,
    required this.label,
    required this.icon,
    required this.price,
    required this.specialties,
  });

  final String id;
  final String label;
  final String icon;
  final num price;
  final List<AppointmentTreeSpecialty> specialties;

  factory AppointmentTreeCategory.fromJson(Map<String, dynamic> json) {
    final label = _firstString(json, const [
      'label',
      'name',
      'title',
      'category',
      'categoryName',
    ]);
    final id = _firstString(json, const ['id', '_id', 'slug', 'key']);
    final price = _firstNum(json, const [
      'price',
      'cost',
      'amount',
      'consultationPrice',
      'categoryPrice',
    ]);
    final specialties =
        _firstList(json, const ['specialties', 'specs', 'children'])
            .map(AppointmentTreeSpecialty.fromAny)
            .whereType<AppointmentTreeSpecialty>()
            .toList();

    return AppointmentTreeCategory(
      id: id.isNotEmpty ? id : label,
      label: label,
      icon: _firstString(json, const [
        'icon',
        'emoji',
        'categoryIcon',
        'categoryEmoji',
        'iconUrl',
        'image',
      ]),
      price: price,
      specialties: specialties,
    );
  }

  Map<String, dynamic> toUiMap() {
    return {
      'id': id,
      'label': label,
      'icon': icon,
      'cost': price,
      'specs': specialties
          .map((specialty) => specialty.toUiMap(price))
          .toList(),
    };
  }
}

class AppointmentTreeSpecialty {
  const AppointmentTreeSpecialty({
    required this.name,
    required this.icon,
    required this.live,
    required this.count,
    required this.conditions,
    this.price,
  });

  final String name;
  final String icon;
  final bool live;
  final String count;
  final List<AppointmentTreeCondition> conditions;

  // Null when the backend doesn't send a specialty-specific price for this
  // node — callers should fall back to the parent category's price rather
  // than treating a missing price as $0.
  final num? price;

  static AppointmentTreeSpecialty? fromAny(dynamic value) {
    if (value is String) {
      final name = value.trim();
      if (name.isEmpty) return null;
      return AppointmentTreeSpecialty(
        name: name,
        icon: '',
        live: false,
        count: '',
        conditions: const [],
      );
    }

    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final name = _firstString(json, const [
      'name',
      'label',
      'title',
      'specialty',
      'specialtyName',
    ]);
    if (name.isEmpty) return null;

    return AppointmentTreeSpecialty(
      name: name,
      icon: _firstString(json, const ['icon', 'emoji']),
      live: _firstBool(json, const ['live', 'isLive', 'active']),
      count: _firstString(json, const ['count', 'doctorCount', 'doctors']),
      price: _firstNumOrNull(json, const [
        'price',
        'cost',
        'amount',
        'specialtyPrice',
        'consultationPrice',
      ]),
      conditions: _firstList(json, const ['conditions', 'symptoms', 'items'])
          .map(AppointmentTreeCondition.fromAny)
          .whereType<AppointmentTreeCondition>()
          .toList(),
    );
  }

  Map<String, dynamic> toUiMap(num categoryPrice) {
    final effectivePrice = price ?? categoryPrice;
    return {
      'name': name,
      'icon': icon,
      'live': live,
      'count': count,
      'cost': effectivePrice,
      'conditions': conditions.map((condition) {
        return [condition.name, condition.icon, condition.price ?? effectivePrice];
      }).toList(),
    };
  }
}

class AppointmentTreeCondition {
  const AppointmentTreeCondition({
    required this.name,
    required this.icon,
    this.price,
  });

  final String name;
  final String icon;

  // Null unless the backend sends the condition as an object with its own
  // price — the string/tuple forms carry no pricing data.
  final num? price;

  static AppointmentTreeCondition? fromAny(dynamic value) {
    if (value is String) {
      final name = value.trim();
      if (name.isEmpty) return null;
      return AppointmentTreeCondition(name: name, icon: '');
    }

    if (value is List && value.isNotEmpty) {
      final name = value.first?.toString().trim() ?? '';
      if (name.isEmpty) return null;
      return AppointmentTreeCondition(
        name: name,
        icon: value.length > 1 ? value[1]?.toString().trim() ?? '' : '',
      );
    }

    if (value is! Map) return null;
    final json = value.map((key, value) => MapEntry(key.toString(), value));
    final name = _firstString(json, const [
      'name',
      'label',
      'title',
      'condition',
      'conditionName',
      'symptom',
    ]);
    if (name.isEmpty) return null;

    return AppointmentTreeCondition(
      name: name,
      icon: _firstString(json, const ['icon', 'emoji']),
      price: _firstNumOrNull(json, const [
        'price',
        'cost',
        'amount',
        'conditionPrice',
        'consultationPrice',
      ]),
    );
  }
}

List<AppointmentTreeCategory> parseAppointmentTree(dynamic response) {
  final categories = _extractCategoryList(response);
  return categories
      .whereType<Map>()
      .map((item) => item.map((key, value) => MapEntry(key.toString(), value)))
      .map(AppointmentTreeCategory.fromJson)
      .where((category) => category.label.isNotEmpty)
      .toList();
}

List<dynamic> _extractCategoryList(dynamic value) {
  if (value is List) return value;
  if (value is! Map) return const [];

  final json = value.map((key, value) => MapEntry(key.toString(), value));
  for (final key in const [
    'categories',
    'appointmentTree',
    'tree',
    'items',
    'results',
  ]) {
    final list = json[key];
    if (list is List) return list;
  }

  final data = json['data'];
  if (data is List) return data;
  if (data is Map) return _extractCategoryList(data);

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

num? _firstNumOrNull(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is num) return value;
    final parsed = num.tryParse(value?.toString() ?? '');
    if (parsed != null) return parsed;
  }
  return null;
}

bool _firstBool(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is bool) return value;
    final normalized = value?.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
  }
  return false;
}

List<dynamic> _firstList(Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value is List) return value;
  }
  return const [];
}

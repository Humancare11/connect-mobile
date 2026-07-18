// Shared helpers for defensively parsing loosely-typed backend JSON
// responses, where the exact field name and nesting shape can vary across
// endpoints (e.g. a token might arrive as `token`, `accessToken`, or nested
// under `data.user.token`). Used by auth_service.dart, auth_response.dart
// (UserModel), payment_service.dart, and ticket_service.dart — each of
// those files previously defined its own identical private copy of these
// functions, risking silent drift if one copy was ever fixed or extended
// without the others.

Map<String, dynamic> asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }
  return <String, dynamic>{};
}

Map<String, dynamic> firstNonEmptyMap(List<dynamic> values) {
  for (final value in values) {
    final map = asMap(value);
    if (map.isNotEmpty) return map;
  }
  return <String, dynamic>{};
}

String firstNonEmptyString(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';
    if (text.isNotEmpty) return text;
  }
  return '';
}

Map<String, dynamic> findFirstMapByKeys(dynamic value, Set<String> keys) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final map = asMap(entry.value);
      if (keys.contains(key) && map.isNotEmpty) return map;

      final nested = findFirstMapByKeys(entry.value, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  if (value is List) {
    for (final item in value) {
      final nested = findFirstMapByKeys(item, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  return <String, dynamic>{};
}

String findFirstStringByKeys(dynamic value, Set<String> keys) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      if (keys.contains(key)) {
        final entryValue = entry.value;
        if (entryValue is String || entryValue is num || entryValue is bool) {
          final text = entryValue.toString().trim();
          if (text.isNotEmpty) return text;
        }
      }

      final nested = findFirstStringByKeys(entry.value, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  if (value is List) {
    for (final item in value) {
      final nested = findFirstStringByKeys(item, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  return '';
}

class AuthResponse {
  const AuthResponse({
    required this.token,
    required this.user,
    this.resetToken = '',
  });

  final String token;
  final UserModel user;
  final String resetToken;
}

class UserModel {
  const UserModel({
    required this.id,
    required this.name,
    required this.email,
    required this.role,
    required this.mobile,
    required this.dob,
    required this.gender,
    required this.country,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String mobile;
  final String dob;
  final String gender;
  final String country;

  factory UserModel.fromMaps(
    Map<String, dynamic> data,
    Map<String, dynamic> responseData,
  ) {
    final nestedData = _asMap(responseData['data']);
    final user = _firstNonEmptyMap([
      data['user'],
      data['patient'],
      data['profile'],
      data['account'],
      responseData['user'],
      responseData['patient'],
      responseData['profile'],
      responseData['account'],
      nestedData['user'],
      nestedData['patient'],
      nestedData['profile'],
      nestedData['account'],
      _findFirstMapByKeys(data, const {
        'user',
        'patient',
        'profile',
        'account',
      }),
    ]);

    return UserModel(
      id: _firstNonEmptyString([
        user['_id'],
        user['id'],
        data['userId'],
        responseData['userId'],
      ]),
      name: _firstNonEmptyString([
        user['name'],
        user['fullName'],
        data['name'],
        responseData['name'],
      ]),
      email: _firstNonEmptyString([
        user['email'],
        data['email'],
        responseData['email'],
      ]),
      role: _firstNonEmptyString([
        user['role'],
        user['userRole'],
        data['role'],
        responseData['role'],
        'patient',
      ]),
      mobile: _firstNonEmptyString([
        user['mobile'],
        user['phone'],
        user['phoneNumber'],
        data['mobile'],
        responseData['mobile'],
      ]),
      dob: _firstNonEmptyString([
        user['dob'],
        data['dob'],
        responseData['dob'],
      ]),
      gender: _firstNonEmptyString([
        user['gender'],
        data['gender'],
        responseData['gender'],
      ]),
      country: _firstNonEmptyString([
        user['country'],
        data['country'],
        responseData['country'],
      ]),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map) {
    return value.map((key, value) => MapEntry(key.toString(), value));
  }

  return <String, dynamic>{};
}

Map<String, dynamic> _firstNonEmptyMap(List<dynamic> values) {
  for (final value in values) {
    final map = _asMap(value);
    if (map.isNotEmpty) return map;
  }

  return <String, dynamic>{};
}

String _firstNonEmptyString(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';

    if (text.isNotEmpty) {
      return text;
    }
  }

  return '';
}

Map<String, dynamic> _findFirstMapByKeys(dynamic value, Set<String> keys) {
  if (value is Map) {
    for (final entry in value.entries) {
      final key = entry.key.toString();
      final map = _asMap(entry.value);
      if (keys.contains(key) && map.isNotEmpty) return map;

      final nested = _findFirstMapByKeys(entry.value, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  if (value is List) {
    for (final item in value) {
      final nested = _findFirstMapByKeys(item, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  return <String, dynamic>{};
}

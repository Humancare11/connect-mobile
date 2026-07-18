import '../utils/json_helpers.dart';

class AuthResponse {
  const AuthResponse({
    required this.token,
    required this.user,
    this.refreshToken = '',
    this.resetToken = '',
  });

  final String token;
  final UserModel user;
  final String refreshToken;
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
    required this.state,
    required this.city,
    required this.location,
  });

  final String id;
  final String name;
  final String email;
  final String role;
  final String mobile;
  final String dob;
  final String gender;
  final String country;
  final String state;
  final String city;
  final String location;

  factory UserModel.fromMaps(
    Map<String, dynamic> data,
    Map<String, dynamic> responseData,
  ) {
    final nestedData = asMap(responseData['data']);
    final user = firstNonEmptyMap([
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
      findFirstMapByKeys(data, const {
        'user',
        'patient',
        'profile',
        'account',
      }),
    ]);

    return UserModel(
      id: firstNonEmptyString([
        user['_id'],
        user['id'],
        data['userId'],
        responseData['userId'],
      ]),
      name: firstNonEmptyString([
        user['name'],
        user['fullName'],
        data['name'],
        responseData['name'],
      ]),
      email: firstNonEmptyString([
        user['email'],
        data['email'],
        responseData['email'],
      ]),
      role: firstNonEmptyString([
        user['role'],
        user['userRole'],
        data['role'],
        responseData['role'],
        'patient',
      ]),
      mobile: firstNonEmptyString([
        user['mobile'],
        user['phone'],
        user['phoneNumber'],
        data['mobile'],
        responseData['mobile'],
      ]),
      dob: firstNonEmptyString([
        user['dob'],
        data['dob'],
        responseData['dob'],
      ]),
      gender: firstNonEmptyString([
        user['gender'],
        data['gender'],
        responseData['gender'],
      ]),
      country: firstNonEmptyString([
        user['country'],
        data['country'],
        responseData['country'],
      ]),
      state: firstNonEmptyString([
        user['state'],
        user['province'],
        data['state'],
        responseData['state'],
      ]),
      city: firstNonEmptyString([
        user['city'],
        data['city'],
        responseData['city'],
      ]),
      location: firstNonEmptyString([
        user['location'],
        data['location'],
        responseData['location'],
      ]),
    );
  }
}

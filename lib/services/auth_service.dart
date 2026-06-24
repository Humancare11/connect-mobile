import 'package:google_sign_in/google_sign_in.dart';

import '../models/api_result.dart';
import '../models/auth_response.dart';
import 'api_client.dart';
import 'token_storage_service.dart';

class AuthService {
  AuthService({ApiClient? apiClient, TokenStorageService? tokenStorage})
    : _apiClient = apiClient ?? ApiClient(),
      _tokenStorage = tokenStorage ?? const TokenStorageService();

  final ApiClient _apiClient;
  final TokenStorageService _tokenStorage;
  static bool _googleInitialized = false;
  static const String _updateProfileEndpoint = '/auth/update-profile';
  static const List<String> _profileEndpoints = [
    '/auth/profile',
    '/auth/me',
    '/user/profile',
    '/user/me',
    '/patient/profile',
    '/profile',
    '/me',
  ];

  Future<ApiResult<AuthResponse>> login({
    required String email,
    required String password,
  }) async {
    final result = await _apiClient.post('/auth/login', {
      'email': email,
      'password': password,
    });

    return _authResult(result, 'Login response did not include a valid token.');
  }

  Future<ApiResult<void>> sendRegisterOtp({
    required String email,
    required String password,
    required String dob,
    required bool privacyConsent,
    required bool hipaaConsent,
  }) async {
    final result = await _apiClient.post('/auth/send-register-otp', {
      'email': email,
      'password': password,
      'dob': dob,
      'privacyConsent': privacyConsent,
      'hipaaConsent': hipaaConsent,
    });

    return ApiResult<void>(
      success: result.success,
      message: result.success ? 'OTP sent successfully.' : result.message,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<AuthResponse>> register({
    required String name,
    required String email,
    required String mobile,
    required String dob,
    required String gender,
    required String country,
    required String password,
    required bool privacyConsent,
    required bool hipaaConsent,
    required String otp,
  }) async {
    final result = await _apiClient.post('/auth/register', {
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      'password': password,
      'otp': otp.trim(),
      'privacyConsent': privacyConsent,
      'hipaaConsent': hipaaConsent,
      'dob': dob.trim(),
      if (mobile.trim().isNotEmpty) 'mobile': mobile.trim(),
      if (gender.trim().isNotEmpty) 'gender': gender.trim(),
      if (country.trim().isNotEmpty) 'country': country.trim(),
    });

    return _authResult(
      result,
      'Registration response did not include a token.',
    );
  }

  Future<ApiResult<void>> sendForgotOtp(String email) async {
    final result = await _apiClient.post('/auth/send-forgot-otp', {
      'email': email,
    });

    return ApiResult<void>(
      success: result.success,
      message: result.success ? 'OTP sent successfully.' : result.message,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<AuthResponse>> verifyForgotOtp({
    required String email,
    required String otp,
  }) async {
    final result = await _apiClient.post('/auth/verify-forgot-otp', {
      'email': email,
      'otp': otp,
    });

    final data = result.data ?? <String, dynamic>{};
    final responseData = _asMap(data['data']);
    final resetToken = _firstNonEmptyString([
      data['resetToken'],
      responseData['resetToken'],
    ]);

    if (!result.success) {
      return ApiResult<AuthResponse>(
        success: false,
        message: result.message.isNotEmpty ? result.message : 'Invalid OTP.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    if (resetToken.isEmpty) {
      return ApiResult<AuthResponse>(
        success: false,
        message: 'OTP verified but reset token was missing.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    return ApiResult<AuthResponse>(
      success: true,
      message: result.message,
      data: AuthResponse(
        token: '',
        resetToken: resetToken,
        user: UserModel.fromMaps(data, responseData),
      ),
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<void>> resetPassword({
    required String resetToken,
    required String newPassword,
  }) async {
    final result = await _apiClient.post('/auth/reset-password', {
      'resetToken': resetToken,
      'newPassword': newPassword,
    });

    return ApiResult<void>(
      success: result.success,
      message: result.success
          ? 'Password reset successfully! Please sign in.'
          : result.message,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<void>> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    final result = await _apiClient.put('/auth/change-password', {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });

    return ApiResult<void>(
      success: result.success,
      message: result.message,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<AuthResponse>> googleLogin() async {
    try {
      final googleSignIn = GoogleSignIn.instance;
      if (!_googleInitialized) {
        await googleSignIn.initialize();
        _googleInitialized = true;
      }

      const scopes = ['openid', 'profile', 'email'];
      final account = await googleSignIn.authenticate(scopeHint: scopes);
      final authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      final accessToken = authorization.accessToken;

      if (accessToken.isEmpty) {
        return const ApiResult<AuthResponse>(
          success: false,
          message: 'Google Sign-In did not return an access token.',
        );
      }

      final result = await _apiClient.post('/auth/google', {
        'accessToken': accessToken,
      });

      return _authResult(result, 'Google Sign-In response was invalid.');
    } catch (error) {
      return const ApiResult<AuthResponse>(
        success: false,
        message: 'Google Sign-In failed.',
      );
    }
  }

  Future<void> saveSession(AuthResponse authResponse) async {
    await _tokenStorage.saveToken(authResponse.token);
    if (authResponse.refreshToken.isNotEmpty) {
      await _tokenStorage.saveRefreshToken(authResponse.refreshToken);
    }
    await _tokenStorage.saveUserProfile(
      userId: authResponse.user.id,
      name: authResponse.user.name,
      email: authResponse.user.email,
      role: authResponse.user.role,
      mobile: authResponse.user.mobile,
      dob: authResponse.user.dob,
      gender: authResponse.user.gender,
      country: authResponse.user.country,
      state: authResponse.user.state,
      city: authResponse.user.city,
      location: authResponse.user.location,
    );
  }

  Future<ApiResult<Map<String, String>>> fetchCurrentProfile() async {
    ApiResult<Map<String, dynamic>>? lastFailure;

    for (final endpoint in _profileEndpoints) {
      final result = await _apiClient.get(endpoint);

      if (result.success) {
        final profile = _normalizeProfile(
          result.data ?? <String, dynamic>{},
          const <String, String>{},
        );

        if (_hasMeaningfulProfile(profile)) {
          return ApiResult<Map<String, String>>(
            success: true,
            message: result.message,
            data: profile,
            raw: result.raw,
            statusCode: result.statusCode,
          );
        }
      }

      lastFailure = result;
      if (result.statusCode != 404 && result.statusCode != 405) {
        break;
      }
    }

    return ApiResult<Map<String, String>>(
      success: false,
      message: lastFailure?.message.isNotEmpty == true
          ? lastFailure!.message
          : 'Unable to fetch profile from server.',
      raw: lastFailure?.raw ?? const <String, dynamic>{},
      statusCode: lastFailure?.statusCode ?? 0,
    );
  }

  Future<ApiResult<Map<String, String>>> updateProfile({
    required String userId,
    required String name,
    required String email,
    required String role,
    required String mobile,
    required String dob,
    required String gender,
    required String country,
    String state = '',
    String city = '',
    String location = '',
  }) async {
    final current = await _tokenStorage.getUserProfile();
    final requestData = <String, String>{
      'userId': userId,
      'name': name,
      'email': email,
      'role': role,
      'mobile': mobile,
      'dob': dob,
      'gender': gender,
      'country': country,
      'state': state,
      'city': city,
      'location': location,
    };

    final mergedFallback = <String, String>{...current, ...requestData};
    final payload = <String, dynamic>{
      'name': name.trim(),
      'email': email.trim().toLowerCase(),
      if (mobile.trim().isNotEmpty) 'mobile': mobile.trim(),
      if (dob.trim().isNotEmpty) 'dob': dob.trim(),
      if (gender.trim().isNotEmpty) 'gender': gender.trim(),
      if (country.trim().isNotEmpty) 'country': country.trim(),
    };

    final result = await _apiClient.put(_updateProfileEndpoint, payload);
    if (!result.success) {
      return ApiResult<Map<String, String>>(
        success: false,
        message: result.message.isNotEmpty
            ? result.message
            : 'Unable to update profile on server.',
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    return _profileUpdateResult(result, mergedFallback);
  }

  ApiResult<Map<String, String>> _profileUpdateResult(
    ApiResult<Map<String, dynamic>> response,
    Map<String, String> fallback,
  ) {
    final profile = _normalizeProfile(
      response.data ?? <String, dynamic>{},
      fallback,
    );

    return ApiResult<Map<String, String>>(
      success: true,
      message: response.message,
      data: profile,
      raw: response.raw,
      statusCode: response.statusCode,
    );
  }

  Map<String, String> _normalizeProfile(
    Map<String, dynamic> data,
    Map<String, String> fallback,
  ) {
    final responseData = _asMap(data['data']);
    final user = UserModel.fromMaps(data, responseData);
    final responseUser = _firstNonEmptyMap([
      data['user'],
      responseData['user'],
      _findFirstMapByKeys(data, const {'user'}),
    ]);
    final patientId = _firstNonEmptyString([
      responseUser['patientId'],
      data['patientId'],
      responseData['patientId'],
    ]);

    String pick(String key, String candidate) {
      final text = candidate.trim();
      if (text.isNotEmpty) return text;
      return (fallback[key] ?? '').trim();
    }

    return {
      'userId': pick('userId', patientId.isNotEmpty ? patientId : user.id),
      'name': pick('name', user.name),
      'email': pick('email', user.email),
      'role': pick('role', user.role),
      'mobile': pick('mobile', user.mobile),
      'dob': pick('dob', user.dob),
      'gender': pick('gender', user.gender),
      'country': pick('country', user.country),
      'state': pick('state', user.state),
      'city': pick('city', user.city),
      'location': pick('location', user.location),
    };
  }

  bool _hasMeaningfulProfile(Map<String, String> profile) {
    return (profile['name'] ?? '').trim().isNotEmpty ||
        (profile['email'] ?? '').trim().isNotEmpty ||
        (profile['userId'] ?? '').trim().isNotEmpty;
  }

  ApiResult<AuthResponse> _authResult(
    ApiResult<Map<String, dynamic>> result,
    String missingTokenMessage,
  ) {
    final data = result.data ?? <String, dynamic>{};
    final responseData = _asMap(data['data']);
    final nestedData = _asMap(responseData['data']);
    final token = _firstNonEmptyString([
      data['token'],
      data['accessToken'],
      data['access_token'],
      data['authToken'],
      data['auth_token'],
      data['jwt'],
      data['jwtToken'],
      data['bearerToken'],
      responseData['token'],
      responseData['accessToken'],
      responseData['access_token'],
      responseData['authToken'],
      responseData['auth_token'],
      responseData['jwt'],
      responseData['jwtToken'],
      responseData['bearerToken'],
      nestedData['token'],
      nestedData['accessToken'],
      nestedData['access_token'],
      nestedData['authToken'],
      nestedData['auth_token'],
      nestedData['jwt'],
      nestedData['jwtToken'],
      nestedData['bearerToken'],
      _findFirstStringByKeys(data, const {
        'token',
        'accessToken',
        'access_token',
        'authToken',
        'auth_token',
        'jwt',
        'jwtToken',
        'bearerToken',
      }),
    ]);
    final refreshToken = _firstNonEmptyString([
      data['refreshToken'],
      data['refresh_token'],
      responseData['refreshToken'],
      responseData['refresh_token'],
      nestedData['refreshToken'],
      nestedData['refresh_token'],
      _findFirstStringByKeys(data, const {
        'refreshToken',
        'refresh_token',
      }),
    ]);

    if (!result.success) {
      return ApiResult<AuthResponse>(
        success: false,
        message: result.message,
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    if (token.isEmpty) {
      return ApiResult<AuthResponse>(
        success: false,
        message: missingTokenMessage,
        raw: result.raw,
        statusCode: result.statusCode,
      );
    }

    return ApiResult<AuthResponse>(
      success: true,
      message: result.message,
      data: AuthResponse(
        token: token,
        refreshToken: refreshToken,
        user: UserModel.fromMaps(data, responseData),
      ),
      raw: result.raw,
      statusCode: result.statusCode,
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

String _firstNonEmptyString(List<dynamic> values) {
  for (final value in values) {
    final text = value?.toString().trim() ?? '';

    if (text.isNotEmpty) {
      return text;
    }
  }

  return '';
}

String _findFirstStringByKeys(dynamic value, Set<String> keys) {
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

      final nested = _findFirstStringByKeys(entry.value, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  if (value is List) {
    for (final item in value) {
      final nested = _findFirstStringByKeys(item, keys);
      if (nested.isNotEmpty) return nested;
    }
  }

  return '';
}

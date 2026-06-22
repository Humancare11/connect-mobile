import 'package:google_sign_in/google_sign_in.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/api_result.dart';
import '../models/auth_response.dart';
import 'api_client.dart';

class AuthService {
  AuthService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  final ApiClient _apiClient;
  static bool _googleInitialized = false;

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
      'name': name,
      'email': email,
      'mobile': mobile,
      'dob': dob,
      'gender': gender,
      'country': country,
      'password': password,
      'privacyConsent': privacyConsent,
      'hipaaConsent': hipaaConsent,
      'otp': otp,
    });

    return _authResult(result, 'Registration response did not include a token.');
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
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('token', authResponse.token);
    await prefs.setString('userId', authResponse.user.id);
    await prefs.setString('name', authResponse.user.name);
    await prefs.setString('email', authResponse.user.email);
    await prefs.setString('role', authResponse.user.role);
    await prefs.setString('mobile', authResponse.user.mobile);
    await prefs.setString('dob', authResponse.user.dob);
    await prefs.setString('gender', authResponse.user.gender);
    await prefs.setString('country', authResponse.user.country);
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

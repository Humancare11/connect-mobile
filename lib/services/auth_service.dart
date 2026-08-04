import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../models/api_result.dart';
import '../models/auth_response.dart';
import '../models/google_auth_result.dart';
import '../utils/json_helpers.dart';
import 'api_client.dart';
import 'idle_session_timer.dart';
import 'notification_service.dart';
import 'session_expired_service.dart';
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

  static String? get _googleServerClientId {
    final clientId =
        dotenv.env['ANDROID_GOOGLE_CLIENT_ID'] ??
        dotenv.env['GOOGLE_CLIENT_ID'] ??
        dotenv.env['VITE_GOOGLE_CLIENT_ID'];
    final trimmed = clientId?.trim() ?? '';
    return trimmed.isEmpty ? null : trimmed;
  }

  Future<ApiResult<AuthResponse>> login({
    required String email,
    required String password,
  }) async {
    final result = await _apiClient.post('/auth/login', {
      'email': email,
      'password': password.trim(),
    });

    return _authResult(result, 'Login response did not include a valid token.');
  }

  // Every password value is trimmed here — the single place all password
  // flows (register, forgot-password reset, login above) funnel through —
  // rather than in each screen individually. Previously only login_screen.dart
  // and change_password_screen.dart trimmed before sending, while
  // registration and password-reset didn't: a password with a leading/
  // trailing space (easy to introduce via autocapitalize or paste) would be
  // accepted here untrimmed but validated as if trimmed (AuthValidators
  // treats a space as a valid "special character"), then rejected on every
  // future login attempt once trimmed — permanently locking the user out of
  // an account with its own valid password.
  Future<ApiResult<void>> sendRegisterOtp({
    required String email,
    required String password,
    required String dob,
    required bool privacyConsent,
    required bool hipaaConsent,
  }) async {
    final result = await _apiClient.post('/auth/send-register-otp', {
      'email': email,
      'password': password.trim(),
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
      'password': password.trim(),
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
    final responseData = asMap(data['data']);
    final resetToken = firstNonEmptyString([
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
      'newPassword': newPassword.trim(),
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
      'currentPassword': currentPassword.trim(),
      'newPassword': newPassword.trim(),
    });

    return ApiResult<void>(
      success: result.success,
      message: result.message,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<ApiResult<void>> requestAccountDeletion({String reason = ''}) async {
    final result = await _apiClient.post('/auth/account-delete-request', {
      'reason': reason.trim(),
    });

    return ApiResult<void>(
      success: result.success,
      message: result.message,
      raw: result.raw,
      statusCode: result.statusCode,
    );
  }

  Future<GoogleAuthResult> googleLoginWithAccessToken(
    String accessToken,
  ) async {
    try {
      final trimmedToken = accessToken.trim();
      if (trimmedToken.isEmpty) {
        return const GoogleAuthResult(
          success: false,
          message: 'Google Sign-In did not return an access token.',
        );
      }

      final result = await _apiClient.post('/auth/google', {
        'accessToken': trimmedToken,
      });

      if (!result.success) {
        return GoogleAuthResult(
          success: false,
          message: result.message.isNotEmpty
              ? result.message
              : 'Google Sign-In failed.',
        );
      }

      final data = result.data ?? <String, dynamic>{};
      final isNewUser = data['isNewUser'] == true;
      final googleName = data['googleName']?.toString() ?? '';
      final googleEmail = data['googleEmail']?.toString() ?? '';

      if (isNewUser) {
        return GoogleAuthResult(
          success: true,
          message: 'Complete your profile to continue.',
          isNewUser: true,
          googleName: googleName,
          googleEmail: googleEmail,
          accessToken: trimmedToken,
        );
      }

      final authResult = _authResult(
        result,
        'Google Sign-In response was invalid.',
      );
      return GoogleAuthResult(
        success: authResult.success,
        message: authResult.message,
        authResponse: authResult.data,
      );
    } catch (error) {
      return const GoogleAuthResult(
        success: false,
        message: 'Google Sign-In failed.',
      );
    }
  }

  Future<GoogleAuthResult> googleLogin() async {
    if (kIsWeb) {
      return const GoogleAuthResult(
        success: false,
        message: 'Use the Google button on the web version.',
      );
    }

    try {
      final googleSignIn = GoogleSignIn.instance;
      if (!_googleInitialized) {
        final serverClientId = _googleServerClientId;
        if (serverClientId == null) {
          return const GoogleAuthResult(
            success: false,
            message: 'Google Sign-In is missing ANDROID_GOOGLE_CLIENT_ID.',
          );
        }

        await googleSignIn.initialize(serverClientId: serverClientId);
        _googleInitialized = true;
      }

      const scopes = ['openid', 'profile', 'email'];
      final account = await googleSignIn.authenticate(scopeHint: scopes);
      final authorization =
          await account.authorizationClient.authorizationForScopes(scopes) ??
          await account.authorizationClient.authorizeScopes(scopes);
      final accessToken = authorization.accessToken;

      return googleLoginWithAccessToken(accessToken);
    } catch (error, stackTrace) {
      debugPrint('Google Sign-In failed: $error');
      debugPrint('$stackTrace');
      return GoogleAuthResult(
        success: false,
        message: 'Google Sign-In failed: ${_googleErrorMessage(error)}',
      );
    }
  }

  Future<GoogleAuthResult> completeGoogleRegistration({
    required String accessToken,
    required String mobile,
    required String dob,
    required String gender,
    required String country,
    required bool privacyConsent,
    required bool hipaaConsent,
  }) async {
    try {
      final result = await _apiClient.post('/auth/google', {
        'accessToken': accessToken,
        'mobile': mobile,
        'dob': dob,
        'gender': gender,
        'country': country,
        'privacyConsent': privacyConsent,
        'hipaaConsent': hipaaConsent,
      });

      if (!result.success) {
        return GoogleAuthResult(
          success: false,
          message: result.message.isNotEmpty
              ? result.message
              : 'Registration failed.',
        );
      }

      final authResult = _authResult(
        result,
        'Google registration response was invalid.',
      );
      return GoogleAuthResult(
        success: authResult.success,
        message: authResult.message,
        authResponse: authResult.data,
      );
    } catch (error) {
      return const GoogleAuthResult(
        success: false,
        message: 'Registration failed.',
      );
    }
  }

  Future<void> saveSession(AuthResponse authResponse) async {
    // Every login/register/Google-auth path funnels through here to
    // establish a session — the single place to also clear a stale
    // "session expired" flag, rather than relying solely on the gate's own
    // button handler (see SessionExpiredScreen._goToLogin), and to start
    // the 30-minute inactivity countdown.
    SessionExpiredService.instance.reset();
    IdleSessionTimer.instance.start();
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
    // Fire-and-forget: FCM token registration now retries transient
    // failures with backoff (see notification_service.dart), which can add
    // several seconds of delay on its own. Awaiting it here would block the
    // login/register screen from navigating to MainScreen on nothing more
    // than a slow or flaky push-notification registration — whether this
    // device gets push notifications has no bearing on whether login should
    // proceed.
    unawaited(NotificationService.instance.syncTokenAfterLogin());
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
    final responseData = asMap(data['data']);
    final user = UserModel.fromMaps(data, responseData);
    final responseUser = firstNonEmptyMap([
      data['user'],
      responseData['user'],
      findFirstMapByKeys(data, const {'user'}),
    ]);
    final patientId = firstNonEmptyString([
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
    final responseData = asMap(data['data']);
    final nestedData = asMap(responseData['data']);
    final token = firstNonEmptyString([
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
      findFirstStringByKeys(data, const {
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
    final refreshToken = firstNonEmptyString([
      data['refreshToken'],
      data['refresh_token'],
      responseData['refreshToken'],
      responseData['refresh_token'],
      nestedData['refreshToken'],
      nestedData['refresh_token'],
      findFirstStringByKeys(data, const {'refreshToken', 'refresh_token'}),
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

String _googleErrorMessage(Object error) {
  final message = error.toString().trim();
  if (message.isEmpty) return 'Please try again.';

  const prefixes = [
    'GoogleSignInException: ',
    'PlatformException(',
    'Exception: ',
  ];

  var cleaned = message;
  for (final prefix in prefixes) {
    if (cleaned.startsWith(prefix)) {
      cleaned = cleaned.substring(prefix.length).trim();
      break;
    }
  }

  if (cleaned.length > 180) {
    return '${cleaned.substring(0, 177)}...';
  }

  return cleaned;
}

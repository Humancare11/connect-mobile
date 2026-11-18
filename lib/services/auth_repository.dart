import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../config/app_info.dart';
import '../models/api_result.dart';
import '../models/auth_response.dart';
import '../models/register_model.dart';
import 'auth_service.dart';
import 'notification_service.dart';
import 'token_storage_service.dart';

/// Repository pattern implementation for authentication
/// This abstracts the auth service and storage operations
/// Follows clean architecture principles
class AuthRepository {
  AuthRepository({
    AuthService? authService,
    TokenStorageService? tokenStorage,
    http.Client? httpClient,
    Future<void> Function()? deleteFcmToken,
  }) : _authService = authService ?? AuthService(),
       _tokenStorage = tokenStorage ?? const TokenStorageService(),
       // ignore: prefer_initializing_formals -- named params can't be private
       _httpClient = httpClient,
       _deleteFcmToken =
           deleteFcmToken ?? (() => NotificationService.instance.deleteLocalToken());

  final AuthService _authService;
  final TokenStorageService _tokenStorage;
  final http.Client? _httpClient;
  final Future<void> Function() _deleteFcmToken;

  static const Duration _logoutTimeout = Duration(seconds: 8);

  /// Send OTP to email for registration.
  Future<ApiResult<void>> sendRegisterOtp({
    required String email,
    required String password,
    required String name,
    required String mobile,
    required bool privacyConsent,
    required bool hipaaConsent,
  }) async {
    return _authService.sendRegisterOtp(
      email: email,
      password: password,
      name: name,
      mobile: mobile,
      privacyConsent: privacyConsent,
      hipaaConsent: hipaaConsent,
    );
  }

  /// Register a new user with OTP verification
  Future<ApiResult<AuthResponse>> register(RegisterRequest request) async {
    final result = await _authService.register(
      name: request.name,
      email: request.email,
      password: request.password,
      mobile: request.mobile,
      country: request.country,
      state: request.state,
      city: request.city,
      privacyConsent: request.privacyConsent,
      hipaaConsent: request.hipaaConsent,
      otp: request.otp,
    );

    if (result.success && result.data != null) {
      // Delegates to AuthService.saveSession — the two used to duplicate
      // this logic verbatim (this copy was only ever reachable from
      // register(), while every screen that logs in calls
      // AuthService.saveSession directly), risking silent drift if one was
      // ever updated without the other.
      await _authService.saveSession(result.data!);
    }

    return result;
  }

  /// Get current authentication token
  Future<String?> getToken() async {
    return _tokenStorage.getToken();
  }

  /// Get current user profile
  Future<Map<String, String>> getUserProfile() async {
    return _tokenStorage.getUserProfile();
  }

  /// Check if user is authenticated
  Future<bool> isAuthenticated() async {
    return _tokenStorage.isAuthenticated();
  }

  /// Logs out: revokes the session on the server (`POST /auth/logout`, 8s
  /// timeout), deletes this device's FCM token, then clears local storage.
  /// The server call and the FCM deletion are best-effort — local storage is
  /// always cleared, even if either of them fails or times out.
  Future<void> clearSession() async {
    try {
      await _logoutOnServer();
    } catch (error) {
      debugPrint('Logout: server call failed: $error');
    }
    try {
      await _deleteFcmToken();
    } catch (error) {
      debugPrint('Logout: FCM token deletion failed: $error');
    }
    await _tokenStorage.clearAll();
  }

  Future<void> _logoutOnServer() async {
    final refreshToken = (await _tokenStorage.getRefreshToken()) ?? '';
    final accessToken = (await _tokenStorage.getToken()) ?? '';
    // The backend reads the session id from the bearer token, or from the
    // `refreshToken` body field, and ignores token expiry — so an expired
    // access token still revokes the session.
    final bearer = refreshToken.isNotEmpty ? refreshToken : accessToken;
    if (bearer.isEmpty) return;

    final client = _httpClient ?? http.Client();
    try {
      await client
          .post(
            Uri.parse('${ApiConfig.baseUrl}/auth/logout'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              ...AppBuildInfo.headers,
              'Authorization': 'Bearer $bearer',
              'X-Auth-Role': 'user',
            },
            body: jsonEncode({'refreshToken': refreshToken}),
          )
          .timeout(_logoutTimeout);
    } finally {
      if (_httpClient == null) client.close();
    }
  }
}

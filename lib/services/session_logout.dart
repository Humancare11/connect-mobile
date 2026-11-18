import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../config/app_info.dart';
import 'notification_service.dart';
import 'token_storage_service.dart';

/// The one logout flow used by every way a session can end — the manual
/// "Log out" button, the idle timeout and a dead (expired) session:
///
/// 1. `POST /auth/logout` (refresh token in the body, 8s timeout) so the
///    server revokes the session,
/// 2. delete this device's FCM token (the next login registers a fresh one),
/// 3. clear local storage.
///
/// Steps 1 and 2 are best-effort and never throw; step 3 always runs.
///
/// Kept free of `ApiClient` on purpose: `ApiClient` itself calls this when a
/// session dies, and going through it would re-enter the 401/refresh logic.
class SessionLogout {
  SessionLogout({
    TokenStorageService? tokenStorage,
    http.Client? httpClient,
    Future<void> Function()? deleteFcmToken,
  }) : _tokenStorage = tokenStorage ?? const TokenStorageService(),
       // ignore: prefer_initializing_formals -- named params cannot be private
       _httpClient = httpClient,
       _deleteFcmToken =
           deleteFcmToken ??
           (() => NotificationService.instance.deleteLocalToken());

  static SessionLogout _shared = SessionLogout();
  static SessionLogout get shared => _shared;
  @visibleForTesting
  static set shared(SessionLogout value) => _shared = value;

  static const Duration serverTimeout = Duration(seconds: 8);

  final TokenStorageService _tokenStorage;
  final http.Client? _httpClient;
  final Future<void> Function() _deleteFcmToken;

  /// Runs the logout. With [background] true the server call and the FCM
  /// deletion run detached, so the caller (a timer or an HTTP error path) is
  /// not held up by the network; local storage is still cleared before this
  /// returns. Never throws.
  Future<void> perform({bool background = false}) async {
    var refreshToken = '';
    var accessToken = '';
    try {
      refreshToken = (await _tokenStorage.getRefreshToken()) ?? '';
      accessToken = (await _tokenStorage.getToken()) ?? '';
    } catch (error) {
      debugPrint('Logout: could not read tokens: $error');
    }

    final remote = _remoteCleanup(refreshToken, accessToken);
    if (background) {
      unawaited(remote);
    } else {
      await remote;
    }

    try {
      await _tokenStorage.clearAll();
    } catch (error) {
      debugPrint('Logout: clearing local storage failed: $error');
    }
  }

  Future<void> _remoteCleanup(String refreshToken, String accessToken) async {
    try {
      await _logoutOnServer(refreshToken, accessToken);
    } catch (error) {
      debugPrint('Logout: server call failed: $error');
    }
    try {
      await _deleteFcmToken();
    } catch (error) {
      debugPrint('Logout: FCM token deletion failed: $error');
    }
  }

  Future<void> _logoutOnServer(String refreshToken, String accessToken) async {
    // The backend reads the session id from the bearer token or from the
    // `refreshToken` body field, and ignores token expiry — so even an
    // expired access token still revokes the session.
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
          .timeout(serverTimeout);
    } finally {
      if (_httpClient == null) client.close();
    }
  }
}

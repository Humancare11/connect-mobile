import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../config/app_info.dart';
import 'token_storage_service.dart';

/// Global state for the "Please update" experience, mirroring
/// `SessionExpiredService`: pure state, no navigation. `AppUpdateGate` (mounted
/// once in `main.dart`'s `MaterialApp.builder`) turns it into UI.
///
/// Two levels:
///  * [forced]   — this build may no longer be used (sign-up gets
///    `426 APP_UPDATE_REQUIRED`, or startup found the build is below the
///    minimum while nobody is signed in). Blocking screen.
///  * [optional] — a newer build exists. Dismissible card.
class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  bool _forced = false;
  bool _optional = false;
  String _storeUrl = '';

  bool get forced => _forced;
  bool get optional => _optional && !_forced;
  String get storeUrl => _storeUrl;

  void requireUpdate({String storeUrl = ''}) {
    if (_forced && (storeUrl.isEmpty || storeUrl == _storeUrl)) return;
    _forced = true;
    if (storeUrl.isNotEmpty) _storeUrl = storeUrl;
    notifyListeners();
  }

  void suggestUpdate({String storeUrl = ''}) {
    if (_optional || _forced) return;
    _optional = true;
    if (storeUrl.isNotEmpty) _storeUrl = storeUrl;
    notifyListeners();
  }

  void dismissOptional() {
    if (!_optional) return;
    _optional = false;
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _forced = false;
    _optional = false;
    _storeUrl = '';
  }
}

enum UpdateDecision { none, optional, required }

/// What to do about this build, given the server's numbers.
///
/// `minBuild` is "the lowest build allowed to sign up". So a build below it is
/// *blocked* only while nobody is signed in; a signed-in patient (possibly
/// about to join a consultation) just gets the dismissible suggestion.
UpdateDecision decideUpdate({
  required int build,
  required int minBuild,
  required int latestBuild,
  required bool loggedIn,
}) {
  if (build <= 0) return UpdateDecision.none; // unknown build: never nag
  if (minBuild > 0 && build < minBuild) {
    return loggedIn ? UpdateDecision.optional : UpdateDecision.required;
  }
  if (latestBuild > build) return UpdateDecision.optional;
  return UpdateDecision.none;
}

/// Startup check against `GET /api/app/version`. Fails open: offline, a slow
/// server or a malformed answer simply means no prompt — the app is never
/// held up by it.
class AppVersionService {
  AppVersionService({
    http.Client? client,
    TokenStorageService? tokenStorage,
    this.timeout = const Duration(seconds: 4),
  }) : _client = client ?? http.Client(),
       _tokenStorage = tokenStorage ?? const TokenStorageService();

  final http.Client _client;
  final TokenStorageService _tokenStorage;
  final Duration timeout;

  Future<UpdateDecision> check() async {
    final platform = AppBuildInfo.platform;
    if (platform.isEmpty) return UpdateDecision.none;
    try {
      final response = await _client
          .get(
            Uri.parse('${ApiConfig.baseUrl}/app/version'),
            headers: {'Accept': 'application/json', ...AppBuildInfo.headers},
          )
          .timeout(timeout);
      if (response.statusCode != 200) return UpdateDecision.none;

      final decoded = jsonDecode(response.body);
      final mine = decoded is Map ? decoded[platform] : null;
      if (mine is! Map) return UpdateDecision.none;

      final minBuild = _asInt(mine['minBuild']);
      final latestBuild = _asInt(mine['latestBuild']);
      final storeUrl = mine['storeUrl']?.toString().trim() ?? '';

      final token = await _tokenStorage.getToken() ?? '';
      final decision = decideUpdate(
        build: AppBuildInfo.buildNumber,
        minBuild: minBuild,
        latestBuild: latestBuild,
        loggedIn: token.isNotEmpty,
      );

      switch (decision) {
        case UpdateDecision.required:
          AppUpdateService.instance.requireUpdate(storeUrl: storeUrl);
        case UpdateDecision.optional:
          AppUpdateService.instance.suggestUpdate(storeUrl: storeUrl);
        case UpdateDecision.none:
          break;
      }
      return decision;
    } catch (_) {
      return UpdateDecision.none;
    }
  }

  static int _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../config/api_config.dart';
import '../config/app_info.dart';
import 'active_call_tracker.dart';
import 'payment_in_progress_tracker.dart';

/// Global state for the forced update, mirroring `SessionExpiredService`: pure
/// state, no navigation. `AppUpdateGate` (mounted once in `main.dart`'s
/// `MaterialApp.builder`) turns it into UI.
///
/// There is one level only: this build must be updated. It is set by the
/// version check ([AppVersionService]) or by a `426 APP_UPDATE_REQUIRED`
/// answer (see `ApiClient`).
class AppUpdateService extends ChangeNotifier {
  AppUpdateService._();

  static final AppUpdateService instance = AppUpdateService._();

  bool _required = false;
  String _storeUrl = '';

  /// An update is required, whether or not the dialog is on screen yet.
  bool get isRequired => _required;
  String get storeUrl => _storeUrl;

  /// The dialog must be on screen now. A video consultation or an unfinished
  /// payment is never interrupted: the dialog waits until it is over.
  bool get isBlocking =>
      _required &&
      !ActiveCallTracker.instance.isActive &&
      !PaymentInProgressTracker.instance.isActive;

  /// Without a store link there is no way out of the dialog, so the app is
  /// not blocked.
  void requireUpdate({String storeUrl = ''}) {
    final url = storeUrl.trim();
    if (url.isEmpty) return;
    if (_required && url == _storeUrl) return;
    _required = true;
    _storeUrl = url;
    notifyListeners();
  }

  void clear() {
    if (!_required) return;
    _required = false;
    _storeUrl = '';
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _required = false;
    _storeUrl = '';
  }
}

enum UpdateDecision { none, required }

/// What to do about this build, given the server's numbers. A build below the
/// minimum or below the latest one must update, signed in or not.
UpdateDecision decideUpdate({
  required int build,
  required int minBuild,
  required int latestBuild,
}) {
  if (build <= 0) return UpdateDecision.none; // unknown build: never block
  return build < minBuild || build < latestBuild
      ? UpdateDecision.required
      : UpdateDecision.none;
}

/// Check against `GET /api/app/version`, on cold start and on return from the
/// background.
///
/// Fails open: offline, a slow server or a malformed answer neither adds nor
/// removes a block. Only a valid answer does.
class AppVersionService {
  AppVersionService({
    http.Client? client,
    this.timeout = const Duration(seconds: 4),
    this.minInterval = const Duration(minutes: 5),
    DateTime Function()? now,
  }) : _client = client ?? http.Client(),
       _now = now ?? DateTime.now;

  /// The one instance the app uses, so the throttle covers both triggers.
  static final AppVersionService shared = AppVersionService();

  final http.Client _client;
  final Duration timeout;

  /// The shortest gap between two checks made by [checkIfDue].
  final Duration minInterval;
  final DateTime Function() _now;

  DateTime? _lastCheck;

  /// [check], unless one was made less than [minInterval] ago.
  Future<UpdateDecision> checkIfDue() async {
    final last = _lastCheck;
    if (last != null && _now().difference(last) < minInterval) {
      return UpdateDecision.none;
    }
    return check();
  }

  Future<UpdateDecision> check() async {
    final platform = AppBuildInfo.platform;
    final build = AppBuildInfo.buildNumber;
    if (platform.isEmpty || build <= 0) return UpdateDecision.none;
    _lastCheck = _now();
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
      if (minBuild == null || latestBuild == null) return UpdateDecision.none;
      final storeUrl = mine['storeUrl']?.toString().trim() ?? '';

      final decision = decideUpdate(
        build: build,
        minBuild: minBuild,
        latestBuild: latestBuild,
      );

      if (decision == UpdateDecision.required && storeUrl.isNotEmpty) {
        AppUpdateService.instance.requireUpdate(storeUrl: storeUrl);
        return UpdateDecision.required;
      }
      AppUpdateService.instance.clear();
      return UpdateDecision.none;
    } catch (_) {
      return UpdateDecision.none;
    }
  }

  static int? _asInt(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value');
}

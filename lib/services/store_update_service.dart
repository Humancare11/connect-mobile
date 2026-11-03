import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/api_config.dart';
import '../config/app_info.dart';
import 'active_call_tracker.dart';

/// Kill switch for the store-driven force update.
///
/// * [enabled] is the compile-time switch: set it to `false` and ship a
///   build to turn forcing off for good.
/// * Without a release, the backend can send `forceStoreUpdate: false`
///   (top-level or inside the platform's object) in `GET /api/app/version`;
///   see [fetchRemoteForceFlag]. A missing flag means "force".
class StoreUpdateConfig {
  const StoreUpdateConfig._();

  static const bool enabled = true;
}

/// What the store told us. `null` from a check always means "couldn't tell":
/// the app then carries on as if nothing were wrong.
class StoreUpdateInfo {
  const StoreUpdateInfo({required this.updateAvailable, this.storeUrl = ''});

  final bool updateAvailable;
  final String storeUrl;
}

/// True only when [store] is strictly newer than [current] ("1.0.1" vs
/// "1.0.0"). Compares dotted numbers; anything that doesn't parse is "not
/// newer" so a strange store string can never force an update.
bool isNewerVersion(String store, String current) {
  List<int>? parse(String v) {
    final core = v.trim().split(RegExp(r'[+\-\s]')).first;
    if (core.isEmpty) return null;
    final parts = <int>[];
    for (final part in core.split('.')) {
      final n = int.tryParse(part);
      if (n == null) return null;
      parts.add(n);
    }
    return parts;
  }

  final a = parse(store);
  final b = parse(current);
  if (a == null || b == null) return false;
  final len = a.length > b.length ? a.length : b.length;
  for (var i = 0; i < len; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}

/// App Store lookup by bundle id. Returns `null` when the app isn't on the
/// store yet (resultCount 0), offline, or anything is malformed — so the iOS
/// side stays silent until the app is live and then switches on by itself.
Future<StoreUpdateInfo?> lookupAppStore({
  required http.Client client,
  required String bundleId,
  required String currentVersion,
  Duration timeout = const Duration(seconds: 5),
}) async {
  try {
    if (bundleId.isEmpty) return null;
    final response = await client
        .get(
          Uri.https('itunes.apple.com', '/lookup', {'bundleId': bundleId}),
          headers: {'Accept': 'application/json'},
        )
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    final results = decoded is Map ? decoded['results'] : null;
    if (results is! List || results.isEmpty || results.first is! Map) {
      return null;
    }
    final app = results.first as Map;
    final version = app['version']?.toString() ?? '';
    if (version.isEmpty) return null;
    var url = app['trackViewUrl']?.toString() ?? '';
    if (url.isEmpty && app['trackId'] != null) {
      url = 'https://apps.apple.com/app/id${app['trackId']}';
    }
    return StoreUpdateInfo(
      updateAvailable: isNewerVersion(version, currentVersion),
      storeUrl: url,
    );
  } catch (_) {
    return null;
  }
}

/// Reads the optional remote kill switch. `false` = forcing is off; `true` or
/// anything unreadable = leave forcing on.
Future<bool?> fetchRemoteForceFlag({
  required http.Client client,
  required String platform,
  Duration timeout = const Duration(seconds: 4),
}) async {
  try {
    final response = await client
        .get(
          Uri.parse('${ApiConfig.baseUrl}/app/version'),
          headers: {'Accept': 'application/json', ...AppBuildInfo.headers},
        )
        .timeout(timeout);
    if (response.statusCode != 200) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) return null;
    final mine = decoded[platform];
    final perPlatform = mine is Map ? mine['forceStoreUpdate'] : null;
    final flag = perPlatform is bool
        ? perPlatform
        : decoded['forceStoreUpdate'];
    return flag is bool ? flag : null;
  } catch (_) {
    return null;
  }
}

/// Force-update state, mirroring `AppUpdateService`: pure state, no
/// navigation. `AppUpdateGate` turns it into UI.
///
/// * [prompt]  — "A new version is available" popup (Update / Cancel).
/// * [blocked] — iOS only: Cancel was pressed, so a full-screen "Update
///   required" screen takes over (Apple rejects apps that exit themselves).
///
/// The popup comes back on every launch and every return from background
/// until the user is actually on the new version. Every failure path leaves
/// both flags off: a failed check never blocks anyone.
class StoreUpdateService extends ChangeNotifier {
  StoreUpdateService({
    this._platform,
    this._checkStore,
    this._runInAppUpdate,
    Future<bool> Function(String url)? openUrl,
    Future<void> Function()? closeApp,
    this._remoteFlag,
    bool Function()? isCallActive,
    this._enabled = StoreUpdateConfig.enabled,
    this.enabledInDebug = false,
    this.minInterval = const Duration(seconds: 30),
    DateTime Function()? now,
  }) : _openUrl = openUrl ?? _launch,
       _closeApp = closeApp ?? SystemNavigator.pop,
       _isCallActive =
           isCallActive ?? (() => ActiveCallTracker.instance.isActive),
       _now = now ?? DateTime.now;

  static final StoreUpdateService instance = StoreUpdateService();

  final String? _platform;
  final Future<StoreUpdateInfo?> Function()? _checkStore;
  final Future<bool> Function()? _runInAppUpdate;
  final Future<bool> Function(String url) _openUrl;
  final Future<void> Function() _closeApp;
  final Future<bool?> Function()? _remoteFlag;
  final bool Function() _isCallActive;
  final bool _enabled;
  final bool enabledInDebug;
  final Duration minInterval;
  final DateTime Function() _now;

  bool _prompt = false;
  bool _blocked = false;
  String _storeUrl = '';
  bool _checking = false;
  DateTime? _lastCheck;

  bool get prompt => _prompt && !_blocked;
  bool get blocked => _blocked;
  String get storeUrl => _storeUrl;

  String get _platformName => _platform ?? AppBuildInfo.platform;
  bool get _isAndroid => _platformName == 'android';

  /// Asks the store whether a newer version exists. Safe to call from
  /// anywhere, as often as you like.
  Future<void> check() async {
    if (_checking || _prompt || _blocked) return;
    if (!_enabled || (kDebugMode && !enabledInDebug)) return;
    final platform = _platformName;
    if (platform != 'android' && platform != 'ios') return;
    // Never interrupt a consultation: Cancel closes the app on Android.
    if (_isCallActive()) return;
    final last = _lastCheck;
    if (last != null && _now().difference(last) < minInterval) return;

    _checking = true;
    _lastCheck = _now();
    try {
      final flag = await (_remoteFlag ?? _defaultRemoteFlag)();
      if (flag == false) return;
      final info = await (_checkStore ?? _defaultCheckStore)();
      if (info == null || !info.updateAvailable) return;
      // A call may have started while we were waiting on the network.
      if (_isCallActive()) return;
      _storeUrl = info.storeUrl;
      _prompt = true;
      notifyListeners();
    } catch (_) {
      // Fail open.
    } finally {
      _checking = false;
    }
  }

  /// "Update" on the popup or the iOS blocking screen. The popup / screen
  /// stays up afterwards: if the user comes back without updating, they see
  /// it again.
  Future<void> update() async {
    if (_isAndroid) {
      final ran = await (_runInAppUpdate ?? _defaultInAppUpdate)();
      if (ran) return;
    }
    await _openUrl(_storeUrl);
  }

  /// "Cancel" on the popup. Android closes the app; iOS swaps the popup for
  /// the blocking screen.
  Future<void> cancel() async {
    if (_isAndroid) {
      await _closeApp();
      return;
    }
    _blocked = true;
    _prompt = false;
    notifyListeners();
  }

  Future<bool?> _defaultRemoteFlag() =>
      fetchRemoteForceFlag(client: http.Client(), platform: _platformName);

  Future<StoreUpdateInfo?> _defaultCheckStore() async {
    final info = await PackageInfo.fromPlatform();
    if (_isAndroid) {
      final play = await InAppUpdate.checkForUpdate();
      return StoreUpdateInfo(
        updateAvailable:
            play.updateAvailability == UpdateAvailability.updateAvailable,
        storeUrl:
            'https://play.google.com/store/apps/details?id=${info.packageName}',
      );
    }
    return lookupAppStore(
      client: http.Client(),
      bundleId: info.packageName,
      currentVersion: info.version,
    );
  }

  /// True when the Play immediate-update flow ran (the user may still have
  /// backed out of it — the popup is then simply still there).
  Future<bool> _defaultInAppUpdate() async {
    try {
      final play = await InAppUpdate.checkForUpdate();
      if (play.updateAvailability != UpdateAvailability.updateAvailable ||
          !play.immediateUpdateAllowed) {
        return false;
      }
      final result = await InAppUpdate.performImmediateUpdate();
      return result != AppUpdateResult.inAppUpdateFailed;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _launch(String url) async {
    if (url.isEmpty) return false;
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
  }
}

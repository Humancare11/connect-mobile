import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// What this build is: the platform and the `version+build` string the
/// backend expects in `X-Client-Platform` / `X-App-Version` (admin shows it
/// as "App · Android · v1.0.0+16", and the sign-up version gate compares the
/// build number after the `+`).
///
/// Call [init] once in `main()` before any request is made. If it never runs
/// (or fails), [headers] is simply empty and the app behaves as an
/// undeclared client — requests still work, they just aren't labelled.
class AppBuildInfo {
  const AppBuildInfo._();

  static String _platform = '';
  static String _version = '';
  static int _buildNumber = 0;

  /// "android" or "ios"; empty on web and desktop (the backend then falls
  /// back to the User-Agent, which is correct for a browser).
  static String get platform => _platform;

  /// "1.0.0+16", or empty before [init].
  static String get version => _version;

  /// The build number alone (the `+16` part); 0 when unknown.
  static int get buildNumber => _buildNumber;

  static Future<void> init() async {
    _platform = platformFor(defaultTargetPlatform, isWeb: kIsWeb);
    try {
      final info = await PackageInfo.fromPlatform();
      _buildNumber = int.tryParse(info.buildNumber) ?? 0;
      _version = info.buildNumber.isEmpty
          ? info.version
          : '${info.version}+${info.buildNumber}';
    } catch (_) {
      // Leave version blank rather than send a wrong one.
    }
  }

  /// Extra headers every API call carries.
  static Map<String, String> get headers => {
    if (_platform.isNotEmpty) 'X-Client-Platform': _platform,
    if (_platform.isNotEmpty && _version.isNotEmpty) 'X-App-Version': _version,
  };

  static String platformFor(TargetPlatform target, {required bool isWeb}) {
    if (isWeb) return '';
    switch (target) {
      case TargetPlatform.android:
        return 'android';
      case TargetPlatform.iOS:
        return 'ios';
      default:
        return '';
    }
  }

  /// Build number out of "1.0.0+16" (or a bare "16"); null if there is none.
  static int? parseBuild(String? version) {
    final value = (version ?? '').trim();
    final match =
        RegExp(r'\+(\d{1,9})$').firstMatch(value) ??
        RegExp(r'^(\d{1,9})$').firstMatch(value);
    return match == null ? null : int.parse(match.group(1)!);
  }

  @visibleForTesting
  static void setForTest({String platform = '', String version = ''}) {
    _platform = platform;
    _version = version;
    _buildNumber = parseBuild(version) ?? 0;
  }
}

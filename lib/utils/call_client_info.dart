import 'dart:io' show Platform;

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';

import '../config/app_info.dart';

/// What this app declares about itself when it joins a video call, for the
/// admin-only call report: platform, app version, OS version and device model.
///
/// Informational only - the server validates it and reconciles it with what it
/// observes (it is never used for access control), so a wrong or missing value
/// can never affect the call. No device name (owner-chosen), no identifiers.
/// Returns an empty map when nothing useful is known (e.g. desktop tests).
Future<Map<String, dynamic>> buildCallClientInfo({DeviceInfoPlugin? plugin}) async {
  final platform = AppBuildInfo.platform;
  if (platform.isEmpty) return const {};

  final info = <String, dynamic>{
    'platform': platform,
    if (AppBuildInfo.version.isNotEmpty) 'appVersion': AppBuildInfo.version,
  };

  try {
    final device = plugin ?? DeviceInfoPlugin();
    if (!kIsWeb && Platform.isAndroid) {
      final android = await device.androidInfo;
      info['osName'] = 'Android';
      info['osVersion'] = android.version.release;
      final model = formatDeviceModel(android.manufacturer, android.model);
      if (model.isNotEmpty) info['deviceModel'] = model;
    } else if (!kIsWeb && Platform.isIOS) {
      final ios = await device.iosInfo;
      info['osName'] = 'iOS';
      info['osVersion'] = ios.systemVersion;
      // `model` is the generic family ("iPhone"/"iPad"); `name` is the owner's
      // own label for the phone and is deliberately not sent.
      if (ios.model.isNotEmpty) info['deviceModel'] = ios.model;
    }
  } catch (_) {
    // Platform channel unavailable: keep the platform + app version we have.
  }
  return info;
}

/// "Google" + "Pixel 8" -> "Google Pixel 8"; avoids "samsung samsung SM-S918B".
@visibleForTesting
String formatDeviceModel(String? manufacturer, String? model) {
  final make = (manufacturer ?? '').trim();
  final name = (model ?? '').trim();
  if (name.isEmpty) return make;
  if (make.isEmpty || name.toLowerCase().startsWith(make.toLowerCase())) return name;
  final prettyMake = make[0].toUpperCase() + make.substring(1);
  return '$prettyMake $name';
}

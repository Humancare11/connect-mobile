// Starts/stops an Android foreground service that keeps this process (and
// the active call's socket + RTCPeerConnection) alive while the app is
// backgrounded during a video consultation — screen lock, switching apps, or
// a brief background window during a Wi-Fi/cellular handoff. Without it,
// Android (especially aggressive OEM battery managers) can suspend
// background networking mid-call. See CallForegroundService.kt.
//
// No-op on iOS/web/desktop: iOS instead relies on the "audio" UIBackgroundMode
// declared in Info.plist for the same purpose.

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallForegroundService {
  CallForegroundService._();

  static const MethodChannel _channel =
      MethodChannel('com.humancareconnect.app/call_foreground_service');

  /// [hasAudio]/[hasVideo] should reflect which local media tracks the call
  /// actually acquired — the native side only ever requests a foreground
  /// service type backed by a track that's present (and therefore already
  /// permission-granted), never a type the app doesn't hold permission for.
  static Future<void> start({required bool hasAudio, required bool hasVideo}) async {
    if (kIsWeb || !Platform.isAndroid) return;
    if (!hasAudio && !hasVideo) return;
    try {
      await _channel.invokeMethod('start', {
        'hasAudio': hasAudio,
        'hasVideo': hasVideo,
      });
    } catch (err) {
      debugPrint('[call-foreground-service] start failed: $err');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (err) {
      debugPrint('[call-foreground-service] stop failed: $err');
    }
  }
}

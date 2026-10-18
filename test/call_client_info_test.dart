import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/config/app_info.dart';
import 'package:humancare_connect/utils/call_client_info.dart';

void main() {
  group('formatDeviceModel', () {
    test('joins manufacturer and model once', () {
      expect(formatDeviceModel('Google', 'Pixel 8'), 'Google Pixel 8');
      expect(formatDeviceModel('samsung', 'SM-S918B'), 'Samsung SM-S918B');
    });

    test('does not repeat the manufacturer already in the model', () {
      expect(formatDeviceModel('Xiaomi', 'Xiaomi 13T'), 'Xiaomi 13T');
    });

    test('copes with missing parts', () {
      expect(formatDeviceModel(null, 'Pixel 8'), 'Pixel 8');
      expect(formatDeviceModel('Google', ''), 'Google');
      expect(formatDeviceModel(null, null), '');
    });
  });

  group('buildCallClientInfo', () {
    tearDown(() => AppBuildInfo.setForTest());

    test('is empty when the platform is unknown (desktop / tests)', () async {
      AppBuildInfo.setForTest();
      expect(await buildCallClientInfo(), isEmpty);
    });

    test('declares platform and app version even if the device plugin is unavailable', () async {
      AppBuildInfo.setForTest(platform: 'android', version: '1.0.18+17');
      final info = await buildCallClientInfo();
      expect(info['platform'], 'android');
      expect(info['appVersion'], '1.0.18+17');
      // never anything identifying
      expect(info.keys, everyElement(isIn(['platform', 'appVersion', 'osName', 'osVersion', 'deviceModel'])));
    });
  });
}

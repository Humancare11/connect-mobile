import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/services/device_time_zone.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('flutter_timezone');

  void mockPlatform(Future<Object?> Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  }

  test('returns the IANA name the platform reports', () async {
    mockPlatform((call) async {
      expect(call.method, 'getLocalTimezone');
      return 'Asia/Kolkata';
    });

    expect(await deviceTimeZone(), 'Asia/Kolkata');
  });

  test('the name is trimmed', () async {
    mockPlatform((_) async => '  Europe/London ');

    expect(await deviceTimeZone(), 'Europe/London');
  });

  test('a platform error gives an empty string, never an exception', () async {
    mockPlatform((_) async => throw PlatformException(code: 'boom'));

    expect(await deviceTimeZone(), '');
  });

  test('no platform plugin at all gives an empty string', () async {
    // Nothing is registered for the channel, as in a plain unit test.
    expect(await deviceTimeZone(), '');
  });

  test('a lookup that never answers gives up after about two seconds', () async {
    mockPlatform((_) => Future<Object?>.delayed(const Duration(seconds: 30)));

    final watch = Stopwatch()..start();
    final result = await deviceTimeZone();
    watch.stop();

    expect(result, '');
    expect(watch.elapsed, lessThan(const Duration(seconds: 5)));
  });
}

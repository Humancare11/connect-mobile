import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/config/app_info.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/app_update_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';

class _Tokens extends TokenStorageService {
  const _Tokens(this.token);
  final String? token;

  @override
  Future<String?> getToken() async => token;
}

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
  });

  setUp(() {
    AppUpdateService.instance.resetForTest();
    AppBuildInfo.setForTest();
  });

  group('AppBuildInfo', () {
    test('parseBuild reads the number after "+"', () {
      expect(AppBuildInfo.parseBuild('1.0.0+16'), 16);
      expect(AppBuildInfo.parseBuild(' 2.1.0+120 '), 120);
      expect(AppBuildInfo.parseBuild('16'), 16);
      expect(AppBuildInfo.parseBuild('1.0.0'), isNull);
      expect(AppBuildInfo.parseBuild(null), isNull);
    });

    test('platform is android / ios only, and empty on web', () {
      expect(
        AppBuildInfo.platformFor(TargetPlatform.android, isWeb: false),
        'android',
      );
      expect(AppBuildInfo.platformFor(TargetPlatform.iOS, isWeb: false), 'ios');
      expect(
        AppBuildInfo.platformFor(TargetPlatform.windows, isWeb: false),
        '',
      );
      expect(AppBuildInfo.platformFor(TargetPlatform.android, isWeb: true), '');
    });

    test('headers carry platform and version', () {
      AppBuildInfo.setForTest(platform: 'android', version: '1.0.0+16');
      expect(AppBuildInfo.headers, {
        'X-Client-Platform': 'android',
        'X-App-Version': '1.0.0+16',
        // This build can pay in rupees (Razorpay).
        'X-Client-Capabilities': 'razorpay',
      });
      expect(AppBuildInfo.buildNumber, 16);
    });

    test('before init there are no headers (undeclared client)', () {
      expect(AppBuildInfo.headers, isEmpty);
    });

    test('the Razorpay capability is only declared with a platform', () {
      AppBuildInfo.setForTest(platform: '', version: '1.0.0+21');
      expect(AppBuildInfo.headers.containsKey('X-Client-Capabilities'), isFalse);
      AppBuildInfo.setForTest(platform: 'ios', version: '1.0.0+21');
      expect(AppBuildInfo.headers['X-Client-Capabilities'], 'razorpay');
    });
  });

  group('ApiClient sends the headers', () {
    test('on POST and GET', () async {
      AppBuildInfo.setForTest(platform: 'ios', version: '1.0.0+16');
      final seen = <http.BaseRequest>[];
      final client = ApiClient(
        client: MockClient((request) async {
          seen.add(request);
          return http.Response(jsonEncode({'ok': true}), 200);
        }),
        tokenStorage: const _Tokens(null),
      );

      await client.post('/auth/login', {'email': 'a@b.c'}, silent: true);
      await client.get('/locations/countries', null, true);

      expect(seen, hasLength(2));
      for (final request in seen) {
        expect(request.headers['X-Client-Platform'], 'ios');
        expect(request.headers['X-App-Version'], '1.0.0+16');
      }
    });

    test(
      'a 426 APP_UPDATE_REQUIRED requires the update',
      () async {
        final client = ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'msg': 'Please update the app to continue.',
                'code': 'APP_UPDATE_REQUIRED',
                'storeUrl': 'https://play.google.com/store/apps/details?id=x',
              }),
              426,
            ),
          ),
          tokenStorage: const _Tokens(null),
        );
        final result = await client.post('/auth/register', {}, silent: true);
        expect(result.success, isFalse);
        expect(result.statusCode, 426);
        expect(AppUpdateService.instance.isRequired, isTrue);
        expect(AppUpdateService.instance.storeUrl, contains('play.google.com'));
      },
    );

    test('a 426 without a store link does not block', () async {
      final client = ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'APP_UPDATE_REQUIRED', 'storeUrl': ''}),
            426,
          ),
        ),
        tokenStorage: const _Tokens(null),
      );
      await client.post('/auth/register', {}, silent: true);
      expect(AppUpdateService.instance.isRequired, isFalse);
    });

    test('an ordinary 400 does not', () async {
      final client = ApiClient(
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'msg': 'Country is required.'}), 400),
        ),
        tokenStorage: const _Tokens(null),
      );
      await client.post('/auth/register', {}, silent: true);
      expect(AppUpdateService.instance.isRequired, isFalse);
    });
  });

  group('decideUpdate', () {
    UpdateDecision d({int build = 16, int min = 0, int latest = 0}) =>
        decideUpdate(build: build, minBuild: min, latestBuild: latest);

    test('nothing configured → nothing', () {
      expect(d(), UpdateDecision.none);
    });

    test('below the minimum → required', () {
      expect(d(build: 15, min: 16), UpdateDecision.required);
    });

    test('below the latest build → required', () {
      expect(d(build: 16, min: 10, latest: 18), UpdateDecision.required);
    });

    test('equal to or newer than both → fine', () {
      expect(d(build: 18, min: 16, latest: 18), UpdateDecision.none);
      expect(d(build: 19, min: 16, latest: 18), UpdateDecision.none);
    });

    test('an unknown build is never blocked', () {
      expect(d(build: 0, min: 99, latest: 99), UpdateDecision.none);
    });
  });

  group('AppVersionService', () {
    AppVersionService service(http.Client client) =>
        AppVersionService(client: client);

    http.Client answering(Object body, {int status = 200}) =>
        MockClient((_) async => http.Response(jsonEncode(body), status));

    Map<String, Object> entry({
      Object min = 16,
      Object latest = 18,
      String url = 'https://store/android',
    }) => {'minBuild': min, 'latestBuild': latest, 'storeUrl': url};

    final config = {
      'android': entry(),
      'ios': entry(min: 0, latest: 0, url: ''),
    };

    bool isRequired() => AppUpdateService.instance.isRequired;

    void android(int build) =>
        AppBuildInfo.setForTest(platform: 'android', version: '1.0.0+$build');

    test('below the minimum → required, with the store link', () async {
      android(15);
      expect(await service(answering(config)).check(), UpdateDecision.required);
      expect(isRequired(), isTrue);
      expect(AppUpdateService.instance.storeUrl, 'https://store/android');
    });

    // The check takes no session at all, so signed in or out is the same.
    test('below the latest build only → required', () async {
      android(17);
      expect(await service(answering(config)).check(), UpdateDecision.required);
      expect(isRequired(), isTrue);
    });

    test('current build → nothing', () async {
      android(18);
      expect(await service(answering(config)).check(), UpdateDecision.none);
      expect(isRequired(), isFalse);
    });

    test('uses its own platform entry, on iOS too', () async {
      AppBuildInfo.setForTest(platform: 'ios', version: '1.0.0+1');
      expect(await service(answering(config)).check(), UpdateDecision.none);
      expect(
        await service(
          answering({'ios': entry(url: 'https://apps.apple.com/app/id1')}),
        ).check(),
        UpdateDecision.required,
      );
      expect(AppUpdateService.instance.storeUrl, contains('apps.apple.com'));
    });

    test('an empty store link never blocks, on Android or iOS', () async {
      for (final platform in ['android', 'ios']) {
        AppBuildInfo.setForTest(platform: platform, version: '1.0.0+1');
        expect(
          await service(answering({platform: entry(url: ' ')})).check(),
          UpdateDecision.none,
        );
        expect(isRequired(), isFalse);
      }
    });

    final failures = <String, http.Client Function()>{
      'server error': () => answering({}, status: 500),
      'bad JSON': () =>
          MockClient((_) async => http.Response('not json', 200)),
      'offline': () =>
          MockClient((_) async => throw http.ClientException('offline')),
      'no platform entry': () => answering({}),
      'missing numbers': () => answering({
        'android': {'storeUrl': 'https://store/android'},
      }),
      'unreadable numbers': () =>
          answering({'android': entry(min: 'x', latest: 'y')}),
    };

    for (final failure in failures.entries) {
      test('${failure.key}: neither adds nor removes a block', () async {
        android(1);
        expect(await service(failure.value()).check(), UpdateDecision.none);
        expect(isRequired(), isFalse);

        await service(answering(config)).check();
        await service(failure.value()).check();
        expect(isRequired(), isTrue);
      });
    }

    test('a timeout does not block', () async {
      android(1);
      final slow = AppVersionService(
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      );
      expect(await slow.check(), UpdateDecision.none);
      expect(isRequired(), isFalse);
    });

    test('a valid "no update" answer removes the block', () async {
      android(15);
      await service(answering(config)).check();
      await service(
        answering({'android': entry(min: 0, latest: 0)}),
      ).check();
      expect(isRequired(), isFalse);
    });

    test('no platform (web, desktop) → no request', () async {
      AppBuildInfo.setForTest(version: '1.0.0+1');
      var calls = 0;
      final client = MockClient((_) async {
        calls++;
        return http.Response(jsonEncode(config), 200);
      });
      expect(await service(client).check(), UpdateDecision.none);
      expect(calls, 0);
    });

    test('checkIfDue is throttled; the cold-start check counts', () async {
      android(18);
      var calls = 0;
      var now = DateTime(2030);
      final throttled = AppVersionService(
        now: () => now,
        client: MockClient((_) async {
          calls++;
          return http.Response(jsonEncode(config), 200);
        }),
      );

      await throttled.check();
      await throttled.checkIfDue();
      expect(calls, 1);

      now = now.add(const Duration(minutes: 5));
      await throttled.checkIfDue();
      expect(calls, 2);
    });
  });
}

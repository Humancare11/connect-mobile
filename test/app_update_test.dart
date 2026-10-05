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
      });
      expect(AppBuildInfo.buildNumber, 16);
    });

    test('before init there are no headers (undeclared client)', () {
      expect(AppBuildInfo.headers, isEmpty);
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
      'a 426 APP_UPDATE_REQUIRED turns on the blocking update screen',
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
        expect(AppUpdateService.instance.forced, isTrue);
        expect(AppUpdateService.instance.storeUrl, contains('play.google.com'));
      },
    );

    test('an ordinary 400 does not', () async {
      final client = ApiClient(
        client: MockClient(
          (_) async =>
              http.Response(jsonEncode({'msg': 'Country is required.'}), 400),
        ),
        tokenStorage: const _Tokens(null),
      );
      await client.post('/auth/register', {}, silent: true);
      expect(AppUpdateService.instance.forced, isFalse);
    });
  });

  group('decideUpdate', () {
    UpdateDecision d({
      int build = 16,
      int min = 0,
      int latest = 0,
      bool loggedIn = false,
    }) => decideUpdate(
      build: build,
      minBuild: min,
      latestBuild: latest,
      loggedIn: loggedIn,
    );

    test('nothing configured → no prompt', () {
      expect(d(), UpdateDecision.none);
    });

    test('below the minimum, signed out → blocked', () {
      expect(d(build: 15, min: 16), UpdateDecision.required);
    });

    test(
      'below the minimum but signed in → only a suggestion (never locked out mid-care)',
      () {
        expect(d(build: 15, min: 16, loggedIn: true), UpdateDecision.optional);
      },
    );

    test('at or above the minimum → fine', () {
      expect(d(build: 16, min: 16), UpdateDecision.none);
    });

    test('a newer build exists → optional', () {
      expect(d(build: 16, min: 10, latest: 18), UpdateDecision.optional);
    });

    test('an unknown build never nags', () {
      expect(d(build: 0, min: 99, latest: 99), UpdateDecision.none);
    });
  });

  group('AppVersionService', () {
    AppVersionService service(http.Client client, {String? token}) =>
        AppVersionService(client: client, tokenStorage: _Tokens(token));

    http.Client answering(Map<String, dynamic> body, {int status = 200}) =>
        MockClient((_) async => http.Response(jsonEncode(body), status));

    const config = {
      'android': {
        'minBuild': 16,
        'latestBuild': 18,
        'storeUrl': 'https://store/android',
      },
      'ios': {'minBuild': 0, 'latestBuild': 0, 'storeUrl': ''},
    };

    test('old build, signed out → forced update with the store link', () async {
      AppBuildInfo.setForTest(platform: 'android', version: '1.0.0+15');
      final decision = await service(answering(config)).check();
      expect(decision, UpdateDecision.required);
      expect(AppUpdateService.instance.forced, isTrue);
      expect(AppUpdateService.instance.storeUrl, 'https://store/android');
    });

    test('old build, signed in → dismissible suggestion only', () async {
      AppBuildInfo.setForTest(platform: 'android', version: '1.0.0+15');
      final decision = await service(answering(config), token: 'abc').check();
      expect(decision, UpdateDecision.optional);
      expect(AppUpdateService.instance.forced, isFalse);
      expect(AppUpdateService.instance.optional, isTrue);
    });

    test('current build with nothing newer → no prompt', () async {
      AppBuildInfo.setForTest(platform: 'android', version: '1.0.0+18');
      expect(await service(answering(config)).check(), UpdateDecision.none);
      expect(AppUpdateService.instance.forced, isFalse);
      expect(AppUpdateService.instance.optional, isFalse);
    });

    test('uses its own platform entry (iOS min 0 → nothing)', () async {
      AppBuildInfo.setForTest(platform: 'ios', version: '1.0.0+1');
      expect(await service(answering(config)).check(), UpdateDecision.none);
    });

    test('fails open: server error, bad JSON, timeout, no platform', () async {
      AppBuildInfo.setForTest(platform: 'android', version: '1.0.0+1');
      expect(
        await service(answering({}, status: 500)).check(),
        UpdateDecision.none,
      );
      expect(
        await service(
          MockClient((_) async => http.Response('not json', 200)),
        ).check(),
        UpdateDecision.none,
      );
      expect(
        await service(
          MockClient((_) async => throw http.ClientException('offline')),
        ).check(),
        UpdateDecision.none,
      );
      AppBuildInfo.setForTest(version: '1.0.0+1'); // web/desktop: no platform
      expect(await service(answering(config)).check(), UpdateDecision.none);
      expect(AppUpdateService.instance.forced, isFalse);
    });
  });
}

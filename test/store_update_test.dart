import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/config/app_info.dart';
import 'package:humancare_connect/services/app_update_service.dart';
import 'package:humancare_connect/services/store_update_service.dart';
import 'package:humancare_connect/widgets/app_update_gate.dart';

/// A [StoreUpdateService] wired to fakes, with counters for what it did.
class _Rig {
  _Rig({
    this.platform = 'android',
    this.info,
    this.storeThrows = false,
    this.remote = true,
    this.remoteThrows = false,
    this.callActive = false,
    this.inAppRuns = true,
    bool enabled = true,
    bool enabledInDebug = true,
    Duration minInterval = Duration.zero,
  }) {
    service = StoreUpdateService(
      platform: platform,
      enabled: enabled,
      enabledInDebug: enabledInDebug,
      minInterval: minInterval,
      checkStore: () async {
        storeChecks++;
        if (storeThrows) throw Exception('store unreachable');
        return info;
      },
      runInAppUpdate: () async {
        inAppRuns_++;
        return inAppRuns;
      },
      openUrl: (url) async {
        opened.add(url);
        return true;
      },
      closeApp: () async => closed++,
      remoteFlag: () async {
        if (remoteThrows) throw Exception('version endpoint unreachable');
        return remote;
      },
      isCallActive: () => callActive,
    );
  }

  final String platform;
  final StoreUpdateInfo? info;
  final bool storeThrows;
  final bool? remote;
  final bool remoteThrows;
  bool callActive;
  final bool inAppRuns;

  late final StoreUpdateService service;
  int storeChecks = 0;
  int inAppRuns_ = 0;
  int closed = 0;
  final opened = <String>[];
}

const _newer = StoreUpdateInfo(
  updateAvailable: true,
  storeUrl: 'https://store.test/app',
);
const _same = StoreUpdateInfo(updateAvailable: false);

void main() {
  setUpAll(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
  });

  setUp(() {
    AppUpdateService.instance.resetForTest();
    AppBuildInfo.setForTest();
  });

  group('isNewerVersion', () {
    test('newer / same / older', () {
      expect(isNewerVersion('1.0.1', '1.0.0'), isTrue);
      expect(isNewerVersion('1.1', '1.0.9'), isTrue);
      expect(isNewerVersion('2.0.0', '1.9.9'), isTrue);
      expect(isNewerVersion('1.0.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.0', '1.0.1'), isFalse);
      expect(isNewerVersion('0.9.9', '1.0.0'), isFalse);
    });

    test('numeric, not alphabetical: 1.10.0 is newer than 1.9.0', () {
      expect(isNewerVersion('1.10.0', '1.9.0'), isTrue);
    });

    test('ignores a +build / -suffix and never forces on garbage', () {
      expect(isNewerVersion('1.0.1+5', '1.0.0+9'), isTrue);
      expect(isNewerVersion('1.0.0+9', '1.0.0+1'), isFalse);
      expect(isNewerVersion('', '1.0.0'), isFalse);
      expect(isNewerVersion('abc', '1.0.0'), isFalse);
      expect(isNewerVersion('1.0.1', ''), isFalse);
    });
  });

  group('lookupAppStore (iOS)', () {
    Future<StoreUpdateInfo?> lookup(http.Client client) => lookupAppStore(
      client: client,
      bundleId: 'com.humancareconnect.app',
      currentVersion: '1.0.0',
    );

    http.Response found(String version) => http.Response(
      jsonEncode({
        'resultCount': 1,
        'results': [
          {
            'version': version,
            'trackViewUrl': 'https://apps.apple.com/app/id123',
          },
        ],
      }),
      200,
    );

    test('newer version on the store', () async {
      final info = await lookup(MockClient((_) async => found('1.0.1')));
      expect(info!.updateAvailable, isTrue);
      expect(info.storeUrl, 'https://apps.apple.com/app/id123');
    });

    test('same version: no update', () async {
      final info = await lookup(MockClient((_) async => found('1.0.0')));
      expect(info!.updateAvailable, isFalse);
    });

    test('older store version: no update', () async {
      final info = await lookup(MockClient((_) async => found('0.9.0')));
      expect(info!.updateAvailable, isFalse);
    });

    test('app not on the App Store yet: null (stays silent)', () async {
      final info = await lookup(
        MockClient(
          (_) async =>
              http.Response(jsonEncode({'resultCount': 0, 'results': []}), 200),
        ),
      );
      expect(info, isNull);
    });

    test('server error, bad body, network failure: null', () async {
      expect(
        await lookup(MockClient((_) async => http.Response('boom', 500))),
        isNull,
      );
      expect(
        await lookup(MockClient((_) async => http.Response('<html>', 200))),
        isNull,
      );
      expect(
        await lookup(MockClient((_) async => throw Exception('offline'))),
        isNull,
      );
    });

    test('falls back to the trackId URL', () async {
      final info = await lookup(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'results': [
                {'version': '2.0.0', 'trackId': 42},
              ],
            }),
            200,
          ),
        ),
      );
      expect(info!.storeUrl, 'https://apps.apple.com/app/id42');
    });
  });

  group('fetchRemoteForceFlag (kill switch)', () {
    Future<bool?> flag(Object body, {int status = 200}) => fetchRemoteForceFlag(
      client: MockClient((_) async => http.Response(jsonEncode(body), status)),
      platform: 'android',
    );

    test('top-level true / false are read as they are', () async {
      expect(await flag({'forceStoreUpdate': true}), isTrue);
      expect(await flag({'forceStoreUpdate': false}), isFalse);
    });

    test(
      'per-platform true / false are read, and win over the top level',
      () async {
        expect(
          await flag({
            'android': {'forceStoreUpdate': true},
          }),
          isTrue,
        );
        expect(
          await flag({
            'android': {'forceStoreUpdate': false},
            'forceStoreUpdate': true,
          }),
          isFalse,
        );
        // the other platform's value is not ours
        expect(
          await flag({
            'ios': {'forceStoreUpdate': true},
          }),
          isNull,
        );
      },
    );

    test('missing field, wrong type or bad status: null', () async {
      expect(
        await flag({
          'android': {'minBuild': 1},
        }),
        isNull,
      );
      expect(await flag({'forceStoreUpdate': 'true'}), isNull);
      expect(await flag({}, status: 500), isNull);
      expect(await flag(['not', 'a', 'map']), isNull);
    });

    test('network error: null', () async {
      expect(
        await fetchRemoteForceFlag(
          client: MockClient((_) async => throw Exception('offline')),
          platform: 'android',
        ),
        isNull,
      );
    });

    test('timeout: null', () async {
      expect(
        await fetchRemoteForceFlag(
          client: MockClient((_) async {
            await Future<void>.delayed(const Duration(milliseconds: 300));
            return http.Response(jsonEncode({'forceStoreUpdate': true}), 200);
          }),
          platform: 'android',
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
    });
  });

  group('StoreUpdateService.check', () {
    test('newer version -> popup with the store url', () async {
      final rig = _Rig(info: _newer);
      await rig.service.check();
      expect(rig.service.prompt, isTrue);
      expect(rig.service.blocked, isFalse);
      expect(rig.service.storeUrl, 'https://store.test/app');
    });

    test('same / older version -> nothing', () async {
      final rig = _Rig(info: _same);
      await rig.service.check();
      expect(rig.service.prompt, isFalse);
      expect(rig.service.blocked, isFalse);
    });

    test('failed check (null or throws) -> nothing, never blocks', () async {
      for (final rig in [_Rig(info: null), _Rig(storeThrows: true)]) {
        await rig.service.check();
        expect(rig.service.prompt, isFalse);
        expect(rig.service.blocked, isFalse);
      }
    });

    test('kill switch (compile-time) -> store is not even asked', () async {
      final rig = _Rig(info: _newer, enabled: false);
      await rig.service.check();
      expect(rig.storeChecks, 0);
      expect(rig.service.prompt, isFalse);
    });

    test('kill switch (remote false) -> no popup', () async {
      final rig = _Rig(info: _newer, remote: false);
      await rig.service.check();
      expect(rig.storeChecks, 0);
      expect(rig.service.prompt, isFalse);
    });

    test('only an explicit remote true forces', () async {
      final rig = _Rig(info: _newer, remote: true);
      await rig.service.check();
      expect(rig.service.prompt, isTrue);
    });

    test('remote missing / unreadable (null) -> does NOT force', () async {
      final rig = _Rig(info: _newer, remote: null);
      await rig.service.check();
      expect(rig.storeChecks, 0);
      expect(rig.service.prompt, isFalse);
      expect(rig.service.blocked, isFalse);
    });

    test(
      'remote check throws (error / timeout surfaced) -> does NOT force',
      () async {
        final rig = _Rig(info: _newer, remoteThrows: true);
        await rig.service.check();
        expect(rig.storeChecks, 0);
        expect(rig.service.prompt, isFalse);
      },
    );

    test('debug builds skip the check by default', () async {
      final rig = _Rig(info: _newer, enabledInDebug: false);
      await rig.service.check();
      expect(rig.storeChecks, 0);
      expect(rig.service.prompt, isFalse);
    });

    test('unknown platform (web / desktop) does nothing', () async {
      final rig = _Rig(platform: '', info: _newer);
      await rig.service.check();
      expect(rig.storeChecks, 0);
    });

    test('never interrupts an active call', () async {
      final rig = _Rig(info: _newer, callActive: true);
      await rig.service.check();
      expect(rig.storeChecks, 0);
      expect(rig.service.prompt, isFalse);

      rig.callActive = false;
      await rig.service.check();
      expect(rig.service.prompt, isTrue);
    });

    test('checks are throttled between quick resumes', () async {
      final rig = _Rig(info: _same, minInterval: const Duration(minutes: 5));
      await rig.service.check();
      await rig.service.check();
      expect(rig.storeChecks, 1);
    });
  });

  group('StoreUpdateService actions', () {
    test('Android Update: Play in-app flow, no store page', () async {
      final rig = _Rig(info: _newer);
      await rig.service.check();
      await rig.service.update();
      expect(rig.inAppRuns_, 1);
      expect(rig.opened, isEmpty);
      // Still showing: it comes back until the user really updates.
      expect(rig.service.prompt, isTrue);
    });

    test('Android Update falls back to the Play Store page', () async {
      final rig = _Rig(info: _newer, inAppRuns: false);
      await rig.service.check();
      await rig.service.update();
      expect(rig.opened, ['https://store.test/app']);
      expect(rig.service.prompt, isTrue);
    });

    test('Android Cancel closes the app', () async {
      final rig = _Rig(info: _newer);
      await rig.service.check();
      await rig.service.cancel();
      expect(rig.closed, 1);
      expect(rig.service.blocked, isFalse);
    });

    test('iOS Update opens the App Store page', () async {
      final rig = _Rig(platform: 'ios', info: _newer);
      await rig.service.check();
      await rig.service.update();
      expect(rig.inAppRuns_, 0);
      expect(rig.opened, ['https://store.test/app']);
    });

    test(
      'iOS Cancel does NOT exit; it blocks with the update screen',
      () async {
        final rig = _Rig(platform: 'ios', info: _newer);
        await rig.service.check();
        await rig.service.cancel();
        expect(rig.closed, 0);
        expect(rig.service.prompt, isFalse);
        expect(rig.service.blocked, isTrue);
      },
    );

    test('iOS not live on the store: nothing happens', () async {
      final rig = _Rig(platform: 'ios', info: null);
      await rig.service.check();
      expect(rig.service.prompt, isFalse);
      expect(rig.service.blocked, isFalse);
    });
  });

  group('AppUpdateGate UI', () {
    Future<void> pump(WidgetTester tester, _Rig rig) async {
      await tester.pumpWidget(
        MaterialApp(
          home: AppUpdateGate(
            storeUpdate: rig.service,
            child: const Scaffold(body: Text('app body')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Android: popup shows, Cancel closes the app', (tester) async {
      final rig = _Rig(info: _newer);
      await pump(tester, rig);

      expect(
        find.text('A new version is available. Please update to continue.'),
        findsOneWidget,
      );
      expect(find.text('Update'), findsOneWidget);
      expect(find.text('Cancel'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(rig.closed, 1);
    });

    testWidgets('Android: Update runs the in-app flow', (tester) async {
      final rig = _Rig(info: _newer);
      await pump(tester, rig);
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();
      expect(rig.inAppRuns_, 1);
      // Popup is still there afterwards.
      expect(find.text('Cancel'), findsOneWidget);
    });

    testWidgets('iOS: Cancel swaps to the blocking screen, Update only', (
      tester,
    ) async {
      final rig = _Rig(platform: 'ios', info: _newer);
      await pump(tester, rig);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(rig.closed, 0);
      expect(find.text('Update required'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
      expect(find.text('Update now'), findsOneWidget);

      await tester.tap(find.text('Update now'));
      await tester.pumpAndSettle();
      expect(rig.opened, ['https://store.test/app']);
      expect(find.text('Update required'), findsOneWidget);
    });

    testWidgets('no newer version: app body only', (tester) async {
      final rig = _Rig(info: _same);
      await pump(tester, rig);
      expect(find.text('app body'), findsOneWidget);
      expect(find.text('Cancel'), findsNothing);
    });

    testWidgets('re-checks when the app returns from background', (
      tester,
    ) async {
      final rig = _Rig(info: _same);
      await pump(tester, rig);
      expect(rig.storeChecks, 1);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(rig.storeChecks, 2);
    });
  });
}

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/config/app_info.dart';
import 'package:humancare_connect/screens/book_appointment_payment_screen.dart';
import 'package:humancare_connect/screens/video_call_screen.dart';
import 'package:humancare_connect/services/active_call_tracker.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/app_update_service.dart';
import 'package:humancare_connect/services/currency_service.dart';
import 'package:humancare_connect/services/notification_service.dart';
import 'package:humancare_connect/services/payment_in_progress_tracker.dart';
import 'package:humancare_connect/services/payment_service.dart';
import 'package:humancare_connect/services/pricing_service.dart';
import 'package:humancare_connect/services/razorpay_checkout.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:humancare_connect/widgets/app_update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _store = 'https://store.example/app';
const _title = 'New version available';

/// Records what the Navigator is asked to push, and keeps the route.
class _Pushes extends NavigatorObserver {
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      routes.add(route);
}

final _navigatorKey = NotificationService.navigatorKey;

Future<void> _pumpApp(
  WidgetTester tester, {
  Widget? home,
  AppVersionService? versionService,
  Future<bool> Function(String url)? openStore,
  List<NavigatorObserver> observers = const [],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigatorKey,
      navigatorObservers: observers,
      builder: (context, child) => AppUpdateGate(
        versionService: versionService,
        openStore: openStore ?? (_) async => true,
        child: child!,
      ),
      onGenerateRoute: (settings) {
        if (settings.name != '/appointment-confirmation') return null;
        return MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('BOOKING CONFIRMED')),
        );
      },
      home: home ?? const Scaffold(body: Text('HOME')),
    ),
  );
}

Future<void> _settle(WidgetTester tester, [int frames = 25]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _require(WidgetTester tester) async {
  AppUpdateService.instance.requireUpdate(storeUrl: _store);
  await _settle(tester, 3);
}

Future<void> _push(WidgetTester tester, String text) async {
  unawaited(
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(text))),
    ),
  );
  await _settle(tester);
}

Future<void> _backGesture(WidgetTester tester) async {
  Future<void> send(String method, [Object? arguments]) =>
      tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'flutter/backgesture',
        const StandardMethodCodec().encodeMethodCall(
          MethodCall(method, arguments),
        ),
        (_) {},
      );

  await send('startBackGesture', {
    'touchOffset': <double>[5, 300],
    'progress': 0.0,
    'swipeEdge': 0,
  });
  await tester.pump();
  await send('commitBackGesture');
  await _settle(tester);
}

// ── Payment screen fixtures (as in razorpay_payment_test.dart) ──────────────

const _payment = RazorpayPayment(
  orderId: 'order_1',
  paymentId: 'pay_1',
  signature: 'sig_1',
);

/// Checkout stays open (the customer is in a UPI or bank app) until
/// [outcome] completes.
class _HeldLauncher implements RazorpayLauncher {
  final outcome = Completer<RazorpayOutcome>();
  bool opened = false;

  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) {
    opened = true;
    return outcome.future;
  }
}

void _fakePaymentBackend({required int bookingStatus}) {
  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    if (path.endsWith('/razorpay/create-order')) {
      return http.Response(
        jsonEncode({
          'orderId': 'order_1',
          'amountCents': 499900,
          'currency': 'INR',
          'keyId': 'rzp_live_x',
        }),
        200,
      );
    }
    if (path.endsWith('/appointments')) {
      return http.Response(jsonEncode({'msg': 'Booking'}), bookingStatus);
    }
    return http.Response('{}', 404);
  }

  ApiClient client(Future<http.Response> Function(http.Request) handler) =>
      ApiClient(
        client: MockClient(handler),
        tokenStorage: const TokenStorageService(),
      );

  PaymentService.instance = PaymentService(apiClient: client(handle));
  PricingService.instance = PricingService(
    apiClient: client(
      (_) async => http.Response(
        jsonEncode({
          'general': {'price': 59, 'label': 'General', 'priceInr': 4999},
        }),
        200,
      ),
    ),
  );
  CurrencyService.instance = CurrencyService(
    fetchCurrency: () async => {
      'currency': 'INR',
      'country': '',
      'source': 'ip',
    },
    wait: (_) async {},
    observeLifecycle: false,
  );
  PendingRazorpayBookingStore.instance = PendingRazorpayBookingStore();
}

Future<_HeldLauncher> _startPayment(
  WidgetTester tester, {
  required int bookingStatus,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  _fakePaymentBackend(bookingStatus: bookingStatus);
  final launcher = _HeldLauncher();
  RazorpayCheckout.launcher = launcher;

  await _pumpApp(tester);
  unawaited(
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(
          arguments: <String, dynamic>{
            'specName': 'General Physician',
            'catLabel': 'General',
            'catId': 'mongo-general',
            'pricingSlug': 'general',
            'condName': 'Fever',
            'cost': 59,
            'date': '2099-12-01 00:00:00.000',
            'time': '10:00 AM',
            'problem': 'Fever',
            'medicalReports': <Map<String, dynamic>>[],
          },
        ),
        builder: (_) => const AppointmentPaymentPage(),
      ),
    ),
  );
  await _settle(tester);
  await tester.tap(find.text('Pay ₹4,999 with Razorpay'));
  await _settle(tester);
  expect(launcher.opened, isTrue);
  return launcher;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final blocker = UpdateBackBlocker();

  setUp(() {
    // The order main() uses: the blocker is added before the app is built.
    WidgetsBinding.instance.addObserver(blocker);
    dotenv.testLoad(
      fileInput:
          'API_BASE_URL=https://example.test/api\n'
          'VITE_STRIPE_PUBLISHABLE_KEY=pk_live_x',
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access',
      'user_id': 'user-1',
    });
    AppBuildInfo.setForTest(platform: 'android', version: '1.0.0+10');
    AppUpdateService.instance.resetForTest();
    ActiveCallTracker.instance.activeCount.value = 0;
    PaymentInProgressTracker.instance.activeCount.value = 0;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const timeZone = MethodChannel('flutter_timezone');
    messenger.setMockMethodCallHandler(timeZone, (_) async => 'Asia/Kolkata');
    addTearDown(() => messenger.setMockMethodCallHandler(timeZone, null));
  });

  tearDown(() => WidgetsBinding.instance.removeObserver(blocker));

  group('the dialog', () {
    testWidgets('nothing is shown while no update is required', (tester) async {
      await _pumpApp(tester);
      await _settle(tester, 3);

      expect(find.text(_title), findsNothing);
      expect(find.byType(UpdateRequiredDialog), findsNothing);
    });

    testWidgets('has the title, the text and exactly one button', (
      tester,
    ) async {
      await _pumpApp(tester);
      await _require(tester);

      expect(find.text(_title), findsOneWidget);
      expect(
        find.text('Please update Humancare Connect to continue using the app.'),
        findsOneWidget,
      );
      final dialog = find.byType(UpdateRequiredDialog);
      expect(
        find.descendant(of: dialog, matching: find.byType(ElevatedButton)),
        findsOneWidget,
      );
      expect(find.text('Update Now'), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('is shown when already required before the app is built', (
      tester,
    ) async {
      AppUpdateService.instance.requireUpdate(storeUrl: _store);
      await _pumpApp(tester);
      await _settle(tester, 3);

      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('tapping outside does nothing and nothing underneath reacts', (
      tester,
    ) async {
      var taps = 0;
      await _pumpApp(
        tester,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: TextButton(
              onPressed: () => taps++,
              child: const Text('UNDER'),
            ),
          ),
        ),
      );
      await _require(tester);

      await tester.tapAt(const Offset(5, 590));
      await tester.tap(find.text('UNDER'), warnIfMissed: false);
      await _settle(tester, 3);

      expect(taps, 0);
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('takes the focus away and hides the app from screen readers', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      final focus = FocusNode();
      addTearDown(focus.dispose);
      await _pumpApp(
        tester,
        home: Scaffold(body: TextField(focusNode: focus, autofocus: true)),
      );
      await _settle(tester, 3);
      expect(focus.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);

      await _require(tester);

      expect(focus.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      focus.requestFocus();
      await tester.pump();
      expect(focus.hasFocus, isFalse);
      expect(find.semantics.byLabel(_title), findsOne);
      expect(find.semantics.byPredicate((node) => node.flagsCollection.isTextField), findsNothing);
      semantics.dispose();
    });

    testWidgets('Update Now opens the store link and the dialog stays', (
      tester,
    ) async {
      final opened = <String>[];
      await _pumpApp(
        tester,
        openStore: (url) async {
          opened.add(url);
          return true;
        },
      );
      await _require(tester);

      await tester.tap(find.text('Update Now'));
      await _settle(tester, 3);

      expect(opened, [_store]);
      expect(find.text(_title), findsOneWidget);
      expect(find.textContaining("Couldn't open the store"), findsNothing);
    });

    testWidgets('says so when the store cannot be opened', (tester) async {
      await _pumpApp(tester, openStore: (_) async => false);
      await _require(tester);

      await tester.tap(find.text('Update Now'));
      await _settle(tester, 3);

      expect(find.textContaining("Couldn't open the store"), findsOneWidget);
    });

    testWidgets('fits a small screen with large text', (tester) async {
      tester.view.physicalSize = const Size(320, 480);
      tester.view.devicePixelRatio = 1;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.view.reset);
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

      await _pumpApp(tester);
      await _require(tester);

      expect(tester.takeException(), isNull);
      expect(find.text('Update Now'), findsOneWidget);
    });

    testWidgets('a 426 answer shows the same dialog', (tester) async {
      await _pumpApp(tester);
      final client = ApiClient(
        client: MockClient(
          (_) async => http.Response(
            jsonEncode({'code': 'APP_UPDATE_REQUIRED', 'storeUrl': _store}),
            426,
          ),
        ),
        tokenStorage: const TokenStorageService(),
      );

      await tester.runAsync(
        () => client.post('/auth/register', {}, silent: true),
      );
      await _settle(tester, 3);

      expect(find.text(_title), findsOneWidget);
    });
  });

  group('back', () {
    testWidgets('the back button does nothing', (tester) async {
      await _pumpApp(tester);
      await _push(tester, 'SECOND');
      await _require(tester);

      final handled = await tester.binding.handlePopRoute();
      await _settle(tester);

      expect(handled, isTrue);
      expect(find.text('SECOND'), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('the back gesture pops normally without a block (control)', (
      tester,
    ) async {
      await _pumpApp(tester);
      await _push(tester, 'SECOND');

      await _backGesture(tester);

      expect(find.text('SECOND'), findsNothing);
    });

    testWidgets('the predictive back gesture does not pop underneath', (
      tester,
    ) async {
      await _pumpApp(tester);
      await _push(tester, 'SECOND');
      await _require(tester);

      await _backGesture(tester);

      expect(find.text('SECOND'), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('a screen replaced underneath is locked too', (tester) async {
      await _pumpApp(tester);
      await _push(tester, 'SECOND');
      await _require(tester);

      await _push(tester, 'THIRD');
      await _backGesture(tester);

      expect(find.text('THIRD'), findsOneWidget);
    });

    testWidgets('on the first screen Android is told the app handles back', (
      tester,
    ) async {
      final handles = <bool>[];
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'SystemNavigator.setFrameworkHandlesBack') {
          handles.add(call.arguments as bool);
        }
        return null;
      });
      addTearDown(
        () => messenger.setMockMethodCallHandler(SystemChannels.platform, null),
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _pumpApp(tester);
      await _settle(tester, 3);

      await _require(tester);
      expect(handles.last, isTrue);

      AppUpdateService.instance.clear();
      await _settle(tester, 3);
      expect(handles.last, isFalse);
    });

    testWidgets('back works again once the block is removed', (tester) async {
      await _pumpApp(tester);
      await _push(tester, 'SECOND');
      await _require(tester);
      AppUpdateService.instance.clear();
      await _settle(tester, 3);

      await _backGesture(tester);

      expect(find.text('SECOND'), findsNothing);
    });
  });

  group('video consultation', () {
    testWidgets('hidden during a call, shown right after it ends', (
      tester,
    ) async {
      ActiveCallTracker.instance.markActive();
      await _pumpApp(tester);
      await _push(tester, 'CALL');
      await _require(tester);

      expect(find.text(_title), findsNothing);
      expect(AppUpdateService.instance.isBlocking, isFalse);

      ActiveCallTracker.instance.markInactive();
      await _settle(tester, 3);

      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('a call opened while the dialog is up hides it, with no '
        'setState-during-build error', (tester) async {
      await _pumpApp(tester);
      await _require(tester);

      unawaited(
        _navigatorKey.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const _FakeCall()),
        ),
      );
      await _settle(tester);
      expect(find.text(_title), findsNothing);
      expect(find.text('IN CALL'), findsOneWidget);

      _navigatorKey.currentState!.pop();
      await _settle(tester);

      expect(find.text(_title), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('notification taps', () {
    Future<void> tap(WidgetTester tester, Map<String, dynamic> data) async {
      await tester.runAsync(
        () => NotificationService.instance.openTapForTest(data),
      );
    }

    testWidgets('everything but a video call is ignored while blocked', (
      tester,
    ) async {
      final pushes = _Pushes();
      await _pumpApp(tester, observers: [pushes]);
      await _require(tester);
      pushes.routes.clear();

      await tap(tester, {'type': 'appointment', 'appointmentId': 'a1'});
      await tap(tester, {'type': 'prescription'});
      await tap(tester, {'route': 'book'});
      await tap(tester, {'type': 'something-else'});
      // A video notification with no appointment would open the list instead.
      await tap(tester, {'type': 'video-call'});

      expect(pushes.routes, isEmpty);
    });

    testWidgets('a video call tap still opens the call', (tester) async {
      final pushes = _Pushes();
      await _pumpApp(tester, observers: [pushes]);
      await _require(tester);
      pushes.routes.clear();

      await tap(tester, {'type': 'video-call', 'appointmentId': 'a1'});

      final route = pushes.routes.single as MaterialPageRoute<dynamic>;
      final screen = route.builder(tester.element(find.text('HOME')));
      expect((screen as VideoCallScreen).appointmentId, 'a1');
      // Removed before it is built: the real call needs a server and camera.
      _navigatorKey.currentState!.removeRoute(route);
    });

    testWidgets('taps work as usual when no update is required', (tester) async {
      final pushes = _Pushes();
      await _pumpApp(tester, observers: [pushes]);
      pushes.routes.clear();

      await tap(tester, {'type': 'prescription'});

      expect(pushes.routes, hasLength(1));
      _navigatorKey.currentState!.removeRoute(pushes.routes.single);
    });
  });

  group('payment', () {
    testWidgets('waits while Checkout is open, also across a resume, and '
        'appears once the booking is saved', (tester) async {
      final launcher = await _startPayment(tester, bookingStatus: 201);
      await _require(tester);
      expect(find.text(_title), findsNothing);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester, 3);
      expect(find.text(_title), findsNothing);

      launcher.outcome.complete(const RazorpaySuccess(_payment));
      await _settle(tester, 40);

      expect(find.text('BOOKING CONFIRMED'), findsOneWidget);
      expect(find.text(_title), findsOneWidget);
      expect(PaymentInProgressTracker.instance.isActive, isFalse);
    });

    testWidgets('appears right after a cancelled payment', (tester) async {
      final launcher = await _startPayment(tester, bookingStatus: 201);
      await _require(tester);

      launcher.outcome.complete(const RazorpayCancelled());
      await _settle(tester);

      expect(find.text(_title), findsOneWidget);
    });

    testWidgets('keeps waiting while a paid booking is unsaved, until the '
        'screen is left', (tester) async {
      final launcher = await _startPayment(tester, bookingStatus: 500);
      await _require(tester);

      launcher.outcome.complete(const RazorpaySuccess(_payment));
      await _settle(tester, 40);

      expect(find.text('Complete Booking'), findsOneWidget);
      expect(find.text(_title), findsNothing);

      _navigatorKey.currentState!.pop();
      await _settle(tester);

      expect(find.text(_title), findsOneWidget);
      expect(PaymentInProgressTracker.instance.isActive, isFalse);
    });

    testWidgets('a payment still running after the screen is left keeps the '
        'dialog back until it ends', (tester) async {
      final launcher = await _startPayment(tester, bookingStatus: 201);
      await _require(tester);

      _navigatorKey.currentState!.pop();
      await _settle(tester);
      expect(find.text(_title), findsNothing);

      launcher.outcome.complete(const RazorpayCancelled());
      await _settle(tester);

      expect(find.text(_title), findsOneWidget);
    });
  });

  group('resume', () {
    late int latestBuild;
    late int calls;
    late bool offline;
    late DateTime now;
    late AppVersionService service;

    setUp(() {
      latestBuild = 11;
      calls = 0;
      offline = false;
      now = DateTime(2030);
      service = AppVersionService(
        now: () => now,
        client: MockClient((_) async {
          calls++;
          if (offline) throw http.ClientException('offline');
          return http.Response(
            jsonEncode({
              'android': {
                'minBuild': 0,
                'latestBuild': latestBuild,
                'storeUrl': _store,
              },
            }),
            200,
          );
        }),
      );
    });

    Future<void> resume(WidgetTester tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _settle(tester, 3);
    }

    testWidgets('checks again, at most once every few minutes', (tester) async {
      await _pumpApp(tester, versionService: service);

      await resume(tester);
      expect(calls, 1);
      expect(find.text(_title), findsOneWidget);

      now = now.add(const Duration(minutes: 4));
      await resume(tester);
      expect(calls, 1);

      now = now.add(const Duration(minutes: 2));
      await resume(tester);
      expect(calls, 2);
    });

    testWidgets('only a valid answer removes the block', (tester) async {
      await _pumpApp(tester, versionService: service);
      await resume(tester);

      offline = true;
      now = now.add(const Duration(minutes: 6));
      await resume(tester);
      expect(find.text(_title), findsOneWidget);

      offline = false;
      latestBuild = 10;
      now = now.add(const Duration(minutes: 6));
      await resume(tester);
      expect(find.text(_title), findsNothing);
    });
  });
}

/// Marks a call active exactly where VideoCallScreen does.
class _FakeCall extends StatefulWidget {
  const _FakeCall();

  @override
  State<_FakeCall> createState() => _FakeCallState();
}

class _FakeCallState extends State<_FakeCall> {
  @override
  void initState() {
    super.initState();
    ActiveCallTracker.instance.markActive();
  }

  @override
  void dispose() {
    ActiveCallTracker.instance.markInactive();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('IN CALL'));
}

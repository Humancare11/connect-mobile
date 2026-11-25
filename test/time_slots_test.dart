import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/screens/book_appointment_form_screen.dart';
import 'package:humancare_connect/screens/book_appointment_payment_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/currency_service.dart';
import 'package:humancare_connect/services/payment_service.dart';
import 'package:humancare_connect/services/pricing_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:humancare_connect/utils/time_slots.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _today = DateTime.now();

DateTime _at(int hour, int minute) =>
    DateTime(_today.year, _today.month, _today.day, hour, minute);

const _selection = {
  'specName': 'General Physician',
  'specIcon': '🩺',
  'catLabel': 'General & Everyday Care',
  'catId': 'mongo-general',
  'pricingSlug': 'general',
  'condName': 'Fever',
  'condIcon': '',
  'cost': 59,
};

ApiClient _client(Future<http.Response> Function(http.Request) handler) =>
    ApiClient(
      client: MockClient(handler),
      tokenStorage: const TokenStorageService(),
    );

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(
  WidgetTester tester,
  Widget page,
  Map<String, dynamic> arguments, {
  double width = 400,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 3200);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigatorKey,
      home: const Scaffold(body: Text('PREVIOUS SCREEN')),
    ),
  );
  unawaited(
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(arguments: arguments),
        builder: (_) => page,
      ),
    ),
  );
  await _settle(tester);
}

/// Opens the form and picks today in the date picker.
Future<void> _openForm(
  WidgetTester tester,
  DateTime Function() clock, {
  double width = 400,
}) async {
  await _open(
    tester,
    AppointmentFormPage(clock: clock),
    _selection,
    width: width,
  );
  await tester.tap(find.text('Select date'));
  await _settle(tester);
  await tester.tap(find.text('OK'));
  await _settle(tester);
}

Finder _slot(String label) => find.byKey(ValueKey('slot $label'));

bool _tappable(WidgetTester tester, String label) =>
    tester.widget<InkWell>(_slot(label)).onTap != null;

bool _selected(WidgetTester tester, String label) {
  final text = tester.widget<Text>(
    find.descendant(of: _slot(label), matching: find.text(label)),
  );
  return text.style!.color == Colors.white;
}

Future<void> _proceed(WidgetTester tester) async {
  await tester.tap(find.textContaining('Proceed to Payment'));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('isSlotPassed', () {
    final day = DateTime(2026, 5, 10);

    test('the list is the web\'s 48 half hours', () {
      expect(kTimeSlots, hasLength(48));
      expect(kTimeSlots.first, '12:00 AM');
      expect(kTimeSlots[1], '12:30 AM');
      expect(kTimeSlots[24], '12:00 PM');
      expect(kTimeSlots.last, '11:30 PM');
    });

    test('now or earlier is passed, later is not (no buffer)', () {
      final now = DateTime(2026, 5, 10, 10, 0);
      expect(isSlotPassed(day, '9:30 AM', now), isTrue);
      expect(isSlotPassed(day, '10:00 AM', now), isTrue);
      expect(isSlotPassed(day, '10:30 AM', now), isFalse);
      expect(
        isSlotPassed(day, '10:00 AM', DateTime(2026, 5, 10, 9, 59, 59)),
        isFalse,
      );
    });

    test('12 AM is midnight and 12 PM is noon', () {
      final noon = DateTime(2026, 5, 10, 12, 0);
      expect(isSlotPassed(day, '12:00 AM', noon), isTrue);
      expect(isSlotPassed(day, '12:00 PM', noon), isTrue);
      expect(isSlotPassed(day, '12:30 PM', noon), isFalse);
    });

    test('goes by the local calendar day', () {
      // Just after local midnight, when the UTC date may still be yesterday.
      final now = DateTime(2026, 5, 10, 0, 10);
      expect(isSlotPassed(day, '12:00 AM', now), isTrue);
      expect(isSlotPassed(day, '12:30 AM', now), isFalse);
      expect(isSlotPassed(DateTime(2026, 5, 11), '12:00 AM', now), isFalse);
      expect(isSlotPassed(DateTime(2026, 5, 9), '11:30 PM', now), isTrue);
    });
  });

  group('screens', () {
    late List<String> requests;

    setUp(() {
      requests = [];
      dotenv.testLoad(
        fileInput:
            'API_BASE_URL=https://example.test/api\nVITE_STRIPE_PUBLISHABLE_KEY=pk_live_x',
      );
      SharedPreferences.setMockInitialValues({});
      FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
      PricingService.instance = PricingService(
        apiClient: _client(
          (_) async => http.Response(
            jsonEncode({
              'general': {
                'price': 59,
                'label': 'General',
                'currency': 'USD',
                'priceInr': 4999,
              },
            }),
            200,
          ),
        ),
      );
      CurrencyService.instance = CurrencyService(
        fetchCurrency: () async => {'currency': 'INR', 'source': 'ip'},
        wait: (_) async {},
        observeLifecycle: false,
      );
      PaymentService.instance = PaymentService(
        apiClient: _client((request) async {
          requests.add(request.url.path);
          return http.Response('{}', 500);
        }),
      );
      const channel = MethodChannel('flutter_timezone');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => 'Asia/Kolkata');
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    });

    testWidgets('before a date is chosen: the web hint, no grid', (
      tester,
    ) async {
      await _open(tester, const AppointmentFormPage(), _selection);

      expect(
        find.text('⚠ Select a date above to see available slots'),
        findsOneWidget,
      );
      expect(_slot('10:00 AM'), findsNothing);
    });

    testWidgets('today: passed slots are tagged, counted and not tappable', (
      tester,
    ) async {
      await _openForm(tester, () => _at(10, 0));

      // 12:00 AM to 10:00 AM are gone: 21 slots.
      expect(find.text('27 of 48 slots available'), findsOneWidget);
      expect(find.text('Passed'), findsNWidgets(21));
      expect(find.text('Available'), findsOneWidget);
      expect(find.text('Selected'), findsOneWidget);
      expect(find.text('Unavailable'), findsOneWidget);
      expect(_tappable(tester, '10:00 AM'), isFalse);
      expect(_tappable(tester, '10:30 AM'), isTrue);

      await tester.tap(_slot('10:30 AM'));
      await _settle(tester);
      expect(_selected(tester, '10:30 AM'), isTrue);
    });

    testWidgets('three columns, two at 380 wide and below', (tester) async {
      Future<int> inFirstRow(double width) async {
        await tester.pumpWidget(const SizedBox());
        await _openForm(tester, () => _at(0, 0), width: width);
        final top = tester.getTopLeft(_slot('12:00 AM')).dy;
        return kTimeSlots
            .take(4)
            .where((s) => tester.getTopLeft(_slot(s)).dy == top)
            .length;
      }

      expect(await inFirstRow(412), 3);
      expect(await inFirstRow(381), 3);
      expect(await inFirstRow(380), 2);
      expect(await inFirstRow(320), 2);
    });

    testWidgets('a selected slot is cleared once its time comes', (
      tester,
    ) async {
      var now = _at(10, 0);
      await _openForm(tester, () => now);
      await tester.tap(_slot('10:30 AM'));
      await _settle(tester);

      now = _at(10, 30);
      await tester.pump(const Duration(seconds: 16));
      await _settle(tester);

      expect(_selected(tester, '10:30 AM'), isFalse);
      expect(_tappable(tester, '10:30 AM'), isFalse);
      expect(find.text('26 of 48 slots available'), findsOneWidget);
    });

    testWidgets('Proceed to Payment stops on a slot that has just passed', (
      tester,
    ) async {
      var now = _at(10, 0);
      await _openForm(tester, () => now);
      await tester.tap(_slot('10:30 AM'));
      await tester.enterText(find.byType(TextField), 'Fever');
      await _settle(tester);

      now = _at(10, 31);
      await _proceed(tester);

      expect(find.text(kSlotPassedMessage), findsOneWidget);
      expect(find.text('Patient Informed Consent'), findsNothing);
      expect(_selected(tester, '10:30 AM'), isFalse);
    });

    testWidgets('a slot passing while the consent dialog is open stops too', (
      tester,
    ) async {
      var now = _at(10, 0);
      await _openForm(tester, () => now);
      await tester.tap(_slot('10:30 AM'));
      await tester.enterText(find.byType(TextField), 'Fever');
      await _settle(tester);
      await _proceed(tester);
      for (final box in [0, 1]) {
        await tester.tap(find.byType(Checkbox).at(box));
        await _settle(tester);
      }

      now = _at(10, 31);
      await tester.tap(find.text('Confirm & Continue →'));
      await _settle(tester);

      expect(find.text(kSlotPassedMessage), findsOneWidget);
      expect(find.text('Book an Appointment'), findsOneWidget);
    });

    Map<String, dynamic> paymentArgs() => {
      ..._selection,
      'date': _at(0, 0).toString(),
      'time': '10:30 AM',
      'problem': 'Fever',
      'medicalReports': <Map<String, dynamic>>[],
    };

    Future<void> tapPay(WidgetTester tester) async {
      await tester.tap(find.textContaining('with Razorpay'));
      await _settle(tester);
      await _settle(tester);
    }

    testWidgets('payment screen: nothing is created for a passed slot', (
      tester,
    ) async {
      await _open(
        tester,
        AppointmentPaymentPage(clock: () => _at(10, 30)),
        paymentArgs(),
      );
      await tapPay(tester);

      expect(requests, isEmpty);
      expect(find.text(kSlotPassedMessage), findsOneWidget);
      expect(find.text('PREVIOUS SCREEN'), findsOneWidget);
      expect(find.text('Appointment Summary'), findsNothing);
    });

    testWidgets('payment screen: asked again right before the order', (
      tester,
    ) async {
      var asked = 0;
      await _open(
        tester,
        // Still ahead when Pay is tapped, gone by the time the order is due.
        AppointmentPaymentPage(
          clock: () => asked++ == 0 ? _at(10, 29) : _at(10, 30),
        ),
        paymentArgs(),
      );
      await tapPay(tester);

      expect(asked, 2);
      expect(requests, isEmpty);
      expect(find.text(kSlotPassedMessage), findsOneWidget);
      expect(find.text('PREVIOUS SCREEN'), findsOneWidget);
    });

    testWidgets('payment screen: a slot still ahead goes on to the order', (
      tester,
    ) async {
      await _open(
        tester,
        AppointmentPaymentPage(clock: () => _at(10, 0)),
        paymentArgs(),
      );
      await tapPay(tester);

      expect(requests.single, endsWith('/razorpay/create-order'));
      expect(find.text(kSlotPassedMessage), findsNothing);
    });
  });
}

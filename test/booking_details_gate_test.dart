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
import 'package:humancare_connect/screens/complete_details_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/auth_service.dart';
import 'package:humancare_connect/services/currency_service.dart';
import 'package:humancare_connect/services/payment_service.dart';
import 'package:humancare_connect/services/pricing_service.dart';
import 'package:humancare_connect/services/razorpay_checkout.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:humancare_connect/utils/time_slots.dart';
import 'package:shared_preferences/shared_preferences.dart';

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

final _today = DateTime.now();

DateTime _at(int hour, int minute) =>
    DateTime(_today.year, _today.month, _today.day, hour, minute);

/// Answers the profile calls and the two payment-start calls.
class _Server {
  int meStatus = 200;
  String dob = '';
  String gender = '';
  int startStatus = 422;
  final requests = <http.Request>[];

  int count(String suffix) =>
      requests.where((r) => r.url.path.endsWith(suffix)).length;

  Future<http.Response> handle(http.Request request) async {
    requests.add(request);
    final path = request.url.path;
    http.Response json(Object body, [int status = 200]) =>
        http.Response(jsonEncode(body), status);

    if (path.endsWith('/auth/me')) {
      if (meStatus != 200) return json({'msg': 'Server error.'}, meStatus);
      return json({
        'user': {'_id': 'u1', 'dob': dob, 'gender': gender},
      });
    }
    if (path.endsWith('/auth/patient-details')) return json({'user': {}});
    if (path.endsWith('/razorpay/create-order') ||
        path.endsWith('/payments/create-intent-by-amount')) {
      return startStatus == 422
          ? json({
              'code': 'PROFILE_INCOMPLETE',
              'missing': ['dob', 'gender'],
              'msg':
                  'Please complete your date of birth and gender to continue.',
            }, 422)
          : json({'msg': 'Payments are not available right now.'}, startStatus);
    }
    return json({}, 404);
  }

  ApiClient get client => ApiClient(
    client: MockClient(handle),
    tokenStorage: const TokenStorageService(),
  );

  AuthService get auth => AuthService(apiClient: client);
}

class _Launcher implements RazorpayLauncher {
  int opened = 0;

  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async {
    opened++;
    return const RazorpayCancelled();
  }
}

final _navigatorKey = GlobalKey<NavigatorState>();

/// The arguments the form handed to the payment screen, if it got there.
Map<String, dynamic>? _paymentArguments;

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 16; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _open(
  WidgetTester tester,
  Widget page,
  Map<String, dynamic> arguments,
) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 3200);
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigatorKey,
      home: const Scaffold(body: Text('PREVIOUS SCREEN')),
      routes: {
        '/appointment-payment': (context) {
          _paymentArguments =
              ModalRoute.of(context)!.settings.arguments
                  as Map<String, dynamic>;
          return const Scaffold(body: Text('PAYMENT SCREEN'));
        },
      },
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

/// Fills the form (today, 10:30 AM, "Fever") and confirms the consent.
Future<void> _bookFromForm(
  WidgetTester tester,
  _Server server, {
  DateTime Function()? clock,
}) async {
  await _open(
    tester,
    AppointmentFormPage(
      clock: clock ?? () => _at(10, 0),
      authService: server.auth,
    ),
    _selection,
  );
  await tester.tap(find.text('Select date'));
  await _settle(tester);
  await tester.tap(find.text('OK'));
  await _settle(tester);
  await tester.tap(find.byKey(const ValueKey('slot 10:30 AM')));
  await tester.enterText(find.byType(TextField), 'Fever');
  await _settle(tester);
  await tester.tap(find.textContaining('Proceed to Payment'));
  await _settle(tester);
  for (final box in [0, 1]) {
    await tester.tap(find.byType(Checkbox).at(box));
    await _settle(tester);
  }
  await tester.tap(find.text('Confirm & Continue →'));
  await _settle(tester);
}

/// Picks a date and a gender on the details screen and saves.
Future<void> _completeDetails(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('details dob')));
  await _settle(tester);
  await tester.tap(find.text('OK'));
  await _settle(tester);
  await tester.tap(find.text('Female'));
  await _settle(tester);
  await tester.tap(find.text('Save & Continue to Payment →'));
  await _settle(tester);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Server server;
  late _Launcher launcher;
  var currency = 'INR';

  setUp(() {
    server = _Server();
    launcher = _Launcher();
    currency = 'INR';
    _paymentArguments = null;
    dotenv.testLoad(
      fileInput:
          'API_BASE_URL=https://example.test/api\nVITE_STRIPE_PUBLISHABLE_KEY=pk_live_x',
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
    PricingService.instance = PricingService(
      apiClient: ApiClient(
        client: MockClient(
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
        tokenStorage: const TokenStorageService(),
      ),
    );
    CurrencyService.instance = CurrencyService(
      fetchCurrency: () async => {'currency': currency, 'source': 'ip'},
      wait: (_) async {},
      observeLifecycle: false,
    );
    PaymentService.instance = PaymentService(apiClient: server.client);
    RazorpayCheckout.launcher = launcher;

    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const timeZone = MethodChannel('flutter_timezone');
    const stripe = MethodChannel('flutter.stripe/payments', JSONMethodCodec());
    messenger.setMockMethodCallHandler(timeZone, (_) async => 'Asia/Kolkata');
    messenger.setMockMethodCallHandler(stripe, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(timeZone, null);
      messenger.setMockMethodCallHandler(stripe, null);
    });
  });

  group('booking form', () {
    testWidgets('a complete profile goes straight to payment', (tester) async {
      server
        ..dob = '1990-05-01'
        ..gender = 'Male';
      await _bookFromForm(tester, server);

      expect(find.text('PAYMENT SCREEN'), findsOneWidget);
      expect(find.byType(CompleteDetailsScreen), findsNothing);
      expect(server.count('/auth/patient-details'), 0);
    });

    for (final missing in ['date of birth', 'gender']) {
      testWidgets('a missing $missing opens the step first', (tester) async {
        server
          ..dob = missing == 'gender' ? '1990-05-01' : ''
          ..gender = missing == 'gender' ? '' : 'Male';
        await _bookFromForm(tester, server);

        expect(find.byType(CompleteDetailsScreen), findsOneWidget);
        expect(_paymentArguments, isNull);
      });
    }

    testWidgets('back from the step keeps everything and goes nowhere', (
      tester,
    ) async {
      await _bookFromForm(tester, server);
      await tester.pageBack();
      await _settle(tester);

      expect(find.byType(CompleteDetailsScreen), findsNothing);
      expect(_paymentArguments, isNull);
      expect(find.text('Book an Appointment'), findsOneWidget);
      expect(find.text('Fever'), findsWidgets);
      expect(find.text('Select date'), findsNothing);
      expect(
        tester
            .widget<Text>(
              find.descendant(
                of: find.byKey(const ValueKey('slot 10:30 AM')),
                matching: find.text('10:30 AM'),
              ),
            )
            .style!
            .color,
        Colors.white,
      );
      // The button works again.
      expect(find.textContaining('Proceed to Payment'), findsOneWidget);
    });

    testWidgets('after saving, payment opens with the same selection', (
      tester,
    ) async {
      await _bookFromForm(tester, server);
      await _completeDetails(tester);

      expect(find.text('PAYMENT SCREEN'), findsOneWidget);
      expect(server.count('/auth/patient-details'), 1);
      expect(_paymentArguments!['time'], '10:30 AM');
      expect(_paymentArguments!['problem'], 'Fever');
      expect(_paymentArguments!['condName'], 'Fever');
    });

    testWidgets('if /auth/me fails, booking carries on', (tester) async {
      server.meStatus = 500;
      await _bookFromForm(tester, server);

      expect(find.text('PAYMENT SCREEN'), findsOneWidget);
      expect(find.byType(CompleteDetailsScreen), findsNothing);
    });

    testWidgets('a slot that passes during the step stops before payment', (
      tester,
    ) async {
      var now = _at(10, 0);
      await _bookFromForm(tester, server, clock: () => now);
      now = _at(10, 31);
      await _completeDetails(tester);

      expect(_paymentArguments, isNull);
      expect(find.text(kSlotPassedMessage), findsOneWidget);
      expect(find.text('Book an Appointment'), findsOneWidget);
    });
  });

  group('payment screen', () {
    Future<void> pay(WidgetTester tester, String button) async {
      await _open(
        tester,
        AppointmentPaymentPage(
          clock: () => _at(10, 0),
          authService: server.auth,
        ),
        {
          ..._selection,
          'date': _at(0, 0).toString(),
          'time': '10:30 AM',
          'problem': 'Fever',
          'medicalReports': <Map<String, dynamic>>[],
        },
      );
      await tester.tap(find.textContaining(button));
      await _settle(tester);
      await _settle(tester);
    }

    for (final (gateway, code, button, path) in [
      ('Razorpay', 'INR', 'with Razorpay', '/razorpay/create-order'),
      ('Stripe', 'USD', r'Pay $59', '/payments/create-intent-by-amount'),
    ]) {
      testWidgets('$gateway: 422 opens the step; saving does not charge', (
        tester,
      ) async {
        currency = code;
        await pay(tester, button);
        expect(find.byType(CompleteDetailsScreen), findsOneWidget);

        await _completeDetails(tester);

        expect(find.byType(CompleteDetailsScreen), findsNothing);
        expect(find.text('Appointment Summary'), findsOneWidget);
        expect(
          find.text('Details saved. Tap Pay to continue.'),
          findsOneWidget,
        );
        expect(server.count(path), 1);
        expect(server.count('/appointments'), 0);
        expect(launcher.opened, 0);
        // The button is ready for the next tap.
        expect(
          tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
          isNotNull,
        );
        for (final request in server.requests) {
          expect(
            request.headers.keys.map((k) => k.toLowerCase()),
            isNot(contains('x-client')),
          );
        }
      });

      testWidgets('$gateway: any other refusal shows its message as before', (
        tester,
      ) async {
        currency = code;
        server.startStatus = 503;
        await pay(tester, button);

        expect(find.byType(CompleteDetailsScreen), findsNothing);
        expect(
          find.text('Payments are not available right now.'),
          findsOneWidget,
        );
      });
    }

    testWidgets('back from the step stays on payment with no message', (
      tester,
    ) async {
      await pay(tester, 'with Razorpay');
      await tester.pageBack();
      await _settle(tester);

      expect(find.text('Appointment Summary'), findsOneWidget);
      expect(find.text('Details saved. Tap Pay to continue.'), findsNothing);
      expect(server.count('/auth/patient-details'), 0);
    });
  });
}

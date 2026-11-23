import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/screens/book_appointment_payment_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/currency_service.dart';
import 'package:humancare_connect/services/payment_service.dart';
import 'package:humancare_connect/services/pricing_service.dart';
import 'package:humancare_connect/services/razorpay_checkout.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _payment = RazorpayPayment(
  orderId: 'order_ABC123def',
  paymentId: 'pay_XYZ789ghi',
  signature: 'sig0123456789',
);

const _table = {
  'general': {
    'price': 59,
    'label': 'General & Everyday Care',
    'currency': 'USD',
    'priceEur': 55,
    'priceGbp': 49,
    'priceInr': 4999,
  },
};

Map<String, dynamic> _args({String label = 'General & Everyday Care'}) => {
  'specName': 'General Physician',
  'catLabel': label,
  'catId': 'mongo-general',
  'pricingSlug': 'general',
  'condName': 'Fever',
  'cost': 59,
  'date': '2026-12-01 00:00:00.000',
  'time': '10:00 AM',
  'problem': 'Fever',
  'medicalReports': <Map<String, dynamic>>[],
};

class _FakeLauncher implements RazorpayLauncher {
  _FakeLauncher(this.outcome);

  RazorpayOutcome outcome;
  final opened = <Map<String, dynamic>>[];

  @override
  Future<RazorpayOutcome> open(Map<String, dynamic> options) async {
    opened.add(options);
    return outcome;
  }
}

/// Records every request and answers by path.
class _Backend {
  int orderStatus = 200;
  int orderAmountPaise = 499900;
  List<int> bookingStatuses = const [201];
  final requests = <({String path, Map<String, dynamic> body})>[];

  List<Map<String, dynamic>> bodiesFor(String suffix) => [
    for (final r in requests)
      if (r.path.endsWith(suffix)) r.body,
  ];

  Future<http.Response> handle(http.Request request) async {
    final path = request.url.path;
    final body = request.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(request.body) as Map<String, dynamic>;
    requests.add((path: path, body: body));

    if (path.endsWith('/razorpay/create-order')) {
      if (orderStatus != 200) {
        return http.Response(
          jsonEncode({'msg': 'Razorpay payments are not available right now.'}),
          orderStatus,
        );
      }
      return http.Response(
        jsonEncode({
          'orderId': 'order_ABC123def',
          'amountCents': orderAmountPaise,
          'currency': 'INR',
          'keyId': 'rzp_live_publickey',
        }),
        200,
      );
    }
    if (path.endsWith('/appointments')) {
      final index = requests.where((r) => r.path.endsWith('/appointments')).length - 1;
      final status = bookingStatuses[index < bookingStatuses.length ? index : bookingStatuses.length - 1];
      return status < 300
          ? http.Response(jsonEncode({'appointment': {'_id': 'appt1'}}), status)
          : http.Response(jsonEncode({'msg': 'Booking refused ($status).'}), status);
    }
    return http.Response('{}', 404);
  }
}

PaymentService _paymentService(_Backend backend) => PaymentService(
  apiClient: ApiClient(
    client: MockClient(backend.handle),
    tokenStorage: const TokenStorageService(),
  ),
);

CurrencyService _currency(String code) => CurrencyService(
  fetchCurrency: () async => {'currency': code, 'country': '', 'source': 'ip'},
  wait: (_) async {},
  observeLifecycle: false,
);

PricingService _pricing() => PricingService(
  apiClient: ApiClient(
    client: MockClient((_) async => http.Response(jsonEncode(_table), 200)),
    tokenStorage: const TokenStorageService(),
  ),
);

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _open(WidgetTester tester, Map<String, dynamic> args) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigatorKey,
      home: const Scaffold(),
      onGenerateRoute: (settings) {
        if (settings.name == '/appointment-confirmation') {
          return MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => const Scaffold(body: Text('BOOKING CONFIRMED')),
          );
        }
        return null;
      },
    ),
  );
  unawaited(
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(arguments: args),
        builder: (_) => const AppointmentPaymentPage(),
      ),
    ),
  );
  await _settle(tester);
}

Future<void> _settle(WidgetTester tester, [int frames = 12]) async {
  for (var i = 0; i < frames; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _tapPay(WidgetTester tester, String label) async {
  await tester.tap(find.text(label));
  await _settle(tester, 25);
}

Map<String, String> _signedIn() => {
  'auth_token': 'access',
  'user_id': 'user-1',
  'user_name': 'Asha',
  'user_email': 'asha@example.com',
  'user_mobile': '+919876543210',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _Backend backend;
  late _FakeLauncher launcher;

  setUp(() {
    dotenv.testLoad(
      fileInput: 'API_BASE_URL=https://example.test/api\nVITE_STRIPE_PUBLISHABLE_KEY=pk_live_x',
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues(_signedIn());
    backend = _Backend();
    launcher = _FakeLauncher(const RazorpaySuccess(_payment));
    PaymentService.instance = _paymentService(backend);
    PricingService.instance = _pricing();
    CurrencyService.instance = _currency('INR');
    RazorpayCheckout.launcher = launcher;
    PendingRazorpayBookingStore.instance = PendingRazorpayBookingStore();

    const channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'Asia/Kolkata');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  });

  group('Razorpay helpers', () {
    test('Checkout opens with the same options as the web', () {
      expect(
        RazorpayCheckout.buildOptions(
          keyId: 'rzp_live_x',
          orderId: 'order_1',
          amountPaise: 499900,
          description: 'General booking fee',
          name: ' Asha ',
          email: 'asha@example.com',
          contact: '+919876543210',
        ),
        {
          'key': 'rzp_live_x',
          'order_id': 'order_1',
          'amount': 499900,
          'currency': 'INR',
          'name': 'Humancare Connect',
          'description': 'General booking fee',
          'prefill': {
            'name': 'Asha',
            'email': 'asha@example.com',
            'contact': '+919876543210',
          },
          'theme': {'color': '#0a1f44'},
          'retry': {'enabled': true, 'max_count': 4},
        },
      );
    });

    test('the booking carries the three values Checkout returned', () {
      expect(_payment.toBookingFields(), {
        'razorpayOrderId': 'order_ABC123def',
        'razorpayPaymentId': 'pay_XYZ789ghi',
        'razorpaySignature': 'sig0123456789',
      });
    });

    test('a failure shows Razorpay\'s description, else the web text', () {
      expect(
        razorpayFailureText(
          message: '{"error":{}}',
          error: {'error': {'description': 'Your bank declined the payment.'}},
        ),
        'Your bank declined the payment.',
      );
      expect(razorpayFailureText(message: 'Network problem'), 'Network problem');
      expect(razorpayFailureText(message: '{"raw": "json"}'), kRazorpayFailedMessage);
      expect(razorpayFailureText(), 'Payment failed. Please try again.');
    });

    test('the web texts are used word for word', () {
      expect(
        kRazorpayCancelledMessage,
        'Payment was cancelled. You have not been charged. You can try again.',
      );
      expect(kRazorpayStartFailedMessage, 'Failed to start the payment. Please try again.');
    });
  });

  group('create-order', () {
    test('sends only what is being booked and reads the server\'s order', () async {
      final result = await _paymentService(backend).createRazorpayOrder(
        priceType: 'category',
        priceRef: 'mongo-general',
      );

      expect(backend.requests.single.path, '/api/razorpay/create-order');
      expect(backend.requests.single.body, {
        'priceType': 'category',
        'priceRef': 'mongo-general',
      });
      expect(result.success, isTrue);
      expect(result.data!.orderId, 'order_ABC123def');
      expect(result.data!.amountCents, 499900);
      expect(result.data!.currency, 'INR');
      expect(result.data!.keyId, 'rzp_live_publickey');
    });

    test('a refusal carries the server message', () async {
      backend.orderStatus = 503;
      final result = await _paymentService(backend).createRazorpayOrder(
        priceType: 'category',
        priceRef: 'x',
      );
      expect(result.success, isFalse);
      expect(result.message, 'Razorpay payments are not available right now.');
    });
  });

  group('a paid-but-unsaved booking is kept in secure storage', () {
    final booking = PendingRazorpayBooking(payment: _payment, args: _args(), amount: 59);

    test('save, load and clear', () async {
      final store = PendingRazorpayBookingStore();
      expect(await store.load('user-1'), isNull);

      await store.save('user-1', booking);
      final loaded = await store.load('user-1');

      expect(loaded!.payment.paymentId, 'pay_XYZ789ghi');
      expect(loaded.payment.signature, 'sig0123456789');
      expect(loaded.args['catLabel'], 'General & Everyday Care');
      expect(loaded.args['problem'], 'Fever');
      expect(loaded.amount, 59);

      await store.clear('user-1');
      expect(await store.load('user-1'), isNull);
    });

    test('one customer never sees another one\'s booking', () async {
      final store = PendingRazorpayBookingStore();
      await store.save('user-1', booking);
      expect(await store.load('user-2'), isNull);
      expect(await store.load(''), isNull);
    });

    test('nothing is stored without a signed-in customer', () async {
      final store = PendingRazorpayBookingStore();
      await store.save('', booking);
      expect(await store.load(''), isNull);
    });

    test('a damaged entry is dropped, never an error', () async {
      FlutterSecureStorage.setMockInitialValues({
        'pending_razorpay_booking_user-1': 'not json',
      });
      final store = PendingRazorpayBookingStore();
      expect(await store.load('user-1'), isNull);
      expect(await const FlutterSecureStorage().read(key: 'pending_razorpay_booking_user-1'), isNull);
    });
  });

  group('payment screen, rupees', () {
    testWidgets('shows rupees, the Razorpay wording and the web button text', (tester) async {
      await _open(tester, _args());

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('₹4,999'), findsOneWidget);
      expect(find.text('Online Payment'), findsOneWidget);
      expect(find.text('Secure checkout is processed by Razorpay.'), findsOneWidget);
      expect(find.text('UPI · Cards · Netbanking · Wallets'), findsOneWidget);
      expect(find.text('Pay ₹4,999 with Razorpay'), findsOneWidget);
      expect(find.text('Card Payment'), findsNothing);
      expect(find.textContaining('Stripe'), findsNothing);
    });

    testWidgets('other currencies keep the Stripe wording', (tester) async {
      CurrencyService.instance = _currency('GBP');
      await _open(tester, _args());

      expect(find.text('Card Payment'), findsOneWidget);
      expect(
        find.text('Secure checkout is processed by Stripe. Your card details are not stored in this app.'),
        findsOneWidget,
      );
      expect(find.text('Pay £49'), findsOneWidget);
      expect(find.text('UPI · Cards · Netbanking · Wallets'), findsNothing);
      expect(find.text('Online Payment'), findsNothing);
    });

    testWidgets('a category with no INR price stays USD with the Stripe wording', (tester) async {
      PricingService.instance = PricingService(
        apiClient: ApiClient(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'general': {'price': 59, 'label': 'General & Everyday Care', 'priceInr': null},
              }),
              200,
            ),
          ),
          tokenStorage: const TokenStorageService(),
        ),
      );
      await _open(tester, _args());

      expect(find.text(r'$59'), findsOneWidget);
      expect(find.text('Card Payment'), findsOneWidget);
      expect(find.text(r'Pay $59'), findsOneWidget);
    });

    testWidgets('pays: order, Checkout with the server\'s order, then the booking', (tester) async {
      await _open(tester, _args());
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      // 1. The server creates the order from what is being booked.
      expect(backend.bodiesFor('/razorpay/create-order').single, {
        'priceType': 'category',
        'priceRef': 'mongo-general',
      });

      // 2. Checkout opens for that order.
      final options = launcher.opened.single;
      expect(options['key'], 'rzp_live_publickey');
      expect(options['order_id'], 'order_ABC123def');
      expect(options['amount'], 499900);
      expect(options['currency'], 'INR');
      expect(options['description'], 'General & Everyday Care booking fee');
      expect((options['prefill'] as Map)['name'], 'Asha');
      expect((options['prefill'] as Map)['email'], 'asha@example.com');
      expect((options['prefill'] as Map)['contact'], '+919876543210');

      // 3. The booking carries the three values, and never a Stripe intent.
      final booking = backend.bodiesFor('/appointments').single;
      expect(booking['razorpayOrderId'], 'order_ABC123def');
      expect(booking['razorpayPaymentId'], 'pay_XYZ789ghi');
      expect(booking['razorpaySignature'], 'sig0123456789');
      expect(booking.containsKey('paymentIntentId'), isFalse);
      expect(booking['consultationPrice'], 59); // the USD price, as on the web
      expect(booking['patientTimezone'], 'Asia/Kolkata');
      expect(booking['categoryId'], 'mongo-general');

      expect(find.text('BOOKING CONFIRMED'), findsOneWidget);
      expect(await PendingRazorpayBookingStore.instance.load('user-1'), isNull);
    });

    testWidgets('closing Checkout says nothing was charged, and books nothing', (tester) async {
      launcher.outcome = const RazorpayCancelled();
      await _open(tester, _args());
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      expect(
        find.text('Payment was cancelled. You have not been charged. You can try again.'),
        findsOneWidget,
      );
      expect(backend.bodiesFor('/appointments'), isEmpty);
      expect(find.text('Complete Booking'), findsNothing);
      expect(await PendingRazorpayBookingStore.instance.load('user-1'), isNull);
    });

    testWidgets('a failed payment shows the reason and books nothing', (tester) async {
      launcher.outcome = const RazorpayFailed('Your bank declined the payment.');
      await _open(tester, _args());
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      expect(find.text('Your bank declined the payment.'), findsOneWidget);
      expect(backend.bodiesFor('/appointments'), isEmpty);
    });

    testWidgets('an order the server refuses shows its message; Checkout never opens', (tester) async {
      backend.orderStatus = 503;
      await _open(tester, _args());
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      expect(find.text('Razorpay payments are not available right now.'), findsOneWidget);
      expect(launcher.opened, isEmpty);
    });

    testWidgets('an order for another amount than the one shown is refused (stricter than the web)', (tester) async {
      backend.orderAmountPaise = 599900;
      await _open(tester, _args());
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      expect(
        find.text('The price for this appointment changed. Please go back and try again.'),
        findsOneWidget,
      );
      expect(launcher.opened, isEmpty);
    });

    testWidgets('the location changing right before the order creates nothing', (tester) async {
      var answer = 'INR';
      CurrencyService.instance = CurrencyService(
        fetchCurrency: () async => {'currency': answer, 'country': '', 'source': 'ip'},
        wait: (_) async {},
        observeLifecycle: false,
      );
      await _open(tester, _args());
      expect(find.text('Pay ₹4,999 with Razorpay'), findsOneWidget);

      answer = 'GBP';
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      expect(backend.bodiesFor('/razorpay/create-order'), isEmpty);
      expect(launcher.opened, isEmpty);
      expect(find.text('Pay £49'), findsOneWidget);
      expect(find.text('Prices updated to your current location (£ GBP)'), findsOneWidget);
    });

    testWidgets('paid but the booking could not be saved: finish it without paying again', (tester) async {
      backend.bookingStatuses = [500, 201];
      await _open(tester, _args());
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      // The customer has paid, the booking failed: the payment is kept.
      expect(find.text('Booking refused (500).'), findsOneWidget);
      expect(find.text('Payment Received'), findsOneWidget);
      expect(
        find.text(
          'Your payment has already been charged. We just need to finish saving your appointment — tap below to complete it. You will not be charged again.',
        ),
        findsOneWidget,
      );
      expect(find.text('Complete Booking'), findsOneWidget);
      final saved = await PendingRazorpayBookingStore.instance.load('user-1');
      expect(saved!.payment.paymentId, 'pay_XYZ789ghi');
      expect(saved.args['problem'], 'Fever');

      // Complete Booking: the same payment, no new order, no new Checkout.
      await _tapPay(tester, 'Complete Booking');

      expect(backend.bodiesFor('/razorpay/create-order'), hasLength(1));
      expect(launcher.opened, hasLength(1));
      final bookings = backend.bodiesFor('/appointments');
      expect(bookings, hasLength(2));
      expect(bookings.last['razorpayPaymentId'], 'pay_XYZ789ghi');
      expect(find.text('BOOKING CONFIRMED'), findsOneWidget);
      expect(await PendingRazorpayBookingStore.instance.load('user-1'), isNull);
    });

    testWidgets('a final refusal (4xx) drops the saved payment, so nobody is stuck', (tester) async {
      backend.bookingStatuses = [409];
      await _open(tester, _args());
      await _tapPay(tester, 'Pay ₹4,999 with Razorpay');

      expect(find.text('Booking refused (409).'), findsOneWidget);
      expect(find.text('Complete Booking'), findsNothing);
      expect(await PendingRazorpayBookingStore.instance.load('user-1'), isNull);
    });

    testWidgets('after the app was closed, the saved paid booking comes back', (tester) async {
      await PendingRazorpayBookingStore.instance.save(
        'user-1',
        PendingRazorpayBooking(
          payment: _payment,
          args: _args(label: 'Saved Category'),
          amount: 59,
        ),
      );

      // A different booking is opened, but the saved one is what is finished.
      await _open(tester, _args(label: 'Another Category'));

      expect(find.text('Payment Received'), findsOneWidget);
      expect(find.text('Complete Booking'), findsOneWidget);
      expect(find.text('Saved Category'), findsOneWidget);
      expect(find.text('Another Category'), findsNothing);

      await _tapPay(tester, 'Complete Booking');

      expect(backend.bodiesFor('/razorpay/create-order'), isEmpty);
      expect(launcher.opened, isEmpty);
      final booking = backend.bodiesFor('/appointments').single;
      expect(booking['razorpayPaymentId'], 'pay_XYZ789ghi');
      expect(booking['category'], 'Saved Category');
      expect(find.text('BOOKING CONFIRMED'), findsOneWidget);
      expect(await PendingRazorpayBookingStore.instance.load('user-1'), isNull);
    });

    testWidgets('a saved booking of another customer is not offered', (tester) async {
      await PendingRazorpayBookingStore.instance.save(
        'someone-else',
        PendingRazorpayBooking(payment: _payment, args: _args(), amount: 59),
      );
      await _open(tester, _args());

      expect(find.text('Payment Received'), findsNothing);
      expect(find.text('Pay ₹4,999 with Razorpay'), findsOneWidget);
    });
  });
}

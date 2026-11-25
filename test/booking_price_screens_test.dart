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
import 'package:humancare_connect/services/pricing_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _table = {
  'general': {
    'price': 59,
    'label': 'General & Everyday Care',
    'currency': 'USD',
    'priceEur': 55,
    'priceGbp': 49,
  },
  'mental': {'price': 39, 'label': 'Mental Health', 'currency': 'USD'},
};

Map<String, dynamic> _selection({
  String slug = 'general',
  String label = 'General & Everyday Care',
  num cost = 59,
  Map<String, dynamic> extra = const {},
}) => {
  'specName': 'General Physician',
  'specIcon': '🩺',
  'catLabel': label,
  'catId': 'mongo-$slug',
  'pricingSlug': slug,
  'condName': 'Fever',
  'condIcon': '',
  'cost': cost,
  ...extra,
};

PricingService _pricingService({bool fails = false}) => PricingService(
  apiClient: ApiClient(
    client: MockClient((_) async {
      if (fails) return http.Response('{}', 500);
      return http.Response(jsonEncode(_table), 200);
    }),
    tokenStorage: const TokenStorageService(),
  ),
);

CurrencyService _currencyService(Future<Map<String, dynamic>> Function() fetch) =>
    CurrencyService(
      fetchCurrency: fetch,
      wait: (_) async {},
      observeLifecycle: false,
    );

Map<String, dynamic> _answer(String currency) => {
  'currency': currency,
  'country': '',
  'source': 'ip',
};

final _navigatorKey = GlobalKey<NavigatorState>();

Future<void> _open(
  WidgetTester tester, {
  required Widget page,
  required Map<String, dynamic> arguments,
}) async {
  tester.view.physicalSize = const Size(800, 2400);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(navigatorKey: _navigatorKey, home: const Scaffold()),
  );
  unawaited(
    _navigatorKey.currentState!.push(
      MaterialPageRoute<void>(
        settings: RouteSettings(arguments: arguments),
        builder: (_) => page,
      ),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(
      fileInput: 'API_BASE_URL=https://example.test/api\nVITE_STRIPE_PUBLISHABLE_KEY=pk_test_x',
    );
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
    PricingService.instance = _pricingService();
    CurrencyService.instance = _currencyService(() async => _answer('USD'));
    // The payment screen reads the device time zone when it opens.
    const channel = MethodChannel('flutter_timezone');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async => 'Europe/London');
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );
  });

  group('booking form', () {
    Future<void> openForm(WidgetTester tester, Map<String, dynamic> selection) =>
        _open(tester, page: const AppointmentFormPage(), arguments: selection);

    testWidgets('a UK customer sees the GBP price (Fee and button)', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('GBP'));
      await openForm(tester, _selection());

      expect(find.text('£49'), findsOneWidget);
      expect(find.text('Proceed to Payment — £49 →'), findsOneWidget);
      expect(find.text(r'$59'), findsNothing);
    });

    testWidgets('a EU customer sees the EUR price', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('EUR'));
      await openForm(tester, _selection());

      expect(find.text('€55'), findsOneWidget);
      expect(find.text('Proceed to Payment — €55 →'), findsOneWidget);
    });

    testWidgets('everyone else sees USD, exactly as before', (tester) async {
      await openForm(tester, _selection());

      expect(find.text(r'$59'), findsOneWidget);
      expect(find.text(r'Proceed to Payment — $59 →'), findsOneWidget);
    });

    testWidgets('a category with no GBP price shows its USD price, labelled USD', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('GBP'));
      await openForm(
        tester,
        _selection(slug: 'mental', label: 'Mental Health', cost: 39),
      );

      expect(find.text(r'$39'), findsOneWidget);
      expect(find.text('£39'), findsNothing);
    });

    testWidgets('while the currency is loading there is no price and no tap', (tester) async {
      final never = Completer<Map<String, dynamic>>();
      CurrencyService.instance = _currencyService(() => never.future);
      await openForm(tester, _selection());

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text(r'$59'), findsNothing);
      expect(find.text('Proceed to Payment →'), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a price table that did not load is "Price unavailable" for GBP', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('GBP'));
      PricingService.instance = _pricingService(fails: true);
      await openForm(tester, _selection());

      expect(find.text('Price unavailable'), findsOneWidget);
      expect(find.text('£49'), findsNothing);
      expect(find.text(r'$59'), findsNothing);
      expect(find.text('Proceed to Payment →'), findsOneWidget);
    });

    testWidgets('a service is priced from its own GBP price', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('GBP'));
      await openForm(
        tester,
        {
          'specName': 'Fit to fly',
          'catLabel': 'Service',
          'condName': '',
          'cost': 50,
          'priceEur': 45,
          'priceGbp': 40,
          'bookingType': 'service',
        },
      );

      expect(find.text('£40'), findsOneWidget);
    });

    testWidgets('a location change moves the price and says so, with the web text', (tester) async {
      var answer = 'USD';
      CurrencyService.instance = _currencyService(() async => _answer(answer));
      await openForm(tester, _selection());
      expect(find.text(r'$59'), findsOneWidget);

      answer = 'GBP';
      await CurrencyService.instance.recheck(force: true);
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('£49'), findsOneWidget);
      expect(
        find.text('Prices updated to your current location (£ GBP)'),
        findsOneWidget,
      );
    });
  });

  group('payment screen', () {
    Map<String, dynamic> paymentArgs([Map<String, dynamic> selection = const {}]) => {
      ..._selection(),
      'date': '2099-12-01 00:00:00.000',
      'time': '10:00 AM',
      'problem': 'Fever',
      'medicalReports': <Map<String, dynamic>>[],
      ...selection,
    };

    Future<void> openPayment(WidgetTester tester, Map<String, dynamic> args) =>
        _open(tester, page: const AppointmentPaymentPage(), arguments: args);

    testWidgets('shows the GBP total and a Pay button with the same amount', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('GBP'));
      await openPayment(tester, paymentArgs());

      expect(find.text('Total'), findsOneWidget);
      expect(find.text('£49'), findsOneWidget);
      expect(find.text('Pay £49'), findsOneWidget);
    });

    testWidgets('shows EUR and USD the same way', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('EUR'));
      await openPayment(tester, paymentArgs());
      expect(find.text('Pay €55'), findsOneWidget);

      CurrencyService.instance = _currencyService(() async => _answer('USD'));
      await openPayment(tester, paymentArgs());
      expect(find.text(r'Pay $59'), findsOneWidget);
    });

    testWidgets('while the price is loading: a placeholder, the web text, no tap', (tester) async {
      final never = Completer<Map<String, dynamic>>();
      CurrencyService.instance = _currencyService(() => never.future);
      await openPayment(tester, paymentArgs());

      expect(find.text('Loading your price...'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNull);
    });

    testWidgets('a price that is not available says so with the web text', (tester) async {
      CurrencyService.instance = _currencyService(() async => _answer('GBP'));
      PricingService.instance = _pricingService(fails: true);
      await openPayment(tester, paymentArgs());

      expect(find.text('Price unavailable'), findsOneWidget);
      expect(
        find.text(
          'The price is not available right now. Please go back and try again in a moment.',
        ),
        findsOneWidget,
      );
    });
  });
}

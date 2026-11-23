import 'dart:convert';

import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/currency_service.dart';
import 'package:humancare_connect/services/pricing_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Plays back a list of answers (a Map is an answer, anything else a failure).
class _Server {
  _Server(this.answers);

  final List<Object> answers;
  int calls = 0;

  Future<Map<String, dynamic>> call() async {
    final index = calls < answers.length ? calls : answers.length - 1;
    calls++;
    final answer = answers[index];
    if (answer is Map<String, dynamic>) return answer;
    throw StateError('server failed');
  }
}

Map<String, dynamic> _ip(String currency) => {
  'currency': currency,
  'country': currency == 'GBP' ? 'GB' : 'US',
  'source': 'ip',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<Duration> waits;
  late DateTime clock;

  CurrencyService service(
    _Server server, {
    List<Duration>? delays,
    int maxBackgroundRetries = 30,
  }) => CurrencyService(
    fetchCurrency: server.call,
    wait: (d) async => waits.add(d),
    now: () => clock,
    observeLifecycle: false,
    delays: delays ?? const [
      Duration(milliseconds: 400),
      Duration(seconds: 1),
      Duration(milliseconds: 2500),
      Duration(seconds: 5),
    ],
    maxBackgroundRetries: maxBackgroundRetries,
  );

  setUp(() {
    waits = [];
    clock = DateTime(2026, 11, 24, 10);
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
  });

  group('loading the currency', () {
    test('starts loading in USD, then shows the server answer', () async {
      final server = _Server([_ip('GBP')]);
      final s = service(server);
      expect(s.state.loading, isTrue);
      expect(s.currency, 'USD');

      await s.ensureLoaded();

      expect(s.state.loading, isFalse);
      expect(s.currency, 'GBP');
      expect(s.state.source, 'ip');
      expect(server.calls, 1);
      s.dispose();
    });

    test('ensureLoaded asks only once', () async {
      final server = _Server([_ip('EUR')]);
      final s = service(server);
      await Future.wait([s.ensureLoaded(), s.ensureLoaded()]);
      await s.ensureLoaded();
      expect(server.calls, 1);
      s.dispose();
    });

    test('a failed request is retried with the same backoff as the web', () async {
      final server = _Server(['fail', 'fail', _ip('GBP')]);
      final s = service(server);

      await s.ensureLoaded();

      expect(s.currency, 'GBP');
      expect(s.state.loading, isFalse);
      expect(waits, [const Duration(milliseconds: 400), const Duration(seconds: 1)]);
      s.dispose();
    });

    test('the server own "error" answer is not an answer: it is retried', () async {
      final server = _Server([
        {'currency': 'USD', 'country': '', 'source': 'error'},
        _ip('GBP'),
      ]);
      final s = service(server);

      await s.ensureLoaded();

      expect(s.currency, 'GBP');
      expect(server.calls, 2);
      s.dispose();
    });

    test('"default", "disabled" and "app-gate" are real answers (USD)', () async {
      for (final source in ['default', 'disabled', 'app-gate']) {
        final server = _Server([
          {'currency': 'USD', 'country': '', 'source': source},
        ]);
        final s = service(server);
        await s.ensureLoaded();
        expect(s.currency, 'USD', reason: source);
        expect(s.state.source, source);
        expect(s.state.loading, isFalse);
        expect(server.calls, 1, reason: source);
        s.dispose();
      }
    });

    test('rupees are never shown by this build: INR reads as USD', () async {
      final server = _Server([
        {'currency': 'INR', 'country': 'IN', 'source': 'ip'},
      ]);
      final s = service(server);
      await s.ensureLoaded();
      expect(s.currency, 'USD');
      s.dispose();
    });

    test('when every try fails: USD, source "error", and it keeps trying quietly', () async {
      final server = _Server(['fail', 'fail', 'fail', 'fail', 'fail', 'fail', _ip('GBP')]);
      final s = service(server);

      await s.ensureLoaded();
      // The first round is over: USD is shown (not loading) and marked "error".
      expect(s.currency, 'USD');
      expect(s.state.loading, isFalse);
      expect(s.state.source, 'error');

      // The background retry (every 20 s) finds the answer and tells everyone.
      final changes = <CurrencyChange>[];
      s.changes.listen(changes.add);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(waits.where((d) => d == const Duration(seconds: 20)), isNotEmpty);
      expect(s.currency, 'GBP');
      expect(s.state.source, 'ip');
      s.dispose();
    });
  });

  group('recheck', () {
    test('is skipped while the first load is still deciding', () async {
      final server = _Server([_ip('GBP')]);
      final s = service(server);
      final result = await s.recheck();
      expect(result.skipped, isTrue);
      expect(server.calls, 0);
      s.dispose();
    });

    test('a changed answer updates the currency and tells listeners once', () async {
      final server = _Server([_ip('USD'), _ip('GBP')]);
      final s = service(server);
      await s.ensureLoaded();
      final changes = <CurrencyChange>[];
      s.changes.listen(changes.add);
      clock = clock.add(const Duration(minutes: 5));

      final result = await s.recheck();
      await Future<void>.delayed(Duration.zero);

      expect(result.changed, isTrue);
      expect(result.currency, 'GBP');
      expect(s.currency, 'GBP');
      expect(changes, hasLength(1));
      expect(changes.single.from, 'USD');
      expect(changes.single.to, 'GBP');
      s.dispose();
    });

    test('the same answer changes nothing and says nothing', () async {
      final server = _Server([_ip('GBP'), _ip('GBP')]);
      final s = service(server);
      await s.ensureLoaded();
      final changes = <CurrencyChange>[];
      s.changes.listen(changes.add);
      clock = clock.add(const Duration(minutes: 5));

      final result = await s.recheck();
      await Future<void>.delayed(Duration.zero);

      expect(result.changed, isFalse);
      expect(result.ok, isTrue);
      expect(changes, isEmpty);
      s.dispose();
    });

    test('is limited to once every 20 seconds, unless forced', () async {
      final server = _Server([_ip('GBP'), _ip('GBP'), _ip('GBP'), _ip('GBP')]);
      final s = service(server);
      await s.ensureLoaded(); // asking counts as a check
      expect(server.calls, 1);

      clock = clock.add(const Duration(seconds: 10));
      expect((await s.recheck()).skipped, isTrue);
      expect(server.calls, 1);

      clock = clock.add(const Duration(seconds: 11)); // 21 s since the load
      expect((await s.recheck()).skipped, isFalse);
      expect(server.calls, 2);

      clock = clock.add(const Duration(seconds: 1));
      expect((await s.recheck()).skipped, isTrue);
      expect(server.calls, 2);

      expect((await s.recheck(force: true)).skipped, isFalse); // right before a payment
      expect(server.calls, 3);
      s.dispose();
    });

    test('a failed re-check changes nothing', () async {
      final server = _Server([_ip('GBP'), 'fail']);
      final s = service(server);
      await s.ensureLoaded();
      clock = clock.add(const Duration(minutes: 5));

      final result = await s.recheck(force: true);

      expect(result.changed, isFalse);
      expect(result.ok, isFalse);
      expect(s.currency, 'GBP');
      expect(s.state.loading, isFalse);
      s.dispose();
    });

    test('a server "error" answer in a re-check changes nothing', () async {
      final server = _Server([
        _ip('GBP'),
        {'currency': 'USD', 'country': '', 'source': 'error'},
      ]);
      final s = service(server);
      await s.ensureLoaded();

      final result = await s.recheck(force: true);

      expect(result.changed, isFalse);
      expect(s.currency, 'GBP');
      s.dispose();
    });

    test('two re-checks at once share one request', () async {
      final server = _Server([_ip('GBP'), _ip('GBP')]);
      final s = service(server);
      await s.ensureLoaded();

      await Future.wait([s.recheck(force: true), s.recheck(force: true)]);

      expect(server.calls, 2);
      s.dispose();
    });

    test('listeners (the screens) are notified when the currency changes', () async {
      final server = _Server([_ip('USD'), _ip('EUR')]);
      final s = service(server);
      await s.ensureLoaded();
      var notified = 0;
      s.addListener(() => notified++);

      await s.recheck(force: true);

      expect(notified, greaterThan(0));
      expect(s.currency, 'EUR');
      s.dispose();
    });
  });

  group('the real request', () {
    CurrencyService overHttp(Future<http.Response> Function(http.Request) h) =>
        CurrencyService(
          apiClient: ApiClient(
            client: MockClient(h),
            tokenStorage: const TokenStorageService(),
          ),
          wait: (_) async {},
          observeLifecycle: false,
        );

    test('asks GET /api/geo/currency and reads the currency', () async {
      Uri? uri;
      final s = overHttp((request) async {
        uri = request.url;
        return http.Response(jsonEncode(_ip('GBP')), 200);
      });

      await s.ensureLoaded();

      expect(uri?.path, '/api/geo/currency');
      expect(s.currency, 'GBP');
      s.dispose();
    });

    test('a 503 is retried, then the answer is used', () async {
      var calls = 0;
      final s = overHttp((_) async {
        calls++;
        return calls < 3
            ? http.Response(jsonEncode({'msg': 'Could not work out your currency'}), 503)
            : http.Response(jsonEncode(_ip('EUR')), 200);
      });

      await s.ensureLoaded();

      expect(calls, 3);
      expect(s.currency, 'EUR');
      s.dispose();
    });
  });

  group('PricingService (GET /api/pricing)', () {
    PricingService overHttp(Future<http.Response> Function(http.Request) h) =>
        PricingService(
          apiClient: ApiClient(
            client: MockClient(h),
            tokenStorage: const TokenStorageService(),
          ),
        );

    test('reads every category keyed by its slug, with the EUR / GBP prices', () async {
      Uri? uri;
      final s = overHttp((request) async {
        uri = request.url;
        return http.Response(
          jsonEncode({
            'general': {'price': 59, 'label': 'General', 'currency': 'USD', 'priceEur': 55, 'priceGbp': 49},
            'mental': {'price': 39, 'label': 'Mental', 'currency': 'USD', 'priceEur': null, 'priceGbp': null},
          }),
          200,
        );
      });
      expect(s.prices, isNull);

      await s.ensureLoaded();

      expect(uri?.path, '/api/pricing');
      expect(s.prices!.keys, ['general', 'mental']);
      expect(s.prices!['general']!.price, 59);
      expect(s.prices!['general']!.priceEur, 55);
      expect(s.prices!['general']!.priceGbp, 49);
      expect(s.prices!['mental']!.priceGbp, isNull);
      expect(s.loading, isFalse);
    });

    test('a failure leaves the table empty (never a made-up price)', () async {
      final s = overHttp((_) async => http.Response('{}', 500));

      await s.ensureLoaded();

      expect(s.prices, isNull);
      expect(s.loading, isFalse);
    });

    test('a failed refresh keeps the table that is already there', () async {
      var fail = false;
      final s = overHttp((_) async {
        if (fail) return http.Response('{}', 500);
        return http.Response(jsonEncode({'general': {'price': 59, 'label': 'General'}}), 200);
      });
      await s.ensureLoaded();
      fail = true;

      await s.refresh();

      expect(s.prices!['general']!.price, 59);
    });
  });
}

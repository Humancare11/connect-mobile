import 'dart:async';

import 'package:flutter/widgets.dart';

import '../utils/money.dart';
import 'api_client.dart';

/// The currency the customer is priced in right now.
class CurrencyState {
  const CurrencyState({
    this.currency = kDefaultCurrency,
    this.loading = true,
    this.source = '',
  });

  /// USD, EUR or GBP.
  final String currency;

  /// True until the server has answered (or every retry has failed): price
  /// slots show a placeholder, never "$" first and "£" a moment later.
  final bool loading;

  /// `ip`, `default`, `disabled`, `app-gate` (the server's own words), or
  /// `error` when it could not be reached at all.
  final String source;

  CurrencyState copyWith({String? currency, bool? loading, String? source}) =>
      CurrencyState(
        currency: currency ?? this.currency,
        loading: loading ?? this.loading,
        source: source ?? this.source,
      );
}

/// Told once when a re-check finds the customer now priced in another currency.
class CurrencyChange {
  const CurrencyChange({required this.from, required this.to});
  final String from;
  final String to;
}

/// What [CurrencyService.recheck] found. It never throws.
class RecheckResult {
  const RecheckResult({
    this.changed = false,
    this.currency = kDefaultCurrency,
    this.ok = false,
    this.skipped = false,
  });

  final bool changed;
  final String currency;
  final bool ok;
  final bool skipped;
}

/// The customer's pricing currency, decided by the SERVER from the IP the
/// request comes from (`GET /api/geo/currency`); the profile country plays no
/// part and the app never converts an amount. A port of the web app's
/// `currencyLoader.js` + `CurrencyContext.jsx`:
///
///  * one answer for the whole session, shown at once on every screen;
///  * a failed request (network, 5xx, 429) is retried with backoff
///    (0.4 s, 1 s, 2.5 s, 5 s, then every 20 s in the background); while that
///    goes on `loading` stays true;
///  * the server's own `source: "error"` is not an answer and is retried too;
///  * [recheck] asks again during the session (a new booking screen, the app
///    coming back to the front: at most every 20 s), and without that limit
///    right before a payment is created. If the answer changed, listeners are
///    told once on [changes] and every price follows it. A failed re-check
///    changes nothing.
///
/// The request carries the app's `X-Client-Platform` / `X-App-Version`
/// headers (see `AppBuildInfo`), which is how the server's app gate decides
/// whether this build may be priced in EUR / GBP at all. Rupees are never
/// returned to this build, because it does not send `X-Client-Capabilities:
/// razorpay`.
class CurrencyService extends ChangeNotifier with WidgetsBindingObserver {
  CurrencyService({
    this.apiClient,
    Future<Map<String, dynamic>> Function()? fetchCurrency,
    Future<void> Function(Duration)? wait,
    DateTime Function()? now,
    this.delays = const [
      Duration(milliseconds: 400),
      Duration(seconds: 1),
      Duration(milliseconds: 2500),
      Duration(seconds: 5),
    ],
    this.backgroundRetry = const Duration(seconds: 20),
    this.maxBackgroundRetries = 30,
    this.recheckMinInterval = const Duration(seconds: 20),
    this.observeLifecycle = true,
  }) : _fetch = fetchCurrency,
       _wait = wait ?? Future<void>.delayed,
       _now = now ?? DateTime.now;

  /// The shared instance the booking screens use. Replaceable in tests.
  static CurrencyService instance = CurrencyService();

  /// The client used to ask the server (the default one when null).
  final ApiClient? apiClient;
  final Future<Map<String, dynamic>> Function()? _fetch;
  final Future<void> Function(Duration) _wait;
  final DateTime Function() _now;

  final List<Duration> delays;
  final Duration backgroundRetry;
  final int maxBackgroundRetries;
  final Duration recheckMinInterval;
  final bool observeLifecycle;

  final StreamController<CurrencyChange> _changes =
      StreamController<CurrencyChange>.broadcast();

  CurrencyState _state = const CurrencyState();
  String? _lastGood;
  int _sequence = 0;
  bool _disposed = false;
  bool _observing = false;
  Future<void>? _loadFuture;
  Future<RecheckResult>? _recheckInFlight;
  DateTime? _lastRecheckAt;

  CurrencyState get state => _state;
  String get currency => _state.currency;
  bool get loading => _state.loading;

  /// Fires once each time a re-check finds a different currency.
  Stream<CurrencyChange> get changes => _changes.stream;

  void _set(CurrencyState next) {
    _state = next;
    if (!_disposed) notifyListeners();
  }

  /// Starts loading the currency the first time it is called; the same future
  /// afterwards. Completes when the server has answered, or when the first
  /// round of retries has failed (the retries then carry on quietly).
  Future<void> ensureLoaded() {
    _attachLifecycle();
    return _loadFuture ??= _load();
  }

  void _attachLifecycle() {
    if (!observeLifecycle || _observing) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observing = true;
    } catch (_) {
      // No binding (a plain unit test): the app-resume re-check just is not wired.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(recheck());
  }

  Future<Map<String, dynamic>> _ask() async {
    final Map<String, dynamic> data;
    final fetch = _fetch;
    if (fetch != null) {
      data = await fetch();
    } else {
      final result = await (apiClient ?? ApiClient()).get(
        '/geo/currency',
        null,
        true,
      );
      if (!result.success) {
        throw StateError('currency request failed (${result.statusCode})');
      }
      data = result.data ?? result.raw;
    }
    // The server answers source "error" when its own location lookup failed:
    // that is not an answer about this customer, so it is retried like a
    // failed request instead of being shown.
    if (data['source']?.toString() == 'error') {
      throw StateError('the server could not place the customer');
    }
    return data;
  }

  void _accept(Map<String, dynamic> data) {
    final currency = normalizeCurrency(data['currency']?.toString());
    _lastGood = currency;
    _set(
      CurrencyState(
        currency: currency,
        loading: false,
        source: data['source']?.toString() ?? '',
      ),
    );
  }

  Future<void> _load() async {
    final mine = ++_sequence;
    _lastRecheckAt = _now(); // asking now counts as a check
    _set(_state.copyWith(loading: true));

    for (var attempt = 0; attempt <= delays.length; attempt++) {
      if (attempt > 0) await _wait(delays[attempt - 1]);
      if (_disposed || mine != _sequence) return;
      try {
        _accept(await _ask());
        return;
      } catch (_) {
        // try again after the next delay
      }
    }

    // Every try failed. Show what was last known (or USD), say so, and keep
    // trying quietly.
    debugPrint(
      '[currency] could not load the currency after ${delays.length + 1} '
      'tries; showing ${_lastGood ?? kDefaultCurrency} until it can',
    );
    _set(
      CurrencyState(
        currency: _lastGood ?? kDefaultCurrency,
        loading: false,
        source: 'error',
      ),
    );
    unawaited(_retryInBackground(mine));
  }

  Future<void> _retryInBackground(int mine) async {
    for (var retry = 0; retry < maxBackgroundRetries; retry++) {
      await _wait(backgroundRetry);
      if (_disposed || mine != _sequence) return;
      try {
        final data = await _ask();
        final before = _state.currency;
        _accept(data);
        final after = _state.currency;
        if (before != after && !_changes.isClosed) {
          _changes.add(CurrencyChange(from: before, to: after));
        }
        return;
      } catch (_) {
        // keep trying
      }
    }
  }

  /// Asks the server again where the customer is now. Never throws and never
  /// touches the state unless the server gave a real, different answer.
  /// [force] skips the 20 s limit (used right before a payment is created).
  Future<RecheckResult> recheck({bool force = false}) {
    RecheckResult unchanged({bool skipped = false}) => RecheckResult(
      currency: _state.currency,
      skipped: skipped,
    );

    if (_disposed) return Future.value(unchanged(skipped: true));
    // The first load is still deciding the currency: its answer is the fresh one.
    if (_state.loading) return Future.value(unchanged(skipped: true));
    final running = _recheckInFlight;
    if (running != null) return running;
    final last = _lastRecheckAt;
    if (!force && last != null && _now().difference(last) < recheckMinInterval) {
      return Future.value(unchanged(skipped: true));
    }
    _lastRecheckAt = _now();
    final mine = _sequence;

    final future = () async {
      try {
        final Map<String, dynamic> data;
        try {
          data = await _ask();
        } catch (_) {
          return unchanged(); // failed: keep what the session shows
        }
        if (_disposed || mine != _sequence) return unchanged(skipped: true);
        final fresh = normalizeCurrency(data['currency']?.toString());
        // Whatever the server answers is what it will charge in right now, so
        // the screen follows it.
        if (fresh == _state.currency) {
          final source = data['source']?.toString() ?? '';
          if (source != _state.source) _set(_state.copyWith(source: source));
          return RecheckResult(currency: fresh, ok: true);
        }
        final from = _state.currency;
        _accept(data);
        if (!_changes.isClosed) {
          _changes.add(CurrencyChange(from: from, to: fresh));
        }
        return RecheckResult(changed: true, currency: fresh, ok: true);
      } finally {
        _recheckInFlight = null;
      }
    }();
    _recheckInFlight = future;
    return future;
  }

  @override
  void dispose() {
    _disposed = true;
    _sequence++;
    if (_observing) {
      try {
        WidgetsBinding.instance.removeObserver(this);
      } catch (_) {}
      _observing = false;
    }
    _changes.close();
    super.dispose();
  }
}

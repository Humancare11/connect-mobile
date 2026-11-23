import 'package:flutter/foundation.dart';

import '../utils/json_helpers.dart';
import 'api_client.dart';

/// One category's entry of the public price table (`GET /api/pricing`):
/// `price` is always the USD price; `priceEur` / `priceGbp` are `null` until
/// they have been set for that category.
class PricingRecord {
  const PricingRecord({
    required this.price,
    this.label = '',
    this.priceEur,
    this.priceGbp,
  });

  factory PricingRecord.fromJson(Map<String, dynamic> json) {
    return PricingRecord(
      price: _number(json['price']),
      label: (json['label'] ?? '').toString(),
      priceEur: _number(json['priceEur']),
      priceGbp: _number(json['priceGbp']),
    );
  }

  final num? price;
  final String label;
  final num? priceEur;
  final num? priceGbp;

  static num? _number(Object? value) {
    if (value is num) return value;
    return num.tryParse(value?.toString() ?? '');
  }
}

/// The public price table, keyed by the category's `pricingSlug` (the web's
/// `PricingContext`). It carries every currency's price; which one is shown is
/// decided by the customer's currency (see `price_resolver.dart`).
class PricingService extends ChangeNotifier {
  PricingService({ApiClient? apiClient}) : _apiClient = apiClient ?? ApiClient();

  /// The shared instance the booking screens use. Replaceable in tests.
  static PricingService instance = PricingService();

  final ApiClient _apiClient;

  Map<String, PricingRecord>? _prices;
  bool _loading = false;
  Future<void>? _inFlight;

  /// `null` until the table has loaded (or when it could not be loaded).
  Map<String, PricingRecord>? get prices => _prices;

  /// True only while the first load is still running with nothing to show.
  bool get loading => _loading && _prices == null;

  /// Loads the table if it has never loaded; a refresh when [force] is set.
  Future<void> ensureLoaded({bool force = false}) {
    if (_prices != null && !force) return Future<void>.value();
    return refresh();
  }

  /// Fetches the table again. Never throws: a failed refresh keeps what is
  /// already there (and leaves `prices` null when nothing ever loaded).
  Future<void> refresh() {
    final running = _inFlight;
    if (running != null) return running;
    if (_prices == null) {
      _loading = true;
      notifyListeners();
    }
    final future = _load().whenComplete(() {
      _inFlight = null;
      _loading = false;
      notifyListeners();
    });
    _inFlight = future;
    return future;
  }

  Future<void> _load() async {
    final result = await _apiClient.get('/pricing', null, true);
    if (!result.success) return;
    final body = result.data ?? result.raw;
    final table = <String, PricingRecord>{};
    for (final entry in body.entries) {
      final record = asMap(entry.value);
      if (record.isEmpty) continue;
      table[entry.key] = PricingRecord.fromJson(record);
    }
    _prices = table;
  }
}

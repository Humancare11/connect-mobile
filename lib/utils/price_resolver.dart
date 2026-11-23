import '../services/pricing_service.dart';
import 'money.dart';

/// What a price slot shows. A port of the web app's `currencyDisplay.js`
/// (`resolveCategoryPrice`, `priceRecordFor`, `selectionPriceInfo`), so the same
/// selection gets the same price, in the same currency, with the same fallback.
///
/// The result is for DISPLAY only. The server prices the payment itself from
/// what is being booked and where the request comes from; the app never tells
/// it an amount or a currency.
class PriceInfo {
  const PriceInfo({
    this.amount,
    this.currency = kDefaultCurrency,
    this.loading = false,
    this.unavailable = false,
  });

  /// The price in [currency], or null while loading / when there is none.
  final double? amount;
  final String currency;

  /// The currency or the price table is still loading: show a placeholder,
  /// never "$" first and "£" a moment later.
  final bool loading;

  /// There is no usable price at all ("Price unavailable"; never a made-up one).
  final bool unavailable;

  bool get ready => !loading && !unavailable && (amount ?? 0) > 0;

  @override
  bool operator ==(Object other) =>
      other is PriceInfo &&
      other.amount == amount &&
      other.currency == currency &&
      other.loading == loading &&
      other.unavailable == unavailable;

  @override
  int get hashCode => Object.hash(amount, currency, loading, unavailable);
}

double? _positive(Object? value) {
  final n = value is num ? value.toDouble() : double.tryParse('${value ?? ''}');
  return n != null && n.isFinite && n > 0 ? n : null;
}

/// One category's price in [currency], from its price-table entry. A EUR / GBP
/// price that is not set falls back to the USD price, labelled USD: the same
/// rule the server charges by, so what is shown is what is charged. Null when
/// there is no usable price at all.
PriceInfo? resolveCategoryPrice(PricingRecord? record, String? currency) {
  if (record == null) return null;
  final wanted = normalizeCurrency(currency);
  if (wanted == 'EUR') {
    final eur = _positive(record.priceEur);
    if (eur != null) return PriceInfo(amount: eur, currency: 'EUR');
  }
  if (wanted == 'GBP') {
    final gbp = _positive(record.priceGbp);
    if (gbp != null) return PriceInfo(amount: gbp, currency: 'GBP');
  }
  final usd = _positive(record.price);
  return usd != null ? PriceInfo(amount: usd, currency: 'USD') : null;
}

/// The price-table entry of a selection's category. The table is keyed by the
/// category's pricing slug; the category id is tried next, and last the
/// category name (each entry also carries its label).
PricingRecord? priceRecordFor(
  Map<String, dynamic>? selection,
  Map<String, PricingRecord>? prices,
) {
  if (prices == null || selection == null) return null;
  for (final key in [selection['pricingSlug'], selection['catId']]) {
    final text = key?.toString().trim() ?? '';
    if (text.isNotEmpty && prices[text] != null) return prices[text];
  }
  final label = (selection['catLabel']?.toString() ?? '').trim().toLowerCase();
  if (label.isEmpty) return null;
  for (final record in prices.values) {
    if (record.label.trim().toLowerCase() == label) return record;
  }
  return null;
}

/// The price of a booking selection in the customer's currency.
///
/// `selection['cost']` is the USD price the booking page already loaded.
/// A service booking is priced from the service's own record (`priceEur`,
/// `priceGbp` carried in the selection); a category booking from the price
/// table, found through `pricingSlug`.
PriceInfo selectionPriceInfo({
  required Map<String, dynamic>? selection,
  required Map<String, PricingRecord>? prices,
  required String? currency,
  bool currencyLoading = false,
  bool pricesLoading = false,
}) {
  final usdCost = _positive(selection?['cost']);
  final wanted = normalizeCurrency(currency);

  if (selection?['bookingType']?.toString() == 'service') {
    if (currencyLoading) return const PriceInfo(loading: true);
    if (wanted != 'USD') {
      final native = resolveCategoryPrice(
        PricingRecord(
          price: usdCost,
          priceEur: _positive(selection?['priceEur']),
          priceGbp: _positive(selection?['priceGbp']),
        ),
        wanted,
      );
      if (native != null && native.currency == wanted) return native;
    }
    return usdCost != null
        ? PriceInfo(amount: usdCost, currency: 'USD')
        : const PriceInfo(unavailable: true);
  }

  if (currencyLoading) return const PriceInfo(loading: true);
  if (wanted == 'USD') {
    // Exactly today's behaviour: the price the page already loaded, else the
    // price table's USD price.
    final fromTable = prices != null
        ? resolveCategoryPrice(priceRecordFor(selection, prices), 'USD')
        : null;
    final amount = usdCost ?? fromTable?.amount;
    return amount != null
        ? PriceInfo(amount: amount, currency: 'USD')
        : const PriceInfo(unavailable: true);
  }
  if (pricesLoading && prices == null) {
    return PriceInfo(currency: wanted, loading: true);
  }
  // The price table could not be loaded at all (not "this category has no
  // price in it"): the price in the customer's currency is unknown, and showing
  // the USD price instead would make the same page read $ and £ depending on a
  // failed request.
  if (prices == null) return PriceInfo(currency: wanted, unavailable: true);
  final info = resolveCategoryPrice(priceRecordFor(selection, prices), wanted);
  if (info != null) return info;
  // No price-table entry for this category: the USD price the page loaded,
  // labelled USD (never converted).
  return usdCost != null
      ? PriceInfo(amount: usdCost, currency: 'USD')
      : const PriceInfo(unavailable: true);
}

/// Result of comparing the Stripe intent the server created with the price on
/// screen.
enum ChargeCheck { ok, currencyChanged, amountChanged }

/// The server decides what is charged. Before the payment sheet opens:
///  * a different CURRENCY than the one on screen means the customer's location
///    changed (the web does the same): nothing is paid, the screen is brought up
///    to date;
///  * the same currency but a different AMOUNT is refused too (stricter than
///    the web: the payment sheet opens straight away here, with no review step).
ChargeCheck checkCharge({
  required int intentAmountCents,
  required String intentCurrency,
  required double shownAmount,
  required String shownCurrency,
}) {
  if (intentCurrency.trim().toUpperCase() != shownCurrency.trim().toUpperCase()) {
    return ChargeCheck.currencyChanged;
  }
  if (intentAmountCents != (shownAmount * 100).round()) {
    return ChargeCheck.amountChanged;
  }
  return ChargeCheck.ok;
}

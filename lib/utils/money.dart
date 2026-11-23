import 'package:intl/intl.dart';

/// Showing prices in the customer's currency. Pure functions, no network.
///
/// A port of the web app's `frontend/src/utils/currencyDisplay.js`, so the same
/// amount reads the same on both. The server decides the currency (see
/// `CurrencyService`); the app only displays it and never converts an amount.
///
/// Phase 1 prices in USD, EUR and GBP. INR (Razorpay) is not supported by the
/// app yet: the backend keeps an app that cannot pay rupees on USD, and any
/// other code is treated as USD here.

const String kDefaultCurrency = 'USD';
const List<String> kAppCurrencies = ['USD', 'EUR', 'GBP'];

const Map<String, String> _symbols = {
  'USD': r'$',
  'EUR': '€',
  'GBP': '£',
  'INR': '₹',
};

/// USD / EUR / GBP in upper case; anything else (including INR, which this
/// build cannot pay) is USD.
String normalizeCurrency(String? value) {
  final code = (value ?? '').trim().toUpperCase();
  return kAppCurrencies.contains(code) ? code : kDefaultCurrency;
}

/// "$", "€" or "£".
String currencySymbol(String? currency) => _symbols[normalizeCurrency(currency)]!;

/// The notice shown when the customer's location changes during a session and
/// the currency follows it (same text as the web).
String currencyChangeNotice(String? currency) {
  final code = normalizeCurrency(currency);
  return 'Prices updated to your current location (${currencySymbol(code)} $code)';
}

/// Symbol first: $30, €30, £30. A whole amount has no decimals; a fractional
/// one always has two ($29.50, not $29.5). Thousands are grouped: $1,234.50.
/// Empty when the amount is not a finite number, so a missing price never
/// shows as "$NaN".
String formatPrice(num? amount, [String? currency = kDefaultCurrency]) {
  if (amount == null) return '';
  final value = amount.toDouble();
  if (!value.isFinite) return '';
  final whole = (value % 1).abs() < 1e-9;
  final pattern = whole ? '#,##0' : '#,##0.00';
  return '${currencySymbol(currency)}${NumberFormat(pattern, 'en_US').format(value)}';
}

/// An amount that was actually charged, as the Payment History shows it
/// ($59.00, €59.00, £55.00): always two decimals, like the web's
/// `Intl.NumberFormat("en-US", { style: "currency" })`. A currency this app has
/// no symbol for is shown as "CODE 59.00".
String formatCharge(num amount, String? currency) {
  final code = (currency ?? '').trim().toUpperCase();
  final digits = NumberFormat('#,##0.00', 'en_US').format(amount.toDouble());
  final symbol = _symbols[code];
  return symbol != null ? '$symbol$digits' : '$code $digits';
}

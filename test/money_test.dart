import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/models/payment_model.dart';
import 'package:humancare_connect/utils/money.dart';

void main() {
  group('formatPrice (same as the web formatPrice)', () {
    test('a whole amount has no decimals, symbol first', () {
      expect(formatPrice(59, 'USD'), r'$59');
      expect(formatPrice(59, 'EUR'), '€59');
      expect(formatPrice(55, 'GBP'), '£55');
      expect(formatPrice(30.0, 'GBP'), '£30');
    });

    test('a fractional amount always has two decimals', () {
      expect(formatPrice(29.5, 'USD'), r'$29.50');
      expect(formatPrice(1234.5, 'USD'), r'$1,234.50');
      expect(formatPrice(1234.5, 'EUR'), '€1,234.50');
      expect(formatPrice(1234.5, 'GBP'), '£1,234.50');
      expect(formatPrice(0.99, 'GBP'), '£0.99');
    });

    test('thousands are grouped', () {
      expect(formatPrice(1234, 'USD'), r'$1,234');
      expect(formatPrice(1000000, 'GBP'), '£1,000,000');
    });

    test('the currency defaults to USD and is case-insensitive', () {
      expect(formatPrice(59), r'$59');
      expect(formatPrice(55, 'gbp'), '£55');
    });

    test('a missing or broken amount is empty, never "NaN"', () {
      expect(formatPrice(null, 'USD'), '');
      expect(formatPrice(double.nan, 'USD'), '');
      expect(formatPrice(double.infinity, 'GBP'), '');
    });

    test('rupees: ₹ with Indian digit grouping, like the web (en-IN)', () {
      expect(formatPrice(499, 'INR'), '₹499');
      expect(formatPrice(4999, 'INR'), '₹4,999');
      expect(formatPrice(100000, 'INR'), '₹1,00,000');
      expect(formatPrice(1234.5, 'INR'), '₹1,234.50');
      expect(formatPrice(1234567.25, 'INR'), '₹12,34,567.25');
      expect(formatPrice(499, 'inr'), '₹499');
    });

    test('other currencies keep the western grouping', () {
      expect(formatPrice(1000000, 'USD'), r'$1,000,000');
      expect(formatPrice(1000000, 'EUR'), '€1,000,000');
    });
  });

  group('currency helpers', () {
    test('normalizeCurrency keeps USD / EUR / GBP / INR, everything else is USD', () {
      expect(normalizeCurrency('inr'), 'INR');
      expect(normalizeCurrency('gbp'), 'GBP');
      expect(normalizeCurrency(' eur '), 'EUR');
      expect(normalizeCurrency('USD'), 'USD');
      expect(normalizeCurrency(null), 'USD');
      expect(normalizeCurrency(''), 'USD');
      expect(normalizeCurrency('AUD'), 'USD');
    });

    test('the "prices updated" notice has the same text as the web', () {
      expect(
        currencyChangeNotice('GBP'),
        'Prices updated to your current location (£ GBP)',
      );
      expect(
        currencyChangeNotice('EUR'),
        'Prices updated to your current location (€ EUR)',
      );
      expect(
        currencyChangeNotice('USD'),
        r'Prices updated to your current location ($ USD)',
      );
      expect(
        currencyChangeNotice('INR'),
        'Prices updated to your current location (₹ INR)',
      );
    });
  });

  group('formatCharge (Payment History, the web Intl currency format)', () {
    test('always two decimals, symbol first', () {
      expect(formatCharge(59, 'usd'), r'$59.00');
      expect(formatCharge(59, 'eur'), '€59.00');
      expect(formatCharge(55, 'gbp'), '£55.00');
      expect(formatCharge(1234.5, 'USD'), r'$1,234.50');
    });

    test('a currency without a known symbol is shown by its code', () {
      expect(formatCharge(10, 'aud'), 'AUD 10.00');
    });

    test('rupees of an earlier web payment still read as rupees', () {
      expect(formatCharge(4999, 'inr'), '₹4,999.00');
    });

    test('PaymentRecord.amountDisplay uses it', () {
      PaymentRecord record(int cents, String currency) => PaymentRecord.fromJson({
        '_id': 'p1',
        'amountCents': cents,
        'currency': currency,
        'gateway': 'stripe',
      });

      expect(record(5900, 'usd').amountDisplay, r'$59.00');
      expect(record(5900, 'eur').amountDisplay, '€59.00');
      expect(record(5500, 'gbp').amountDisplay, '£55.00');
    });
  });
}

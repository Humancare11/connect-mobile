import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/models/appointment_tree_model.dart';
import 'package:humancare_connect/models/service_model.dart';
import 'package:humancare_connect/services/pricing_service.dart';
import 'package:humancare_connect/utils/price_resolver.dart';

const _general = PricingRecord(
  price: 59,
  label: 'General & Everyday Care',
  priceEur: 55,
  priceGbp: 49,
  priceInr: 4999,
);
const _usdOnly = PricingRecord(price: 39, label: 'Mental Health');

final _prices = <String, PricingRecord>{
  'general': _general,
  'mental': _usdOnly,
};

Map<String, dynamic> _selection({
  String slug = 'general',
  Object? cost = 59,
  String? catId = 'mongo-id-1',
  String catLabel = 'General & Everyday Care',
}) => {
  'pricingSlug': slug,
  'catId': catId,
  'catLabel': catLabel,
  'cost': cost,
};

PriceInfo _info(
  Map<String, dynamic> selection,
  String currency, {
  Map<String, PricingRecord>? prices,
  bool currencyLoading = false,
  bool pricesLoading = false,
  bool noPrices = false,
}) => selectionPriceInfo(
  selection: selection,
  prices: noPrices ? null : (prices ?? _prices),
  currency: currency,
  currencyLoading: currencyLoading,
  pricesLoading: pricesLoading,
);

void main() {
  group('resolveCategoryPrice', () {
    test('each currency reads its own price field', () {
      expect(resolveCategoryPrice(_general, 'USD'),
          const PriceInfo(amount: 59, currency: 'USD'));
      expect(resolveCategoryPrice(_general, 'EUR'),
          const PriceInfo(amount: 55, currency: 'EUR'));
      expect(resolveCategoryPrice(_general, 'GBP'),
          const PriceInfo(amount: 49, currency: 'GBP'));
    });

    test('a EUR / GBP price that is not set falls back to USD, labelled USD', () {
      expect(resolveCategoryPrice(_usdOnly, 'GBP'),
          const PriceInfo(amount: 39, currency: 'USD'));
      expect(resolveCategoryPrice(_usdOnly, 'EUR'),
          const PriceInfo(amount: 39, currency: 'USD'));
      expect(
        resolveCategoryPrice(const PricingRecord(price: 39, priceGbp: 0), 'GBP'),
        const PriceInfo(amount: 39, currency: 'USD'),
      );
    });

    test('rupees read the INR price', () {
      expect(resolveCategoryPrice(_general, 'INR'),
          const PriceInfo(amount: 4999, currency: 'INR'));
    });

    test('a category with no INR price shows its USD price, labelled USD', () {
      expect(resolveCategoryPrice(_usdOnly, 'INR'),
          const PriceInfo(amount: 39, currency: 'USD'));
      expect(
        resolveCategoryPrice(const PricingRecord(price: 39, priceInr: 0), 'INR'),
        const PriceInfo(amount: 39, currency: 'USD'),
      );
    });

    test('no usable price at all is null', () {
      expect(resolveCategoryPrice(null, 'USD'), isNull);
      expect(resolveCategoryPrice(const PricingRecord(price: 0), 'USD'), isNull);
    });
  });

  group('priceRecordFor', () {
    test('the pricing slug first, then the category id, then the label', () {
      expect(priceRecordFor(_selection(), _prices), same(_general));
      expect(
        priceRecordFor({'pricingSlug': '', 'catId': 'mental'}, _prices),
        same(_usdOnly),
      );
      expect(
        priceRecordFor({'catLabel': ' mental health '}, _prices),
        same(_usdOnly),
      );
      expect(priceRecordFor({'catLabel': 'Unknown'}, _prices), isNull);
      expect(priceRecordFor(_selection(), null), isNull);
    });
  });

  group('selectionPriceInfo: a category booking', () {
    test('USD is the price the page already loaded', () {
      expect(_info(_selection(cost: 61), 'USD'),
          const PriceInfo(amount: 61, currency: 'USD'));
    });

    test('USD still works when the price table has not loaded', () {
      expect(_info(_selection(), 'USD', noPrices: true),
          const PriceInfo(amount: 59, currency: 'USD'));
    });

    test('GBP, EUR and INR come from the price table', () {
      expect(_info(_selection(), 'GBP'),
          const PriceInfo(amount: 49, currency: 'GBP'));
      expect(_info(_selection(), 'EUR'),
          const PriceInfo(amount: 55, currency: 'EUR'));
      expect(_info(_selection(), 'INR'),
          const PriceInfo(amount: 4999, currency: 'INR'));
    });

    test('a price table that could not load is "unavailable" for INR too', () {
      expect(_info(_selection(), 'INR', noPrices: true).unavailable, isTrue);
    });

    test('a category with no GBP price shows the USD price, labelled USD', () {
      expect(
        _info(_selection(slug: 'mental', cost: 39, catLabel: 'Mental Health'), 'GBP'),
        const PriceInfo(amount: 39, currency: 'USD'),
      );
    });

    test('a category missing from the table shows its USD price', () {
      expect(
        _info(_selection(slug: 'new-cat', catId: null, catLabel: 'New', cost: 20), 'GBP'),
        const PriceInfo(amount: 20, currency: 'USD'),
      );
    });

    test('loading: the currency still loading, or the table for a foreign currency', () {
      expect(_info(_selection(), 'USD', currencyLoading: true).loading, isTrue);
      expect(
        _info(_selection(), 'GBP', noPrices: true, pricesLoading: true),
        const PriceInfo(currency: 'GBP', loading: true),
      );
    });

    test('a price table that could not load is "unavailable" for GBP, never USD', () {
      final info = _info(_selection(), 'GBP', noPrices: true);
      expect(info.unavailable, isTrue);
      expect(info.amount, isNull);
      expect(info.ready, isFalse);
    });

    test('no price at all is unavailable', () {
      expect(_info(_selection(cost: 0), 'USD', noPrices: true).unavailable, isTrue);
      expect(_info(_selection(cost: null, slug: 'x', catId: null, catLabel: 'Nope'), 'GBP').unavailable, isTrue);
    });

    test('a price string from the tree is read', () {
      expect(_info(_selection(cost: '59.5'), 'USD').amount, 59.5);
    });
  });

  group('selectionPriceInfo: a service booking', () {
    Map<String, dynamic> service({
      Object? eur = 45,
      Object? gbp = 40,
      Object? inr = 3999,
    }) => {
      'bookingType': 'service',
      'specName': 'Fit to fly',
      'cost': 50,
      'priceEur': eur,
      'priceGbp': gbp,
      'priceInr': inr,
    };

    test('is priced from the service record in the customer currency', () {
      expect(_info(service(), 'GBP'), const PriceInfo(amount: 40, currency: 'GBP'));
      expect(_info(service(), 'EUR'), const PriceInfo(amount: 45, currency: 'EUR'));
      expect(_info(service(), 'USD'), const PriceInfo(amount: 50, currency: 'USD'));
    });

    test('rupees come from the service own INR price', () {
      expect(_info(service(), 'INR'),
          const PriceInfo(amount: 3999, currency: 'INR'));
      expect(_info(service(inr: null), 'INR'),
          const PriceInfo(amount: 50, currency: 'USD'));
    });

    test('a missing GBP price falls back to USD, labelled USD', () {
      expect(_info(service(gbp: null), 'GBP'),
          const PriceInfo(amount: 50, currency: 'USD'));
    });

    test('does not depend on the category price table', () {
      expect(_info(service(), 'GBP', noPrices: true),
          const PriceInfo(amount: 40, currency: 'GBP'));
    });

    test('loading while the currency is loading', () {
      expect(_info(service(), 'USD', currencyLoading: true).loading, isTrue);
    });
  });

  group('checkCharge (the intent the server created vs the price on screen)', () {
    test('same currency and amount is fine', () {
      expect(
        checkCharge(
          intentAmountCents: 4900,
          intentCurrency: 'gbp',
          shownAmount: 49,
          shownCurrency: 'GBP',
        ),
        ChargeCheck.ok,
      );
    });

    test('another currency means the location changed', () {
      expect(
        checkCharge(
          intentAmountCents: 5900,
          intentCurrency: 'usd',
          shownAmount: 49,
          shownCurrency: 'GBP',
        ),
        ChargeCheck.currencyChanged,
      );
    });

    test('the same currency with another amount is refused (stricter than the web)', () {
      expect(
        checkCharge(
          intentAmountCents: 5000,
          intentCurrency: 'gbp',
          shownAmount: 49,
          shownCurrency: 'GBP',
        ),
        ChargeCheck.amountChanged,
      );
    });

    test('a fractional amount is compared in minor units', () {
      expect(
        checkCharge(
          intentAmountCents: 2950,
          intentCurrency: 'eur',
          shownAmount: 29.5,
          shownCurrency: 'EUR',
        ),
        ChargeCheck.ok,
      );
    });
  });

  group('the models carry what the resolver needs', () {
    test('the appointment tree keeps the pricing slug', () {
      final categories = parseAppointmentTree([
        {
          '_id': 'abc',
          'pricingSlug': 'general',
          'name': 'General & Everyday Care',
          'price': 59,
          'isActive': true,
          'specialties': [],
        },
      ]);
      expect(categories.single.pricingSlug, 'general');
      expect(categories.single.toUiMap()['pricingSlug'], 'general');
      expect(categories.single.toUiMap()['cost'], 59);
    });

    test('a service keeps its EUR / GBP prices', () {
      final services = parseServices([
        {'_id': 's1', 'name': 'Fit to fly', 'price': 50, 'priceEur': 45, 'priceGbp': '40', 'priceInr': 3999},
        {'_id': 's2', 'name': 'Sick note', 'price': 30},
      ]);
      expect(services[0].priceEur, 45);
      expect(services[0].priceGbp, 40);
      expect(services[0].priceInr, 3999);
      expect(services[1].priceEur, isNull);
      expect(services[1].priceGbp, isNull);
      expect(services[1].priceInr, isNull);
    });
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/models/api_result.dart';
import 'package:humancare_connect/services/backend_location_service.dart';
import 'package:humancare_connect/widgets/geo_phone_controller.dart';

/// Backend stand-in: fixed countries, per-ISO states, and optional gates so a
/// test can decide when (and whether) a states response arrives.
class FakeLocations extends BackendLocationService {
  FakeLocations({this.statesByIso = const {}, this.countriesFail = false});

  final Map<String, List<String>> statesByIso;
  final bool countriesFail;
  final Map<String, Completer<List<String>?>> gates = {};
  final List<String> statesRequests = [];

  static const countryList = [
    BackendCountry(name: 'India', isoCode: 'IN'),
    BackendCountry(name: 'United States', isoCode: 'US'),
    BackendCountry(name: 'Canada', isoCode: 'CA'),
    BackendCountry(name: 'Russia', isoCode: 'RU'),
    BackendCountry(name: 'Kazakhstan', isoCode: 'KZ'),
    BackendCountry(name: 'Guam', isoCode: 'GU'),
    BackendCountry(name: 'Antarctica', isoCode: 'AQ'),
  ];

  @override
  Future<ApiResult<List<BackendCountry>>> countries() async {
    if (countriesFail) {
      return const ApiResult(success: false, message: 'down');
    }
    return const ApiResult(success: true, message: '', data: countryList);
  }

  @override
  Future<ApiResult<List<String>>> states(String country) async {
    statesRequests.add(country);
    final gate = gates[country];
    final list = gate != null ? await gate.future : statesByIso[country];
    if (list == null) return const ApiResult(success: false, message: 'down');
    return ApiResult(success: true, message: '', data: list);
  }
}

const _states = {
  'IN': ['Goa', 'Kerala'],
  'US': ['Alabama', 'Texas'],
  'CA': ['Ontario', 'Quebec'],
  'RU': ['Moscow'],
  'KZ': ['Almaty'],
  'GU': <String>[],
  'AQ': <String>[],
};

Future<GeoPhoneController> _ready({
  FakeLocations? fake,
  bool requireLocation = true,
  bool requireMobile = true,
  bool defaultToIndia = true,
}) async {
  final c = GeoPhoneController(
    locations: fake ?? FakeLocations(statesByIso: _states),
    requireLocation: requireLocation,
    requireMobile: requireMobile,
    defaultToIndia: defaultToIndia,
  );
  await c.init();
  return c;
}

BackendCountry _country(String name) =>
    FakeLocations.countryList.firstWhere((c) => c.name == name);

void main() {
  setUp(GeoPhoneController.clearCaches);

  group('defaults and loading', () {
    test(
      'starts as India / +91 and loads India states from the backend',
      () async {
        final fake = FakeLocations(statesByIso: _states);
        final c = await _ready(fake: fake);
        expect(c.countryName, 'India');
        expect(c.iso2, 'IN');
        expect(c.dialCode, '+91');
        expect(c.states, ['Goa', 'Kerala']);
        expect(c.statesStatus, LoadStatus.ready);
        // ISO2 is what is sent, never a name.
        expect(fake.statesRequests, ['IN']);
      },
    );

    test('a failed country list is reported, and India still works', () async {
      final c = await _ready(
        fake: FakeLocations(statesByIso: _states, countriesFail: true),
      );
      expect(c.countriesStatus, LoadStatus.error);
      expect(c.countryName, 'India');
      expect(c.statesStatus, LoadStatus.ready);
    });

    test(
      'states failure shows an error and blocks submit until retried',
      () async {
        final fake = FakeLocations(statesByIso: {}); // every states call fails
        final c = await _ready(fake: fake);
        expect(c.statesStatus, LoadStatus.error);
        expect(c.stateError, isNotNull);
        expect(c.stateError, contains('Retry'));
      },
    );

    test('states are cached per country for the session', () async {
      final fake = FakeLocations(statesByIso: _states);
      final c = await _ready(fake: fake);
      c.selectCountry(_country('United States'));
      await pumpEventQueue();
      c.selectCountry(_country('India'));
      await pumpEventQueue();
      expect(fake.statesRequests, [
        'IN',
        'US',
      ]); // India's second visit is cached
    });
  });

  group('Country → phone code', () {
    test(
      'picking a country sets the dial code and clears State and City',
      () async {
        final c = await _ready();
        c.selectState('Kerala');
        c.cityController.text = 'Kochi';
        c.selectCountry(_country('United States'));
        expect(c.countryName, 'United States');
        expect(c.dialCode, '+1');
        expect(c.dialIso, 'US');
        expect(c.state, '');
        expect(c.city, '');
        await pumpEventQueue();
        expect(c.states, ['Alabama', 'Texas']);
      },
    );

    test(
      'shared +1: Canada after the US keeps +1 but switches the flag to CA',
      () async {
        final c = await _ready();
        c.selectCountry(_country('United States'));
        c.selectCountry(_country('Canada'));
        expect(c.dialCode, '+1');
        expect(c.dialIso, 'CA');
        expect(c.iso2, 'CA');
      },
    );

    test(
      'a country with no dial code (Antarctica) leaves the code alone',
      () async {
        final c = await _ready();
        c.selectCountry(_country('Antarctica'));
        expect(c.countryName, 'Antarctica');
        expect(c.dialCode, '+91');
        expect(c.dialIso, 'IN');
      },
    );

    test('picking the same country again changes nothing', () async {
      final c = await _ready();
      c.selectState('Kerala');
      c.selectCountry(_country('India'));
      expect(c.state, 'Kerala');
    });
  });

  group('phone code → Country', () {
    test(
      'picking a dial code sets the country (by ISO2) and clears State/City',
      () async {
        final c = await _ready();
        c.selectState('Kerala');
        c.cityController.text = 'Kochi';
        c.selectDialIso('CA');
        expect(c.dialCode, '+1');
        expect(c.countryName, 'Canada');
        expect(c.iso2, 'CA');
        expect(c.state, '');
        expect(c.city, '');
      },
    );

    test('shared +7: Kazakhstan and Russia stay distinct', () async {
      final c = await _ready();
      c.selectDialIso('KZ');
      expect(c.countryName, 'Kazakhstan');
      c.selectDialIso('RU');
      expect(c.countryName, 'Russia');
      expect(c.dialCode, '+7');
    });

    test(
      'choosing the code of the current country keeps State and City',
      () async {
        final c = await _ready();
        c.selectState('Kerala');
        c.cityController.text = 'Kochi';
        c.selectDialIso('IN');
        expect(c.state, 'Kerala');
        expect(c.city, 'Kochi');
      },
    );

    test('an unknown ISO changes nothing', () async {
      final c = await _ready();
      c.selectDialIso('AQ');
      expect(c.dialCode, '+91');
      expect(c.countryName, 'India');
    });
  });

  group('states', () {
    test(
      'required when the country has states; message matches the web',
      () async {
        final c = await _ready();
        expect(c.stateError, 'Select your state / province');
        c.selectState('Kerala');
        expect(c.stateError, isNull);
      },
    );

    test(
      'a country with no states: "No states available", not required',
      () async {
        final c = await _ready();
        c.selectCountry(_country('Guam'));
        await pumpEventQueue();
        expect(c.noStatesAvailable, isTrue);
        expect(c.stateError, isNull);
        expect(c.countryError, isNull);
      },
    );

    test('loading blocks submit with a clear message', () async {
      final fake = FakeLocations(statesByIso: _states);
      fake.gates['US'] = Completer<List<String>?>();
      final c = await _ready(fake: fake);
      c.selectCountry(_country('United States'));
      expect(c.statesStatus, LoadStatus.loading);
      expect(c.stateError, isNotNull);
      fake.gates['US']!.complete(['Alabama']);
      await pumpEventQueue();
      expect(c.statesStatus, LoadStatus.ready);
    });

    test('a slow response for a country the user left is ignored', () async {
      final fake = FakeLocations(statesByIso: _states);
      fake.gates['US'] = Completer<List<String>?>();
      final c = await _ready(fake: fake);
      c.selectCountry(_country('United States')); // slow
      c.selectCountry(_country('Canada')); // fast
      await pumpEventQueue();
      expect(c.states, ['Ontario', 'Quebec']);
      fake.gates['US']!.complete(['Alabama', 'Texas']); // arrives late
      await pumpEventQueue();
      expect(c.states, ['Ontario', 'Quebec']);
      expect(c.iso2, 'CA');
    });

    test('Retry refetches after a failure', () async {
      final fake = FakeLocations(statesByIso: {});
      final c = await _ready(fake: fake);
      expect(c.statesStatus, LoadStatus.error);
      fake.statesByIso['IN'] = ['Goa'];
      await c.retryStates();
      expect(c.statesStatus, LoadStatus.ready);
      expect(c.states, ['Goa']);
    });

    test('Country is required and shows the web message', () async {
      final c = await _ready(defaultToIndia: false);
      expect(c.countryError, 'Select your country');
      expect(c.stateError, isNull); // nothing to choose a state in yet
    });

    test('optional location (profile) never errors', () async {
      final c = await _ready(requireLocation: false, defaultToIndia: false);
      expect(c.countryError, isNull);
      expect(c.stateError, isNull);
    });
  });

  group('phone number', () {
    TextEditingValue run(GeoPhoneController c, String text) => c.numberFormatter
        .formatEditUpdate(TextEditingValue.empty, TextEditingValue(text: text));

    test('India: pasted +91 number is trimmed to 10 digits', () async {
      final c = await _ready();
      expect(run(c, '+91 98765 43210').text, '9876543210');
      expect(run(c, '919876543210').text, '9876543210');
    });

    test('India: a leading 0 is stripped', () async {
      final c = await _ready();
      expect(run(c, '09876543210').text, '9876543210');
    });

    test('India: never more than 10 digits', () async {
      final c = await _ready();
      expect(run(c, '98765432101234').text, '9876543210');
    });

    test('other countries: digits only, up to 15', () async {
      final c = await _ready();
      c.selectCountry(_country('United States'));
      expect(run(c, '(415) 555-2671').text, '4155552671');
      expect(run(c, '1234567890123456789').text.length, 15);
      // The India rules no longer apply: a leading 0 is kept.
      expect(run(c, '0123').text, '0123');
    });

    test('validation uses the web rules', () async {
      final c = await _ready();
      expect(c.mobileError, 'Enter mobile number');
      c.numberController.text = '1234567890';
      expect(c.mobileError, contains('Indian mobile number'));
      c.numberController.text = '9876543210';
      expect(c.mobileError, isNull);
      expect(c.fullNumber, '+919876543210');

      c.selectCountry(_country('United States'));
      c.numberController.text = '4155552671';
      expect(c.mobileError, isNull);
      expect(c.fullNumber, '+14155552671');
      c.numberController.text = '12';
      expect(c.mobileError, 'Enter a valid mobile number with country code.');
    });
  });

  group('parseMobile', () {
    test('splits an Indian number', () {
      final p = parseMobile('+919876543210')!;
      expect([p.iso2, p.dial, p.digits], ['IN', '+91', '9876543210']);
    });

    test('longest code wins (+1671 is Guam, not the US)', () {
      expect(parseMobile('+16715551234')!.iso2, 'GU');
    });

    test(
      'a shared code goes to the stored country, else a sensible default',
      () {
        expect(parseMobile('+14165551234', preferIso: 'CA')!.iso2, 'CA');
        expect(parseMobile('+14165551234')!.iso2, 'US');
        expect(parseMobile('+79123456789')!.iso2, 'RU');
        expect(parseMobile('+79123456789', preferIso: 'KZ')!.iso2, 'KZ');
      },
    );

    test('spaces and dashes are ignored; garbage is null', () {
      expect(parseMobile('+91 98765-43210')!.digits, '9876543210');
      expect(parseMobile('9876543210'), isNull);
      expect(parseMobile('+abc'), isNull);
      expect(parseMobile(''), isNull);
    });
  });

  group('editing an existing profile', () {
    test(
      'loading a profile does not sync: a US country with a +91 number stays',
      () async {
        final c = await _ready(
          requireLocation: false,
          requireMobile: false,
          defaultToIndia: false,
        );
        c.loadFromProfile(
          country: 'United States',
          stateValue: 'Texas',
          cityValue: 'Austin',
          mobile: '+919876543210',
        );
        expect(c.countryName, 'United States');
        expect(c.dialCode, '+91');
        expect(c.numberController.text, '9876543210');
        expect(c.state, 'Texas');
        expect(c.city, 'Austin');
      },
    );

    test(
      'an untouched stored number is sent back as-is and not re-validated',
      () async {
        final c = await _ready(requireMobile: false, defaultToIndia: false);
        c.loadFromProfile(
          country: '',
          stateValue: '',
          cityValue: '',
          mobile: '+9112345',
        );
        expect(c.mobileEdited, isFalse);
        expect(c.mobileError, isNull);
        expect(c.mobileForSubmit, '+9112345');
      },
    );

    test(
      'once edited, the number is validated and the new value is sent',
      () async {
        final c = await _ready(requireMobile: false, defaultToIndia: false);
        c.loadFromProfile(
          country: '',
          stateValue: '',
          cityValue: '',
          mobile: '+919876543210',
        );
        c.numberFormatter.formatEditUpdate(
          TextEditingValue.empty,
          const TextEditingValue(text: '9123456789'),
        );
        c.numberController.text = '9123456789';
        expect(c.mobileEdited, isTrue);
        expect(c.mobileForSubmit, '+919123456789');
      },
    );

    test('a stored number cannot be removed', () async {
      final c = await _ready(requireMobile: false, defaultToIndia: false);
      c.loadFromProfile(
        country: '',
        stateValue: '',
        cityValue: '',
        mobile: '+919876543210',
      );
      c.numberController.clear();
      expect(c.mobileError, 'Mobile number cannot be removed.');
    });

    test('no stored number and none typed is fine on the profile', () async {
      final c = await _ready(requireMobile: false, defaultToIndia: false);
      c.loadFromProfile(country: '', stateValue: '', cityValue: '', mobile: '');
      expect(c.mobileError, isNull);
      expect(c.mobileForSubmit, '');
    });

    test('a legacy ISO code resolves to the canonical country name', () async {
      final c = await _ready(requireLocation: false, defaultToIndia: false);
      c.loadFromProfile(
        country: 'IN',
        stateValue: 'Kerala',
        cityValue: '',
        mobile: '',
      );
      expect(c.countryName, 'India');
      expect(c.iso2, 'IN');
      expect(c.state, 'Kerala');
    });

    test(
      'a country the list does not know is kept as typed, never blanked',
      () async {
        final c = await _ready(requireLocation: false, defaultToIndia: false);
        c.loadFromProfile(
          country: 'Atlantis',
          stateValue: 'Deep',
          cityValue: '',
          mobile: '',
        );
        expect(c.countryName, 'Atlantis');
        expect(c.iso2, '');
        expect(c.state, 'Deep');
        expect(c.stateError, isNull);
      },
    );

    test('Not set clears Country, State and City', () async {
      final c = await _ready(requireLocation: false, defaultToIndia: false);
      c.loadFromProfile(
        country: 'India',
        stateValue: 'Kerala',
        cityValue: 'Kochi',
        mobile: '',
      );
      c.clearCountry();
      expect(c.hasCountry, isFalse);
      expect(c.state, '');
      expect(c.city, '');
    });
  });

  test('dial options list each country once, with its flag', () async {
    final c = await _ready();
    final labels = c.dialOptions.map((o) => o.label).toList();
    expect(labels, contains('🇺🇸 United States (+1)'));
    expect(labels, contains('🇨🇦 Canada (+1)'));
    // No dial entry → not offered.
    expect(labels.any((l) => l.contains('Antarctica')), isFalse);
  });
}

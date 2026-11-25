import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/screens/profile_settings_screen.dart';
import 'package:humancare_connect/widgets/geo_phone_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _countries = [
  {'name': 'Gibraltar', 'isoCode': 'GI'},
  {'name': 'India', 'isoCode': 'IN'},
];

const _states = {
  'IN': ['Goa', 'Kerala'],
  'GI': <String>[],
};

/// Opens Edit Profile against a fake server holding this saved location.
Future<void> _withProfile(
  WidgetTester tester, {
  required String country,
  String state = '',
  String city = '',
  required Future<void> Function() body,
}) async {
  GeoPhoneController.clearCaches();
  dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({'auth_token': 'access'});
  // Tall enough that the info card and the whole form are built.
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 2400);
  addTearDown(tester.view.reset);

  final client = MockClient((request) async {
    final path = request.url.path;
    final Object response;
    if (path.endsWith('/locations/countries')) {
      response = {'countries': _countries};
    } else if (path.contains('/locations/states/')) {
      response = {
        'states': [
          for (final name in _states[path.split('/').last] ?? const <String>[])
            {'name': name},
        ],
      };
    } else {
      response = {
        'user': {
          '_id': 'u1',
          'name': 'Asha Rao',
          'email': 'asha@example.test',
          'role': 'patient',
          'country': country,
          'state': state,
          'city': city,
        },
      };
    }
    return http.Response(
      jsonEncode(response),
      200,
      headers: {'content-type': 'application/json'},
    );
  });

  await http.runWithClient(() async {
    await tester.pumpWidget(const MaterialApp(home: EditProfilePage()));
    await tester.pumpAndSettle();
    await body();
  }, () => client);
}

// Every label is drawn in capitals, both in the info card and above its form
// field: two matches mean "card row + field", one means the field only.
final _countryLabel = find.text('COUNTRY');
final _stateLabel = find.text('STATE / PROVINCE');
final _cityLabel = find.text('CITY');

void main() {
  testWidgets('info card shows Country, State and City, in that order', (
    tester,
  ) async {
    await _withProfile(
      tester,
      country: 'India',
      state: 'Goa',
      city: 'Panaji',
      body: () async {
        expect(_countryLabel, findsNWidgets(2));
        expect(_stateLabel, findsNWidgets(2));
        expect(_cityLabel, findsNWidgets(2));
        final country = tester.getTopLeft(_countryLabel.first).dy;
        final state = tester.getTopLeft(_stateLabel.first).dy;
        final city = tester.getTopLeft(_cityLabel.first).dy;
        expect(country, lessThan(state));
        expect(state, lessThan(city));
        expect(find.textContaining('(OPTIONAL)'), findsNWidgets(2));
        expect(find.text('GENDER (OPTIONAL)'), findsOneWidget);
        expect(find.text('DATE OF BIRTH (OPTIONAL)'), findsOneWidget);
      },
    );
  });

  testWidgets('an empty State or City has no row in the card', (tester) async {
    await _withProfile(
      tester,
      country: 'India',
      body: () async {
        expect(_countryLabel, findsNWidgets(2));
        expect(_stateLabel, findsOneWidget);
        expect(_cityLabel, findsOneWidget);
      },
    );
  });

  testWidgets('the card follows the form before saving', (tester) async {
    await _withProfile(
      tester,
      country: 'India',
      state: 'Goa',
      city: 'Panaji',
      body: () async {
        await tester.enterText(
          find.widgetWithText(TextFormField, 'Panaji'),
          'Margao',
        );
        await tester.pumpAndSettle();
        expect(find.text('Margao'), findsNWidgets(2));

        // A new country clears State and City, so their rows go.
        await tester.tap(find.text('India').last);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Gibraltar').last);
        await tester.pumpAndSettle();

        expect(find.text('Gibraltar'), findsNWidgets(2));
        expect(_stateLabel, findsOneWidget);
        expect(_cityLabel, findsOneWidget);
        expect(find.text('No states available'), findsOneWidget);
      },
    );
  });
}

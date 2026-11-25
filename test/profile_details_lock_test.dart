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

/// Opens Edit Profile against a fake server holding this dob and gender, with
/// [cached] as the copy on the phone. Collects the profile saves in [saves].
Future<void> _withProfile(
  WidgetTester tester, {
  String dob = '',
  String gender = '',
  Map<String, String> cached = const {},
  List<Map<String, dynamic>>? saves,
  required Future<void> Function() body,
}) async {
  GeoPhoneController.clearCaches();
  dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
  SharedPreferences.setMockInitialValues({});
  FlutterSecureStorage.setMockInitialValues({
    'auth_token': 'access',
    ...cached,
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(400, 2400);
  addTearDown(tester.view.reset);

  final client = MockClient((request) async {
    final path = request.url.path;
    final Object response;
    if (path.endsWith('/locations/countries')) {
      response = {'countries': <Object>[]};
    } else if (path.contains('/locations/states/')) {
      response = {'states': <Object>[]};
    } else {
      if (request.method == 'PUT') {
        saves?.add(jsonDecode(request.body) as Map<String, dynamic>);
      }
      response = {
        'user': {
          '_id': 'u1',
          'name': 'Asha Rao',
          'email': 'asha@example.test',
          'role': 'patient',
          'dob': dob,
          'gender': gender,
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

Future<void> _openGender(WidgetTester tester) async {
  await tester.tap(find.byType(DropdownButtonFormField<String>));
  await tester.pumpAndSettle();
}

Future<void> _saveProfile(WidgetTester tester) async {
  await tester.tap(find.textContaining('Save').last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('saved values can be changed but not cleared', (tester) async {
    final saves = <Map<String, dynamic>>[];
    await _withProfile(
      tester,
      dob: '1990-05-01',
      gender: 'Male',
      saves: saves,
      body: () async {
        expect(find.text('GENDER'), findsWidgets);
        expect(find.text('GENDER (OPTIONAL)'), findsNothing);
        expect(find.text('DATE OF BIRTH (OPTIONAL)'), findsNothing);
        expect(find.byIcon(Icons.close), findsNothing);

        await _openGender(tester);
        expect(find.text('Select gender'), findsNothing);
        await tester.tap(find.text('Female').last);
        await tester.pumpAndSettle();

        // The calendar opens on the saved date.
        await tester.tap(find.text('1-5-1990'));
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<DatePickerDialog>(find.byType(DatePickerDialog))
              .initialDate,
          DateTime(1990, 5, 1),
        );
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();

        await _saveProfile(tester);
        expect(saves.single['dob'], '1990-05-01');
        expect(saves.single['gender'], 'Female');
      },
    );
  });

  testWidgets('empty values stay optional and are never sent empty', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    await _withProfile(
      tester,
      saves: saves,
      body: () async {
        expect(find.text('GENDER (OPTIONAL)'), findsOneWidget);
        expect(find.text('DATE OF BIRTH (OPTIONAL)'), findsOneWidget);
        await _openGender(tester);
        expect(find.text('Select gender'), findsWidgets);
        await tester.tap(find.text('Select gender').last);
        await tester.pumpAndSettle();

        // A date picked but not yet saved can still be taken back.
        await tester.tap(find.text('Select date of birth'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('OK'));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.close));
        await tester.pumpAndSettle();

        await _saveProfile(tester);
        expect(saves.single.containsKey('dob'), isFalse);
        expect(saves.single.containsKey('gender'), isFalse);
      },
    );
  });

  testWidgets('an unreadable saved date does not block the save', (
    tester,
  ) async {
    final saves = <Map<String, dynamic>>[];
    await _withProfile(
      tester,
      dob: 'not a date',
      gender: 'Other',
      saves: saves,
      body: () async {
        await _saveProfile(tester);
        expect(saves.single.containsKey('dob'), isFalse);
        expect(saves.single['gender'], 'Other');
      },
    );
  });

  testWidgets('the server filling an empty phone copy does not break the list', (
    tester,
  ) async {
    await _withProfile(
      tester,
      gender: 'Female',
      cached: {'user_name': 'Asha Rao', 'user_gender': ''},
      body: () async {
        expect(tester.takeException(), isNull);
        expect(find.text('Female'), findsWidgets);
        expect(find.text('Select gender'), findsNothing);
      },
    );
  });
}

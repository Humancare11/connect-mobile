import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/screens/complete_details_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/auth_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

AuthService _auth(Future<http.Response> Function(http.Request) handler) =>
    AuthService(
      apiClient: ApiClient(
        client: MockClient(handler),
        tokenStorage: const TokenStorageService(),
      ),
    );

http.Response _json(Object body, [int status = 200]) =>
    http.Response(jsonEncode(body), status);

final _navigatorKey = GlobalKey<NavigatorState>();

/// What the screen popped with: true when saved, false otherwise.
bool? _result;

Future<void> _open(
  WidgetTester tester,
  AuthService auth, {
  String dob = '',
  String gender = '',
}) async {
  _result = null;
  await tester.pumpWidget(
    MaterialApp(
      navigatorKey: _navigatorKey,
      home: const Scaffold(body: Text('PREVIOUS SCREEN')),
    ),
  );
  unawaited(
    CompleteDetailsScreen.open(
      _navigatorKey.currentContext!,
      dob: dob,
      gender: gender,
      authService: auth,
    ).then((value) => _result = value),
  );
  await tester.pumpAndSettle();
}

Future<void> _save(WidgetTester tester) async {
  await tester.tap(find.text('Save & Continue to Payment →'));
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access',
      'user_name': 'Asha Rao',
      'user_country': 'India',
    });
  });

  testWidgets('both are required: nothing is sent without them', (tester) async {
    var calls = 0;
    await _open(tester, _auth((_) async {
      calls++;
      return _json({});
    }));
    await _save(tester);

    expect(find.text('Select Date of Birth'), findsOneWidget);
    expect(find.text('Please select a gender.'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('saves with the right call, keeps the phone copy, pops true', (
    tester,
  ) async {
    final requests = <http.Request>[];
    await _open(tester, _auth((request) async {
      requests.add(request);
      return _json({'user': {}});
    }), dob: '1990-05-01');

    expect(find.text('1-5-1990'), findsOneWidget);
    await tester.tap(find.text('Female'));
    await tester.pumpAndSettle();
    await _save(tester);

    expect(requests.single.method, 'PUT');
    expect(requests.single.url.path, '/api/auth/patient-details');
    expect(jsonDecode(requests.single.body), {
      'dob': '1990-05-01',
      'gender': 'Female',
    });
    expect(
      requests.single.headers.keys.map((k) => k.toLowerCase()),
      isNot(contains('x-client')),
    );
    expect(_result, isTrue);
    expect(find.text('PREVIOUS SCREEN'), findsOneWidget);

    final stored = await const TokenStorageService().getUserProfile();
    expect(stored['dob'], '1990-05-01');
    expect(stored['gender'], 'Female');
    expect(stored['name'], 'Asha Rao');
    expect(stored['country'], 'India');
  });

  testWidgets('a date picked in the calendar is what gets sent', (tester) async {
    Map<String, dynamic>? sent;
    await _open(tester, _auth((request) async {
      sent = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({'user': {}});
    }), gender: 'Other');

    await tester.tap(find.byKey(const ValueKey('details dob')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    await _save(tester);

    expect(sent, {'dob': '2000-01-01', 'gender': 'Other'});
  });

  testWidgets('a refused save shows the server message and stays', (
    tester,
  ) async {
    await _open(
      tester,
      _auth(
        (_) async => _json({'msg': 'Date of Birth cannot be in the future.'}, 400),
      ),
      dob: '1990-05-01',
      gender: 'Male',
    );
    await _save(tester);

    expect(find.text('Date of Birth cannot be in the future.'), findsOneWidget);
    expect(find.text('PREVIOUS SCREEN'), findsNothing);
    expect(_result, isNull);
    final stored = await const TokenStorageService().getUserProfile();
    expect(stored['gender'], '');
  });

  testWidgets('unusable saved values are not pre-filled; back is not a save', (
    tester,
  ) async {
    await _open(
      tester,
      _auth((_) async => _json({})),
      dob: '1990-02-31',
      gender: 'male',
    );
    expect(find.text('Select date of birth'), findsOneWidget);
    expect(
      tester.widgetList<ChoiceChip>(find.byType(ChoiceChip)).where(
        (chip) => chip.selected,
      ),
      isEmpty,
    );

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(_result, isFalse);
  });

  group('fetchPatientDetails', () {
    test('reads dob and gender from /auth/me', () async {
      late String path;
      final auth = _auth((request) async {
        path = request.url.path;
        return _json({
          'user': {'_id': 'u1', 'dob': '1990-05-01', 'gender': 'Male'},
        });
      });
      final details = await auth.fetchPatientDetails();
      expect(path, '/api/auth/me');
      expect(details, (dob: '1990-05-01', gender: 'Male'));
    });

    test('a profile without them reads as empty, not as unknown', () async {
      final auth = _auth((_) async => _json({'user': {'_id': 'u1'}}));
      expect(await auth.fetchPatientDetails(), (dob: '', gender: ''));
    });

    test('an error, an odd answer or no network is unknown (null)', () async {
      for (final auth in [
        _auth((_) async => _json({'msg': 'Server error.'}, 500)),
        _auth((_) async => _json({'ok': true})),
        _auth((_) async => http.Response('<html>', 200)),
        _auth((_) async => throw http.ClientException('offline')),
      ]) {
        expect(await auth.fetchPatientDetails(), isNull);
      }
    });

    test('a server that does not answer in time is unknown', () async {
      final never = Completer<http.Response>();
      final auth = _auth((_) => never.future);
      expect(
        await auth.fetchPatientDetails(
          timeout: const Duration(milliseconds: 20),
        ),
        isNull,
      );
      never.complete(_json({}));
    });
  });
}

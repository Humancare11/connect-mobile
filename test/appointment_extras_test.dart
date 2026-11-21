import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/screens/appointments_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _appt({
  String id = 'a1',
  String status = 'confirmed',
  Map<String, dynamic>? reschedule,
  Map<String, dynamic>? doctor = const {'_id': 'd1', 'name': 'Rao', 'email': 'rao@example.com'},
}) => {
  '_id': id,
  'status': status,
  'date': '2026-11-20',
  'time': '10:00 AM',
  'problem': 'Headache',
  'doctorId': ?doctor,
  'reschedule': ?reschedule,
};

const _resched = {
  'count': 1,
  'previousDate': '2026-11-07',
  'previousTime': '10:00 AM',
  'lastAt': '2026-11-09T09:00:00.000Z',
  'by': 'admin',
};

Future<void> _pump(
  WidgetTester tester,
  List<Map<String, dynamic>> appointments, {
  String tab = 'confirmed',
}) async {
  // Tall enough that the whole page is on screen.
  tester.view.physicalSize = const Size(800, 2000);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AppointmentsScreen(
        key: UniqueKey(),
        enableRealtime: false,
        apiClient: ApiClient(
          client: MockClient((_) async => http.Response(jsonEncode(appointments), 200)),
          tokenStorage: const TokenStorageService(),
        ),
      ),
    ),
  );
  for (var i = 0; i < 4; i++) {
    await tester.pump();
  }
  if (tab != 'confirmed') {
    // The stats strip repeats the labels; the tab bar comes after it.
    await tester.tap(find.text(tab[0].toUpperCase() + tab.substring(1)).last);
    await tester.pump();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    dotenv.testLoad(fileInput: 'API_BASE_URL=https://example.test/api');
    SharedPreferences.setMockInitialValues({});
    FlutterSecureStorage.setMockInitialValues({
      'auth_token': 'access',
      'refresh_token': 'refresh',
      'user_role': 'user',
      'user_name': 'Asha',
    });
  });

  group('Appointment.reschedule', () {
    test('is read from the backend summary', () {
      final appt = Appointment.fromJson(_appt(reschedule: Map.of(_resched)));
      expect(appt.reschedule, isNotNull);
      expect(appt.reschedule!.previousDate, '2026-11-07');
      expect(appt.reschedule!.previousTime, '10:00 AM');
      expect(appt.reschedule!.lastAt, '2026-11-09T09:00:00.000Z');
    });

    test('is null for a booking that was never rescheduled', () {
      expect(Appointment.fromJson(_appt()).reschedule, isNull);
    });
  });

  group('reschedule banner', () {
    testWidgets('shows what changed, when, and from which slot', (tester) async {
      await _pump(tester, [_appt(reschedule: Map.of(_resched))]);

      final changed = DateFormat('d MMM y, h:mm a')
          .format(DateTime.parse('2026-11-09T09:00:00.000Z').toLocal());
      expect(find.text('Your appointment was rescheduled'), findsOneWidget);
      expect(find.text('Rescheduled from 7 Nov 2026, 10:00 AM'), findsOneWidget);
      expect(find.text('Changed on $changed'), findsOneWidget);
      // The rest of the card is untouched.
      expect(find.text('Join Consultation'), findsOneWidget);
      expect(find.text('Reason for visit'), findsOneWidget);
    });

    testWidgets('leaves out the time and the change time when they are missing', (tester) async {
      await _pump(tester, [
        _appt(reschedule: {'previousDate': '2026-11-07'}),
      ]);

      expect(find.text('Rescheduled from 7 Nov 2026'), findsOneWidget);
      expect(find.textContaining('Changed on'), findsNothing);
    });

    testWidgets('is not shown for a booking that was never rescheduled', (tester) async {
      await _pump(tester, [_appt()]);

      expect(find.text('Your appointment was rescheduled'), findsNothing);
    });

    testWidgets('also shows on a completed booking', (tester) async {
      await _pump(
        tester,
        [_appt(status: 'completed', reschedule: Map.of(_resched))],
        tab: 'completed',
      );

      expect(find.text('Your appointment was rescheduled'), findsOneWidget);
    });
  });

  group('pending note', () {
    const expected = {
      'requested': 'Awaiting admin review and doctor assignment',
      'upcoming': 'Awaiting admin review and doctor assignment',
      'pending': 'Awaiting doctor confirmation',
      'assigned': 'Awaiting doctor confirmation',
    };

    for (final entry in expected.entries) {
      testWidgets('${entry.key} reads "${entry.value}"', (tester) async {
        await _pump(tester, [_appt(status: entry.key)], tab: 'pending');

        expect(find.text(entry.value), findsOneWidget);
        expect(find.text('Join Consultation'), findsNothing);
      });
    }
  });

  group('completed', () {
    testWidgets('a completed card offers View Prescription & Certificate', (tester) async {
      await _pump(tester, [_appt(status: 'completed')], tab: 'completed');

      expect(find.text('Consultation completed'), findsOneWidget);
      expect(find.text('View Prescription & Certificate'), findsOneWidget);
      expect(find.text('Join Consultation'), findsNothing);
    });

    testWidgets('a confirmed card has no records button', (tester) async {
      await _pump(tester, [_appt()]);

      expect(find.text('View Prescription & Certificate'), findsNothing);
    });

    testWidgets('an empty Completed tab offers View Medical Records', (tester) async {
      await _pump(tester, [_appt()], tab: 'completed');

      expect(find.text('No completed appointments'), findsOneWidget);
      expect(find.text('View Medical Records'), findsOneWidget);
      expect(find.text('Book Appointment'), findsNothing);
    });

    testWidgets('empty Pending and Confirmed tabs still offer Book Appointment', (tester) async {
      await _pump(tester, [_appt(status: 'completed')]);
      expect(find.text('No confirmed appointments'), findsOneWidget);
      expect(find.text('Book Appointment'), findsWidgets);
      expect(find.text('View Medical Records'), findsNothing);

      await tester.tap(find.text('Pending').last);
      await tester.pump();
      expect(find.text('No pending appointments'), findsOneWidget);
      expect(find.text('View Medical Records'), findsNothing);
    });
  });
}

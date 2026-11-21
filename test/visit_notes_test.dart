import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/models/api_result.dart';
import 'package:humancare_connect/models/visit_note_models.dart';
import 'package:humancare_connect/screens/my_visit_notes_screen.dart';
import 'package:humancare_connect/screens/visit_note_detail_screen.dart';
import 'package:humancare_connect/screens/visit_note_pdf.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:humancare_connect/services/visit_notes_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A real, valid 1x1 PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

Map<String, dynamic> _report({
  String id = 'r1',
  String number = 'HCR-2026-0001',
  String consultationDate = '2026-11-07',
  String signedAt = '2026-11-07T10:05:00.000Z',
  String physician = 'Dr Rao',
  List<Map<String, dynamic>> amendments = const [],
  String note = '',
}) => {
  '_id': id,
  'reportNumber': number,
  'patient': {'name': 'Asha', 'gender': 'Female', 'dob': '1990-01-01', 'age': '36'},
  'consultation': {'date': consultationDate, 'time': '10:00 AM', 'mode': 'Video Consultation'},
  'physician': {
    'name': physician,
    'registrationNumber': 'REG123',
    'speciality': 'GP',
    'country': 'IN',
  },
  'symptoms': 'Headache',
  'clinicalFindings': 'Normal',
  'plan': 'Rest',
  'note': note,
  'signedAt': signedAt,
  'status': 'final',
  'amendments': amendments,
};

Map<String, dynamic> _pending({
  String id = 'a1',
  String date = '2026-11-08',
  String time = '11:00 AM',
  String doctorName = 'Dr Mehta',
}) => {'appointmentId': id, 'date': date, 'time': time, 'doctorName': doctorName};

class _FakeService extends VisitNotesService {
  _FakeService({this.mine, this.one, this.signature});

  ApiResult<VisitNotesSnapshot>? mine;
  ApiResult<VisitNoteReport>? one;
  Uint8List? signature;
  int mineCalls = 0;

  @override
  Future<ApiResult<VisitNotesSnapshot>> fetchMine({bool silent = false}) async {
    mineCalls++;
    return mine!;
  }

  @override
  Future<ApiResult<VisitNoteReport>> fetchOne(String id, {bool silent = false}) async =>
      one!;

  @override
  Future<Uint8List?> fetchSignature(String id) async => signature;

  @override
  Future<Uint8List?> fetchSignatureWithRetry(String id) async => signature;

  @override
  Future<String> countryName(String value) async => value == 'IN' ? 'India' : value;
}

ApiResult<VisitNotesSnapshot> _snapshot({
  List<Map<String, dynamic>> reports = const [],
  List<Map<String, dynamic>> pending = const [],
}) => ApiResult(
  success: true,
  message: '',
  data: VisitNotesSnapshot.fromJson({'reports': reports, 'pending': pending}),
);

Future<void> _pumpList(WidgetTester tester, _FakeService service) async {
  await tester.pumpWidget(
    MaterialApp(
      home: MyVisitNotesScreen(
        service: service,
        sharePdf: (bytes, filename) async {},
      ),
    ),
  );
  await tester.pumpAndSettle();
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

  group('models', () {
    test('a report is read with its patient, consultation, physician and amendments', () {
      final report = VisitNoteReport.fromJson(
        _report(
          amendments: [
            {
              '_id': 'am1',
              'authorName': 'Dr Rao',
              'reason': 'Typo',
              'text': 'Fixed',
              'createdAt': '2026-11-09T09:00:00.000Z',
            },
          ],
        ),
      );
      expect(report.id, 'r1');
      expect(report.reportNumber, 'HCR-2026-0001');
      expect(report.patientName, 'Asha');
      expect(report.consultationWhen, '07 Nov 2026 · 10:00 AM');
      expect(report.physicianName, 'Dr Rao');
      expect(report.physicianCountry, 'IN');
      expect(report.isAmended, isTrue);
      expect(report.amendments.single.reason, 'Typo');
      expect(VisitNoteReport.fromJson(_report()).isAmended, isFalse);
    });

    test('a missing mode reads as Video Consultation; missing fields are empty', () {
      final report = VisitNoteReport.fromJson({'_id': 'x'});
      expect(report.modeLabel, 'Video Consultation');
      expect(report.symptoms, '');
      expect(report.amendments, isEmpty);
    });

    test('the list date is the consultation date, else the signing time', () {
      expect(VisitNoteReport.fromJson(_report()).displayDate, '2026-11-07');
      expect(
        VisitNoteReport.fromJson(_report(consultationDate: '')).displayDate,
        '2026-11-07T10:05:00.000Z',
      );
    });

    test('reports and pending entries merge newest first, ties keep reports first', () {
      final snapshot = VisitNotesSnapshot.fromJson({
        'reports': [
          _report(id: 'old', consultationDate: '2026-10-01'),
          _report(id: 'same', consultationDate: '2026-11-08'),
        ],
        'pending': [
          _pending(id: 'new', date: '2026-11-20'),
          _pending(id: 'tie', date: '2026-11-08'),
        ],
      });
      final ids = snapshot.items
          .map((i) => i.report?.id ?? i.pending!.appointmentId)
          .toList();
      expect(ids, ['new', 'same', 'tie', 'old']);
    });

    test('date helpers: dd MMM yyyy, empty stays empty, odd text is kept', () {
      expect(formatVisitNoteDate('2026-11-07'), '07 Nov 2026');
      expect(formatVisitNoteDate(''), '');
      expect(formatVisitNoteDate('not a date'), 'not a date');
    });
  });

  group('VisitNotesService', () {
    VisitNotesService serviceFor(Future<http.Response> Function(http.Request) h) =>
        VisitNotesService(
          apiClient: ApiClient(
            client: MockClient(h),
            tokenStorage: const TokenStorageService(),
          ),
        );

    test('fetchMine reads reports and pending from /consultation-reports/mine', () async {
      Uri? uri;
      final result = await serviceFor((request) async {
        uri = request.url;
        return http.Response(
          jsonEncode({
            'reports': [_report()],
            'pending': [_pending()],
          }),
          200,
        );
      }).fetchMine(silent: true);

      expect(uri?.path, '/api/consultation-reports/mine');
      expect(result.success, isTrue);
      expect(result.data!.reports.single.reportNumber, 'HCR-2026-0001');
      expect(result.data!.pending.single.doctorName, 'Dr Mehta');
    });

    test('fetchMine surfaces the server message, with a fallback', () async {
      final withMsg = await serviceFor(
        (_) async => http.Response(jsonEncode({'msg': 'Boom'}), 500),
      ).fetchMine(silent: true);
      expect(withMsg.success, isFalse);
      expect(withMsg.message, 'Boom');

      final without = await serviceFor((_) async => http.Response('{}', 500)).fetchMine(
        silent: true,
      );
      expect(without.message, isNotEmpty);
    });

    test('fetchOne reads { report } and reports a 404', () async {
      Uri? uri;
      final ok = await serviceFor((request) async {
        uri = request.url;
        return http.Response(jsonEncode({'report': _report(id: 'r9')}), 200);
      }).fetchOne('r9', silent: true);
      expect(uri?.path, '/api/consultation-reports/mine/r9');
      expect(ok.data!.id, 'r9');

      final missing = await serviceFor(
        (_) async => http.Response(jsonEncode({'msg': 'Visit Note not found.'}), 404),
      ).fetchOne('nope', silent: true);
      expect(missing.success, isFalse);
      expect(missing.statusCode, 404);
    });

    test('the signature is fetched with auth, cached, and a failure is null', () async {
      var calls = 0;
      String? auth;
      Uri? uri;
      final service = serviceFor((request) async {
        calls++;
        auth = request.headers['Authorization'];
        uri = request.url;
        return http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'});
      });

      expect(await service.fetchSignature('r1'), _png);
      expect(await service.fetchSignature('r1'), _png);
      expect(calls, 1);
      expect(auth, 'Bearer access');
      expect(uri?.path, '/api/consultation-reports/mine/r1/signature');
      expect(service.cachedSignature('r1'), _png);

      final notPng = serviceFor(
        (_) async => http.Response.bytes(Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8, 9]), 200),
      );
      expect(await notPng.fetchSignature('r1'), isNull);

      final missing = serviceFor(
        (_) async => http.Response(jsonEncode({'msg': 'Signature not found.'}), 404),
      );
      expect(await missing.fetchSignatureWithRetry('r1'), isNull);
    });

    test('a value that is not a 2-letter code is shown as it is', () async {
      final service = serviceFor((_) async => http.Response('{}', 500));
      expect(await service.countryName('India'), 'India');
      expect(await service.countryName(''), '');
      // An unreachable country list falls back to the code itself.
      expect(await service.countryName('IN'), 'IN');
    });
  });

  group('VisitNotePdf', () {
    test('creates a PDF with and without a signature', () async {
      final report = VisitNoteReport.fromJson(
        _report(
          note: 'Extra note',
          amendments: [
            {
              '_id': 'am1',
              'authorName': 'Dr Rao',
              'reason': 'Typo',
              'text': 'Fixed',
              'createdAt': '2026-11-09T09:00:00.000Z',
            },
          ],
        ),
      );
      final withSignature = await VisitNotePdf.build(report, signature: _png, countryName: 'India');
      final without = await VisitNotePdf.build(report);

      expect(String.fromCharCodes(withSignature.take(5)), '%PDF-');
      expect(String.fromCharCodes(without.take(5)), '%PDF-');
      expect(withSignature.length, greaterThan(without.length));
    });

    test('a very long note flows onto more pages instead of failing', () async {
      final longText = List.filled(400, 'A long line of the consultation note.').join('\n');
      final report = VisitNoteReport.fromJson({
        ..._report(),
        'plan': longText,
        'note': longText,
      });
      final bytes = await VisitNotePdf.build(report);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(bytes.length, greaterThan(5000));
    });
  });

  group('MyVisitNotesScreen', () {
    testWidgets('shows signed, amended and pending items, newest first', (tester) async {
      await _pumpList(
        tester,
        _FakeService(
          mine: _snapshot(
            reports: [
              _report(id: 'r1', consultationDate: '2026-11-07'),
              _report(
                id: 'r2',
                number: 'HCR-2026-0002',
                consultationDate: '2026-11-05',
                amendments: [
                  {'_id': 'a', 'authorName': 'Dr Rao', 'reason': 'x', 'text': 'y', 'createdAt': '2026-11-06T00:00:00.000Z'},
                ],
              ),
            ],
            pending: [_pending(date: '2026-11-08')],
          ),
        ),
      );

      expect(find.text('My Visit Notes'), findsWidgets);
      expect(find.text('Signed'), findsNWidgets(2));
      expect(find.text('Amended'), findsOneWidget);
      expect(find.text('Report pending'), findsOneWidget);
      expect(find.text('Dr Mehta is preparing this note · 11:00 AM'), findsOneWidget);
      expect(find.text('Dr Rao · Video consultation · HCR-2026-0001'), findsOneWidget);
      expect(find.text('View'), findsNWidgets(2));
      expect(find.text('Download PDF'), findsNWidgets(2));

      final order = ['08 Nov 2026', '07 Nov 2026', '05 Nov 2026']
          .map((d) => tester.getTopLeft(find.text(d)).dy)
          .toList();
      expect(order, [...order]..sort());
    });

    testWidgets('empty list shows the empty state', (tester) async {
      await _pumpList(tester, _FakeService(mine: _snapshot()));
      expect(find.text('No consultations yet'), findsOneWidget);
      expect(find.text("Your doctor's signed notes will appear here."), findsOneWidget);
    });

    testWidgets('a failed load shows the message with Retry, not the empty state', (tester) async {
      final service = _FakeService(
        mine: const ApiResult(success: false, message: 'Session expired. Please log in again.', statusCode: 401),
      );
      await _pumpList(tester, service);
      expect(find.text('Session expired. Please log in again.'), findsOneWidget);
      expect(find.text('No consultations yet'), findsNothing);

      service.mine = _snapshot(reports: [_report()]);
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.text('Signed'), findsOneWidget);
      expect(service.mineCalls, 2);
    });

    testWidgets('Download PDF hands a PDF named after the report to the share sheet', (tester) async {
      Uint8List? shared;
      String? name;
      await tester.pumpWidget(
        MaterialApp(
          home: MyVisitNotesScreen(
            service: _FakeService(mine: _snapshot(reports: [_report()]), signature: _png),
            sharePdf: (bytes, filename) async {
              shared = bytes;
              name = filename;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await tester.tap(find.text('Download PDF'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pumpAndSettle();

      expect(name, 'visit-note_HCR-2026-0001.pdf');
      expect(String.fromCharCodes(shared!.take(5)), '%PDF-');
    });
  });

  group('VisitNoteDetailScreen', () {
    Future<void> pumpDetail(WidgetTester tester, _FakeService service) async {
      await tester.pumpWidget(
        MaterialApp(
          home: VisitNoteDetailScreen(
            reportId: 'r1',
            service: service,
            sharePdf: (bytes, filename) async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('shows the note, physician details, country name and amendments', (tester) async {
      await pumpDetail(
        tester,
        _FakeService(
          one: ApiResult(
            success: true,
            message: '',
            data: VisitNoteReport.fromJson(
              _report(
                note: 'Drink water',
                amendments: [
                  {'_id': 'a', 'authorName': 'Dr Rao', 'reason': 'Typo', 'text': 'Fixed', 'createdAt': '2026-11-09T09:00:00.000Z'},
                ],
              ),
            ),
          ),
          signature: _png,
        ),
      );

      expect(find.text('Visit Note Preview'), findsOneWidget);
      expect(find.text('Report ID : HCR-2026-0001'), findsOneWidget);
      expect(find.text('Download PDF'), findsOneWidget);
      expect(find.text('Rest'), findsOneWidget);
      expect(find.text('Note :'), findsOneWidget);
      expect(find.text('India'), findsOneWidget);
      expect(find.text('AMENDMENTS'), findsOneWidget);
      expect(find.byType(Image), findsWidgets);
    });

    testWidgets('the Note row is hidden when the note is empty', (tester) async {
      await pumpDetail(
        tester,
        _FakeService(
          one: ApiResult(success: true, message: '', data: VisitNoteReport.fromJson(_report())),
        ),
      );
      expect(find.text('Note :'), findsNothing);
      expect(find.text('AMENDMENTS'), findsNothing);
    });

    testWidgets('a 404 shows "Visit Note not found"', (tester) async {
      await pumpDetail(
        tester,
        _FakeService(
          one: const ApiResult(success: false, message: 'Visit Note not found.', statusCode: 404),
        ),
      );
      expect(find.text('Visit Note not found'), findsOneWidget);
      expect(find.text('It may not exist, or you may not have access to it.'), findsOneWidget);
    });
  });
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/models/api_result.dart';
import 'package:humancare_connect/models/medical_record_models.dart';
import 'package:humancare_connect/screens/my_records_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/medical_records_service.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _rx() => {
  '_id': 'rx1',
  'diagnosis': 'Migraine',
  'doctorId': {'_id': 'd1', 'name': 'Rao'},
  'medicines': <Map<String, dynamic>>[],
  'createdAt': '2026-11-07T10:00:00.000Z',
};

Map<String, dynamic> _cert() => {
  '_id': 'c1',
  'diagnosis': 'Viral fever',
  'doctorId': {'_id': 'd1', 'name': 'Rao'},
  'issuedDate': '2026-11-07',
  'createdAt': '2026-11-07T10:00:00.000Z',
};

Map<String, dynamic> _report({
  String id = 'mr1',
  String title = 'Blood test summary',
  String status = 'active',
  String doctorName = 'Issued by Humancare',
  String number = 'MR-2026-0001',
}) => {
  '_id': id,
  'reportNumber': number,
  'reportType': 'generated',
  'title': title,
  'reportDate': '2026-11-05T00:00:00.000Z',
  'doctorName': doctorName,
  'status': status,
  'createdAt': '2026-11-05T09:00:00.000Z',
};

/// Routes the three records endpoints of the real service to canned responses.
http.Response Function(http.Request) _routes({
  Object? reports,
  int reportsStatus = 200,
  Map<String, Object?> download = const {},
  int downloadStatus = 200,
}) {
  return (request) {
    final path = request.url.path;
    if (path.endsWith('/medical/my-prescriptions')) {
      return http.Response(jsonEncode([_rx()]), 200);
    }
    if (path.endsWith('/medical/my-certificates')) {
      return http.Response(jsonEncode([_cert()]), 200);
    }
    if (path.endsWith('/medical/my-reports')) {
      return http.Response(jsonEncode(reports ?? <Object>[]), reportsStatus);
    }
    if (path.contains('/medical/my-reports/') && path.endsWith('/download')) {
      return http.Response(jsonEncode(download), downloadStatus);
    }
    return http.Response('{}', 404);
  };
}

MedicalRecordsService _service(http.Response Function(http.Request) routes) =>
    MedicalRecordsService(
      apiClient: ApiClient(
        client: MockClient((request) async => routes(request)),
        tokenStorage: const TokenStorageService(),
      ),
    );

class _FakeRecords extends MedicalRecordsService {
  _FakeRecords({
    this.reports = const [],
    this.error = '',
    this.link,
  });

  final List<Map<String, dynamic>> reports;
  final String error;
  ApiResult<MedicalReportDownloadLink>? link;
  final opened = <String>[];

  @override
  Future<MedicalRecordsSnapshot> fetchMyRecords({bool silent = false}) async {
    return MedicalRecordsSnapshot(
      prescriptions: [PrescriptionRecord.fromJson(_rx())],
      certificates: [MedicalCertificateRecord.fromJson(_cert())],
      reports: reports.map(MedicalReportRecord.fromJson).toList(),
      error: error,
    );
  }

  @override
  Future<ApiResult<MedicalReportDownloadLink>> fetchReportDownloadLink(
    String id, {
    bool silent = false,
  }) async {
    opened.add(id);
    return link ??
        const ApiResult(
          success: true,
          message: '',
          data: MedicalReportDownloadLink(url: 'https://files.test/r.pdf'),
        );
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

  group('MedicalReportRecord', () {
    test('reads the metadata and flags a voided report', () {
      final active = MedicalReportRecord.fromJson(_report());
      expect(active.id, 'mr1');
      expect(active.title, 'Blood test summary');
      expect(active.reportNumber, 'MR-2026-0001');
      expect(active.isVoided, isFalse);

      expect(MedicalReportRecord.fromJson(_report(status: 'voided')).isVoided, isTrue);
      expect(MedicalReportRecord.fromJson(_report(status: 'VOIDED')).isVoided, isTrue);
      expect(MedicalReportRecord.fromJson({'_id': 'x'}).isVoided, isFalse);
    });
  });

  group('MedicalRecordsService', () {
    test('fetchMyRecords reads the reports array alongside the others', () async {
      final snapshot = await _service(
        _routes(reports: [_report(), _report(id: 'mr2', status: 'voided')]),
      ).fetchMyRecords(silent: true);

      expect(snapshot.error, isEmpty);
      expect(snapshot.prescriptions, hasLength(1));
      expect(snapshot.certificates, hasLength(1));
      expect(snapshot.reports.map((r) => r.id), ['mr1', 'mr2']);
      expect(snapshot.reports.last.isVoided, isTrue);
    });

    test('a failed reports call keeps prescriptions and certificates', () async {
      final snapshot = await _service(
        _routes(reports: {'msg': 'Failed to fetch medical reports.'}, reportsStatus: 500),
      ).fetchMyRecords(silent: true);

      expect(snapshot.prescriptions, hasLength(1));
      expect(snapshot.certificates, hasLength(1));
      expect(snapshot.reports, isEmpty);
      expect(
        snapshot.error,
        'Could not load medical reports. Failed to fetch medical reports.',
      );
    });

    test('the existing prescription/certificate error messages are unchanged', () async {
      final snapshot = await _service((request) {
        if (request.url.path.endsWith('/medical/my-certificates')) {
          return http.Response(jsonEncode({'msg': 'Boom'}), 500);
        }
        return _routes()(request);
      }).fetchMyRecords(silent: true);

      expect(snapshot.error, 'Could not load certificates. Boom');
    });

    test('fetchReportDownloadLink returns the presigned url', () async {
      Uri? uri;
      final result = await _service((request) {
        uri = request.url;
        return http.Response(
          jsonEncode({'url': 'https://files.test/r.pdf', 'reportNumber': 'MR-1'}),
          200,
        );
      }).fetchReportDownloadLink('mr1', silent: true);

      expect(uri?.path, '/api/medical/my-reports/mr1/download');
      expect(result.success, isTrue);
      expect(result.data!.url, 'https://files.test/r.pdf');
    });

    test('a voided (403) or missing (404) report surfaces the server message', () async {
      final voided = await _service(
        (_) => http.Response(jsonEncode({'msg': 'This report has been voided.'}), 403),
      ).fetchReportDownloadLink('mr1', silent: true);
      expect(voided.success, isFalse);
      expect(voided.statusCode, 403);
      expect(voided.message, 'This report has been voided.');

      final missing = await _service(
        (_) => http.Response(jsonEncode({'msg': 'Report not found.'}), 404),
      ).fetchReportDownloadLink('nope', silent: true);
      expect(missing.success, isFalse);
      expect(missing.message, 'Report not found.');
    });
  });

  group('MyRecordsPage reports', () {
    Future<_FakeRecords> pumpPage(
      WidgetTester tester, {
      List<Map<String, dynamic>> reports = const [],
      String error = '',
      String initialTab = 'prescriptions',
      ApiResult<MedicalReportDownloadLink>? link,
      List<Uri>? launched,
      bool launchOk = true,
    }) async {
      // Tall enough that the whole page (3 summary cards, tabs, cards) is on screen.
      tester.view.physicalSize = const Size(800, 2000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final fake = _FakeRecords(reports: reports, error: error, link: link);
      await tester.pumpWidget(
        MaterialApp(
          home: MyRecordsPage(
            key: UniqueKey(),
            initialTab: initialTab,
            recordsService: fake,
            openUrl: (uri) async {
              launched?.add(uri);
              return launchOk;
            },
            enableRealtime: false,
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
      return fake;
    }

    testWidgets('shows a Reports summary card and a Reports tab with counts', (tester) async {
      await pumpPage(tester, reports: [_report(), _report(id: 'mr2')]);

      // Summary strip: the three cards (the tab bar repeats two of the labels).
      expect(find.text('Prescriptions'), findsWidgets);
      expect(find.text('Certificates'), findsOneWidget);
      expect(find.text('Reports'), findsNWidgets(2)); // summary card + tab
      expect(find.text('2'), findsNWidgets(2)); // summary count + tab count
    });

    testWidgets('existing tabs keep their labels and still open', (tester) async {
      await pumpPage(tester, reports: [_report()]);

      expect(find.text('Medical Certificates'), findsOneWidget);
      expect(find.text('Migraine'), findsOneWidget);

      await tester.tap(find.text('Medical Certificates'));
      await tester.pump();
      expect(find.text('Viral fever'), findsWidgets);
      expect(find.text('Migraine'), findsNothing);
      expect(find.text('Blood test summary'), findsNothing);
    });

    testWidgets('the Reports tab lists reports with a PDF button', (tester) async {
      await pumpPage(tester, reports: [_report()]);

      await tester.tap(find.widgetWithText(InkWell, 'Reports').last);
      await tester.pump();

      expect(find.text('Blood test summary'), findsOneWidget);
      expect(find.text('Issued by Humancare · 05 Nov 2026 · MR-2026-0001'), findsOneWidget);
      expect(find.text('PDF'), findsOneWidget);
      expect(find.text('Voided'), findsNothing);
      expect(find.text('Migraine'), findsNothing);
    });

    testWidgets('an empty Reports tab shows the empty state', (tester) async {
      await pumpPage(tester, initialTab: 'reports');

      expect(find.text('No medical reports yet'), findsOneWidget);
      expect(find.text('Medical reports issued to you will appear here.'), findsOneWidget);
    });

    testWidgets('initialTab "reports" opens the Reports tab', (tester) async {
      await pumpPage(tester, reports: [_report()], initialTab: 'reports');

      expect(find.text('Blood test summary'), findsOneWidget);
      expect(find.text('Migraine'), findsNothing);
    });

    testWidgets('a voided report shows the badge and message, with no PDF button', (tester) async {
      await pumpPage(
        tester,
        reports: [_report(status: 'voided', doctorName: '')],
        initialTab: 'reports',
      );

      expect(find.textContaining('Blood test summary'), findsOneWidget);
      expect(find.textContaining('Voided', findRichText: true), findsOneWidget);
      expect(
        find.text('This report is no longer valid. A corrected report may be issued separately.'),
        findsOneWidget,
      );
      expect(find.text('PDF'), findsNothing);
      expect(find.text('Humancare · 05 Nov 2026 · MR-2026-0001'), findsOneWidget);
    });

    testWidgets('PDF asks for the link and opens it outside the app', (tester) async {
      final launched = <Uri>[];
      final fake = await pumpPage(
        tester,
        reports: [_report()],
        initialTab: 'reports',
        launched: launched,
      );

      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();

      expect(fake.opened, ['mr1']);
      expect(launched.single.toString(), 'https://files.test/r.pdf');
    });

    testWidgets('a refused link shows the server message', (tester) async {
      await pumpPage(
        tester,
        reports: [_report()],
        initialTab: 'reports',
        link: const ApiResult(success: false, message: 'This report has been voided.', statusCode: 403),
      );

      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();

      expect(find.text('This report has been voided.'), findsOneWidget);
    });

    testWidgets('a link that cannot be opened shows a message', (tester) async {
      await pumpPage(tester, reports: [_report()], initialTab: 'reports', launchOk: false);

      await tester.tap(find.text('PDF'));
      await tester.pumpAndSettle();

      expect(find.text('Could not open the report. Please try again.'), findsOneWidget);
    });

    testWidgets('when only reports fail, the banner shows and the other tabs still work', (tester) async {
      await pumpPage(
        tester,
        error: 'Could not load medical reports. Failed to fetch medical reports.',
      );

      expect(
        find.text('Could not load medical reports. Failed to fetch medical reports.'),
        findsOneWidget,
      );
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('Migraine'), findsOneWidget);
    });
  });
}

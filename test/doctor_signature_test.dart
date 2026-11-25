import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/models/medical_record_models.dart';
import 'package:humancare_connect/screens/my_records_screen.dart';
import 'package:humancare_connect/services/api_client.dart';
import 'package:humancare_connect/services/document_signature_service.dart';
import 'package:humancare_connect/services/medical_records_service.dart';
import 'package:humancare_connect/services/session_expired_service.dart';
import 'package:humancare_connect/services/session_logout.dart';
import 'package:humancare_connect/services/token_storage_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'support/fake_document_saver.dart';

/// A real, valid 1x1 PNG.
final Uint8List _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

http.Response _pngResponse() =>
    http.Response.bytes(_png, 200, headers: {'content-type': 'image/png'});

Map<String, dynamic> _rx({bool signed = false, String id = 'rx1'}) => {
  '_id': id,
  'diagnosis': 'Migraine',
  'doctorId': {'_id': 'd1', 'name': 'Rao', 'email': 'rao@example.com'},
  'medicines': [
    {'name': 'Paracetamol', 'dosage': '500mg', 'frequency': 'bd', 'duration': '3d'},
  ],
  'instructions': 'Rest',
  'createdAt': '2026-11-07T10:00:00.000Z',
  if (signed) 'isSigned': true,
  if (signed) 'signedAt': '2026-11-07T10:05:00.000Z',
};

Map<String, dynamic> _cert({bool signed = false, String id = 'c1'}) => {
  '_id': id,
  'diagnosis': 'Viral fever',
  'doctorId': {'_id': 'd1', 'name': 'Rao'},
  'doctorEnrollment': {'specialization': 'GP', 'qualification': 'MBBS'},
  'issuedDate': '2026-11-07',
  'createdAt': '2026-11-07T10:00:00.000Z',
  if (signed) 'isSigned': true,
  if (signed) 'signedAt': '2026-11-07T10:05:00.000Z',
};

class _FakeRecords extends MedicalRecordsService {
  _FakeRecords(this.prescriptions, this.certificates);
  final List<Map<String, dynamic>> prescriptions;
  final List<Map<String, dynamic>> certificates;

  @override
  Future<MedicalRecordsSnapshot> fetchMyRecords({bool silent = false}) async {
    return MedicalRecordsSnapshot(
      prescriptions: prescriptions.map(PrescriptionRecord.fromJson).toList(),
      certificates: certificates.map(MedicalCertificateRecord.fromJson).toList(),
    );
  }
}

class _FakeSignatures extends DocumentSignatureService {
  _FakeSignatures({this.bytes});

  Uint8List? bytes;
  final calls = <String>[];
  final _cache = <String, Uint8List>{};

  @override
  Uint8List? cached(SignedDocumentKind kind, String id) => _cache['${kind.name}:$id'];

  @override
  Future<Uint8List?> fetch(SignedDocumentKind kind, String id) async {
    calls.add('${kind.name}:$id');
    final b = bytes;
    if (b != null) _cache['${kind.name}:$id'] = b;
    return b;
  }

  @override
  Future<Uint8List?> fetchWithRetry(SignedDocumentKind kind, String id) async =>
      await fetch(kind, id) ?? await fetch(kind, id);
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
    test('isSigned / signedAt are read; older records read as unsigned', () {
      final signed = PrescriptionRecord.fromJson(_rx(signed: true));
      expect(signed.isSigned, isTrue);
      expect(signed.signedAt, isNotEmpty);

      final old = PrescriptionRecord.fromJson(_rx());
      expect(old.isSigned, isFalse);
      expect(old.signedAt, isEmpty);

      expect(MedicalCertificateRecord.fromJson(_cert(signed: true)).isSigned, isTrue);
      expect(MedicalCertificateRecord.fromJson(_cert()).isSigned, isFalse);
    });
  });

  group('ApiClient.getBytes', () {
    ApiClient clientFor(Future<http.Response> Function(http.Request) h) =>
        ApiClient(client: MockClient(h), tokenStorage: const TokenStorageService());

    test('returns the raw bytes with the auth header', () async {
      String? auth;
      final result = await clientFor((request) async {
        auth = request.headers['Authorization'];
        return _pngResponse();
      }).getBytes('/medical/my-prescriptions/rx1/signature');

      expect(result.success, isTrue);
      expect(result.bytes, _png);
      expect(auth, 'Bearer access');
    });

    test('404 is a failure with the server message', () async {
      final result = await clientFor(
        (_) async => http.Response(jsonEncode({'msg': 'Signature not found.'}), 404),
      ).getBytes('/x');

      expect(result.success, isFalse);
      expect(result.statusCode, 404);
      expect(result.message, 'Signature not found.');
    });

    test('a network error is statusCode 0, not an exception', () async {
      final result = await clientFor(
        (_) async => throw http.ClientException('offline'),
      ).getBytes('/x');

      expect(result.success, isFalse);
      expect(result.statusCode, 0);
    });

    test('an expired access token is refreshed once and the call retried',
        () async {
      final calls = <String>[];
      final result = await clientFor((request) async {
        calls.add('${request.method} ${request.url.path} ${request.headers['Authorization']}');
        if (request.url.path.endsWith('/auth/refresh')) {
          return http.Response(
            jsonEncode({'accessToken': 'fresh', 'refreshToken': 'refresh2'}),
            200,
          );
        }
        return request.headers['Authorization'] == 'Bearer fresh'
            ? _pngResponse()
            : http.Response('{}', 401);
      }).getBytes('/medical/my-prescriptions/rx1/signature');

      expect(result.success, isTrue);
      expect(result.bytes, _png);
      expect(calls, [
        'GET /api/medical/my-prescriptions/rx1/signature Bearer access',
        'POST /api/auth/refresh Bearer refresh',
        'GET /api/medical/my-prescriptions/rx1/signature Bearer fresh',
      ]);
    });

    test('a dead session still ends through the normal logout flow', () async {
      SessionLogout.shared = SessionLogout(
        httpClient: MockClient((_) async => http.Response('{}', 200)),
        deleteFcmToken: () async {},
      );
      addTearDown(() {
        SessionLogout.shared = SessionLogout();
        SessionExpiredService.instance.reset();
      });

      final result = await clientFor((_) async => http.Response('{}', 401))
          .getBytes('/x');
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(result.statusCode, 401);
      expect(SessionExpiredService.instance.isExpired, isTrue);
    });
  });

  group('DocumentSignatureService', () {
    DocumentSignatureService serviceFor(
      Future<http.Response> Function(http.Request) h,
    ) => DocumentSignatureService(
      apiClient: ApiClient(
        client: MockClient(h),
        tokenStorage: const TokenStorageService(),
      ),
    );

    test('isValidPng accepts a PNG and rejects other bodies', () {
      expect(DocumentSignatureService.isValidPng(_png), isTrue);
      expect(
        DocumentSignatureService.isValidPng(
          Uint8List.fromList(utf8.encode('<html>nope</html>')),
        ),
        isFalse,
      );
      expect(DocumentSignatureService.isValidPng(Uint8List(0)), isFalse);
      expect(
        DocumentSignatureService.isValidPng(
          Uint8List.fromList([..._png, ...List.filled(1024 * 1024, 0)]),
        ),
        isFalse,
        reason: 'over the 1 MB limit',
      );
    });

    test('uses the right paths and caches a success', () async {
      final paths = <String>[];
      final service = serviceFor((request) async {
        paths.add(request.url.path);
        return _pngResponse();
      });

      expect(await service.fetch(SignedDocumentKind.prescription, 'rx1'), _png);
      expect(await service.fetch(SignedDocumentKind.prescription, 'rx1'), _png);
      expect(await service.fetch(SignedDocumentKind.certificate, 'c1'), _png);

      expect(paths, [
        '/api/medical/my-prescriptions/rx1/signature',
        '/api/medical/my-certificates/c1/signature',
      ]);
      expect(service.cached(SignedDocumentKind.prescription, 'rx1'), _png);
    });

    test('404, non-PNG and network errors give null and are not cached',
        () async {
      var mode = 'notfound';
      var calls = 0;
      final service = serviceFor((request) async {
        calls++;
        switch (mode) {
          case 'notfound':
            return http.Response(jsonEncode({'msg': 'Signature not found.'}), 404);
          case 'html':
            return http.Response('<html></html>', 200);
          case 'offline':
            throw http.ClientException('offline');
          default:
            return _pngResponse();
        }
      });

      for (final m in ['notfound', 'html', 'offline']) {
        mode = m;
        expect(await service.fetch(SignedDocumentKind.prescription, 'rx1'), isNull);
      }
      expect(service.cached(SignedDocumentKind.prescription, 'rx1'), isNull);

      mode = 'ok';
      expect(await service.fetch(SignedDocumentKind.prescription, 'rx1'), _png);
      expect(calls, 4);
    });

    test('fetchWithRetry tries twice', () async {
      var calls = 0;
      final service = serviceFor((_) async {
        calls++;
        return calls == 1 ? http.Response('{}', 500) : _pngResponse();
      });

      expect(
        await service.fetchWithRetry(SignedDocumentKind.certificate, 'c1'),
        _png,
      );
      expect(calls, 2);
    });
  });

  group('MyRecordsPage', () {
    late FakeDocumentSaver saver;

    Future<void> pumpPage(
      WidgetTester tester, {
      required List<Map<String, dynamic>> prescriptions,
      List<Map<String, dynamic>> certificates = const [],
      required _FakeSignatures signatures,
      String initialTab = 'prescriptions',
    }) async {
      tester.view.physicalSize = const Size(900, 6000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      saver = FakeDocumentSaver();
      await tester.pumpWidget(
        MaterialApp(
          home: MyRecordsPage(
            key: UniqueKey(),
            initialTab: initialTab,
            recordsService: _FakeRecords(prescriptions, certificates),
            signatureService: signatures,
            documentSaver: saver,
            enableRealtime: false,
          ),
        ),
      );
      for (var i = 0; i < 4; i++) {
        await tester.pump();
      }
    }

    // the signature itself (the slip header's logo is an asset image)
    final signatureImage = find.byWidgetPredicate(
      (w) => w is Image && w.image is MemoryImage,
    );

    Future<void> openCard(WidgetTester tester, String title) async {
      await tester.tap(find.text(title).first);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
    }

    testWidgets('signed prescription: opening it loads the signature and shows the block',
        (tester) async {
      final signatures = _FakeSignatures(bytes: _png);
      await pumpPage(tester, prescriptions: [_rx(signed: true)], signatures: signatures);

      // nothing is requested until the card is opened
      expect(signatures.calls, isEmpty);
      await openCard(tester, 'Migraine');

      expect(signatures.calls, ['prescription:rx1']);
      expect(find.text('SIGNATURE'), findsOneWidget);
      expect(find.textContaining('Digitally signed'), findsOneWidget);
      expect(signatureImage, findsOneWidget);
    });

    testWidgets('old / unsigned prescription: no signature block, no request',
        (tester) async {
      final signatures = _FakeSignatures(bytes: _png);
      await pumpPage(tester, prescriptions: [_rx()], signatures: signatures);

      await openCard(tester, 'Migraine');

      expect(signatures.calls, isEmpty);
      expect(find.text('SIGNATURE'), findsNothing);
      expect(find.textContaining('Digitally signed'), findsNothing);
    });

    testWidgets('signed but the signature fails to load: empty area with the caption',
        (tester) async {
      final signatures = _FakeSignatures(bytes: null);
      await pumpPage(tester, prescriptions: [_rx(signed: true)], signatures: signatures);

      await openCard(tester, 'Migraine');

      expect(find.text('SIGNATURE'), findsOneWidget);
      expect(find.textContaining('Digitally signed'), findsOneWidget);
      expect(signatureImage, findsNothing);
    });

    testWidgets('certificates: signed replaces the system-generated note, unsigned keeps it',
        (tester) async {
      const note = 'This is a system-generated certificate';
      final signatures = _FakeSignatures(bytes: _png);
      await pumpPage(
        tester,
        prescriptions: const [],
        certificates: [_cert(signed: true, id: 'c1')],
        signatures: signatures,
        initialTab: 'certificates',
      );
      await openCard(tester, 'Viral fever');
      expect(find.textContaining(note), findsNothing);
      expect(find.textContaining('Digitally signed'), findsOneWidget);

      await pumpPage(
        tester,
        prescriptions: const [],
        certificates: [_cert()],
        signatures: _FakeSignatures(bytes: _png),
        initialTab: 'certificates',
      );
      await openCard(tester, 'Viral fever');
      expect(find.textContaining(note), findsOneWidget);
      expect(find.textContaining('Digitally signed'), findsNothing);
    });

    int imageCount(Uint8List pdf) =>
        RegExp('/Subtype\\s*/Image').allMatches(latin1.decode(pdf)).length;

    testWidgets('PDF of a signed prescription embeds the signature image',
        (tester) async {
      final signed = _FakeSignatures(bytes: _png);
      await pumpPage(tester, prescriptions: [_rx(signed: true)], signatures: signed);
      await tester.runAsync(() async {
        await tester.tap(find.text('PDF'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump();
      final withSignature = imageCount(saver.saved.single.$1);

      final unsigned = _FakeSignatures(bytes: _png);
      await pumpPage(tester, prescriptions: [_rx()], signatures: unsigned);
      await tester.runAsync(() async {
        await tester.tap(find.text('PDF'));
        await Future<void>.delayed(const Duration(seconds: 2));
      });
      await tester.pump();
      final without = imageCount(saver.saved.single.$1);

      // an embedded PNG is an image object plus its alpha mask
      expect(withSignature, without + 2);
      expect(unsigned.calls, isEmpty, reason: 'unsigned: no signature request');
    });

    testWidgets('signed but signature unavailable: the PDF export is blocked',
        (tester) async {
      final signatures = _FakeSignatures(bytes: null);
      await pumpPage(tester, prescriptions: [_rx(signed: true)], signatures: signatures);

      await tester.runAsync(() async {
        await tester.tap(find.text('PDF'));
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump();
      await tester.pump();

      expect(saver.saved, isEmpty, reason: 'nothing was saved');
      expect(signatures.calls.length, 2, reason: 'retried once');
      expect(find.textContaining("Couldn't load the doctor's signature"),
          findsOneWidget);
    });
  });
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:humancare_connect/models/api_result.dart';
import 'package:humancare_connect/models/payment_model.dart';
import 'package:humancare_connect/screens/pdf_viewer_screen.dart';
import 'package:humancare_connect/screens/payment_history_screen.dart';
import 'package:humancare_connect/services/document_saver.dart';
import 'package:humancare_connect/services/payment_history_service.dart';
import 'package:open_filex/open_filex.dart';

import 'support/fake_document_saver.dart';

class _FakePayments extends PaymentHistoryService {
  _FakePayments(this.link);

  final ApiResult<InvoiceDownloadLink> link;

  @override
  Future<ApiResult<PaymentHistoryResult>> fetchMyPayments({
    int page = 1,
    int limit = 20,
    bool silent = false,
  }) async {
    return ApiResult<PaymentHistoryResult>(
      success: true,
      message: '',
      data: PaymentHistoryResult.fromJson({
        'payments': [
          {
            '_id': 'p1',
            'description': 'Consultation',
            'amountCents': 5900,
            'currency': 'usd',
            'gateway': 'stripe',
            'status': 'paid',
            'paidAt': '2026-11-05T10:00:00.000Z',
            'invoice': {'invoiceNumber': 'INV-2026-0007'},
          },
        ],
        'page': 1,
        'pages': 1,
        'total': 1,
      }),
    );
  }

  @override
  Future<ApiResult<InvoiceDownloadLink>> fetchInvoiceDownloadLink(
    String paymentId, {
    bool silent = false,
  }) async => link;
}

void main() {
  group('DocumentSaver.cleanFileName', () {
    test('keeps a normal name and ends in .pdf', () {
      expect(
        DocumentSaver.cleanFileName('visit-note_HCR-2026-0001.pdf'),
        'visit-note_HCR-2026-0001.pdf',
      );
      expect(DocumentSaver.cleanFileName('invoice_INV-1'), 'invoice_INV-1.pdf');
    });

    test('replaces characters a file system rejects', () {
      expect(
        DocumentSaver.cleanFileName('a/b\\c:d*e?f"g<h>i|j.pdf'),
        'a_b_c_d_e_f_g_h_i_j.pdf',
      );
    });

    test('never returns an empty or hidden name', () {
      expect(DocumentSaver.cleanFileName(''), 'document.pdf');
      expect(DocumentSaver.cleanFileName('..pdf'), 'document.pdf');
      final traversal = DocumentSaver.cleanFileName('../../x.pdf');
      expect(traversal.contains('/'), isFalse);
      expect(traversal.startsWith('.'), isFalse);
    });
  });

  group('DocumentSaver.uniqueName', () {
    test('keeps the name when nothing has it', () async {
      expect(await DocumentSaver.uniqueName('a.pdf', (_) async => false), 'a.pdf');
    });

    test('adds (1), (2) ... and never overwrites', () async {
      final taken = {'a.pdf', 'a (1).pdf'};
      expect(
        await DocumentSaver.uniqueName('a.pdf', (n) async => taken.contains(n)),
        'a (2).pdf',
      );
    });
  });

  group('DocumentSaver.fetch', () {
    test('returns the bytes of a 200 answer and sends no login header', () async {
      http.BaseRequest? seen;
      final client = MockClient((request) async {
        seen = request;
        return http.Response.bytes([37, 80, 68, 70], 200);
      });
      final bytes = await const DocumentSaver().fetch(
        Uri.parse('https://files.test/x.pdf?sig=1'),
        client: client,
      );
      expect(bytes, Uint8List.fromList([37, 80, 68, 70]));
      expect(seen!.headers.containsKey('authorization'), isFalse);
    });

    test('throws for an expired link or an empty answer', () async {
      for (final response in [
        http.Response('expired', 403),
        http.Response('missing', 404),
        http.Response.bytes([], 200),
      ]) {
        final client = MockClient((request) async => response);
        await expectLater(
          const DocumentSaver().fetch(Uri.parse('https://files.test/x.pdf'), client: client),
          throwsA(anything),
        );
      }
    });
  });

  group('announceSaved', () {
    Future<(FakeDocumentSaver, ScaffoldMessengerState)> pump(
      WidgetTester tester,
      SavedWhere where,
    ) async {
      final saver = FakeDocumentSaver(where: where);
      final key = GlobalKey<ScaffoldMessengerState>();
      await tester.pumpWidget(
        MaterialApp(
          scaffoldMessengerKey: key,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      return (saver, key.currentState!);
    }

    testWidgets('Android: one Open action, file opens only when tapped', (tester) async {
      final (saver, messenger) = await pump(tester, SavedWhere.downloads);
      await announceSaved(
        messenger,
        saver,
        const SavedDocument(path: '/c/a.pdf', where: SavedWhere.downloads),
      );
      await tester.pump();

      expect(find.text('Saved to Downloads'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
      expect(find.text('Share'), findsNothing);
      expect(saver.opened, isEmpty);

      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.text('Open'));
      await tester.pump();
      expect(saver.opened, ['/c/a.pdf']);
    });

    testWidgets('iOS: Saved to Files and the preview opens at once', (tester) async {
      final (saver, messenger) = await pump(tester, SavedWhere.files);
      await announceSaved(
        messenger,
        saver,
        const SavedDocument(path: '/docs/a.pdf', where: SavedWhere.files),
      );
      await tester.pump();

      expect(find.text('Saved to Files'), findsOneWidget);
      expect(saver.opened, ['/docs/a.pdf']);
    });
  });

  group('the copy Open needs (media_store_plus deletes what it is given)', () {
    late Directory cache;
    late File kept;

    setUp(() async {
      cache = await Directory.systemTemp.createTemp('saver');
      kept = File('${cache.path}/visit-note_HCR-1 (1).pdf');
      await kept.writeAsString('%PDF-1.4 kept');
    });
    tearDown(() => cache.delete(recursive: true));

    test('still exists after the plugin deletes its input', () async {
      String? given;
      final result = await DocumentSaver.publishCopy(kept, (path) async {
        given = path;
        expect(await File(path).readAsString(), '%PDF-1.4 kept');
        await File(path).delete();
        return 'saved';
      });

      expect(result, 'saved');
      expect(given, isNot(kept.path));
      // the plugin names the download after the file it is given
      expect(Uri.file(given!).pathSegments.last, 'visit-note_HCR-1 (1).pdf');
      expect(await kept.exists(), isTrue);
    });

    test('a plugin that only copies leaves no spare file behind', () async {
      late String given;
      await DocumentSaver.publishCopy(kept, (path) async => given = path);
      expect(await File(given).exists(), isFalse);
      expect(await kept.exists(), isTrue);
    });

    test('a failed save keeps the file too', () async {
      await expectLater(
        DocumentSaver.publishCopy<void>(kept, (_) async => throw Exception('no')),
        throwsException,
      );
      expect(await kept.exists(), isTrue);
    });

    test('reads the saved file, or null when it is gone', () async {
      const saver = DocumentSaver();
      expect(await saver.read(kept.path), isNotEmpty);
      expect(await saver.read('${cache.path}/missing.pdf'), isNull);
    });
  });

  test('what the phone answered', () {
    expect(DocumentSaver.outcomeOf(ResultType.done), OpenOutcome.opened);
    expect(DocumentSaver.outcomeOf(ResultType.noAppToOpen), OpenOutcome.noApp);
    for (final type in [
      ResultType.fileNotFound,
      ResultType.permissionDenied,
      ResultType.error,
    ]) {
      expect(DocumentSaver.outcomeOf(type), OpenOutcome.failed);
    }
  });

  group('Open', () {
    const failed = {
      SavedWhere.downloads:
          "Couldn't open the file. You can find it in Downloads/Humancare Connect.",
      SavedWhere.files:
          "Couldn't open the file. You can find it in the Files app.",
      SavedWhere.viewOnly:
          "Couldn't open the file. Please try downloading again.",
    };

    /// Saves, taps "Open" where there is a snackbar action, and lets the
    /// result appear.
    Future<FakeDocumentSaver> open(
      WidgetTester tester,
      SavedWhere where,
      OpenOutcome outcome, {
      bool readable = true,
    }) async {
      // the viewer asks the printing plugin what the phone can do
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('net.nfet.printing'),
        (call) async => call.method == 'printingInfo'
            ? <String, Object>{'canRaster': false}
            : null,
      );
      final saver = FakeDocumentSaver(
        where: where,
        outcome: outcome,
        readable: readable,
      );
      final messenger = GlobalKey<ScaffoldMessengerState>();
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          key: UniqueKey(),
          scaffoldMessengerKey: messenger,
          navigatorKey: navigator,
          home: const Scaffold(body: SizedBox()),
        ),
      );
      await announceSaved(
        messenger.currentState!,
        saver,
        SavedDocument(path: '/cache/documents/a.pdf', where: where),
        navigator: navigator.currentState,
      );
      await tester.pump();
      if (where == SavedWhere.downloads) {
        await tester.pump(const Duration(milliseconds: 600));
        await tester.tap(find.text('Open'));
      }
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      expect(saver.opened, ['/cache/documents/a.pdf']);
      return saver;
    }

    for (final where in SavedWhere.values) {
      testWidgets('${where.name}: opened in another app, nothing more', (
        tester,
      ) async {
        await open(tester, where, OpenOutcome.opened);
        expect(find.byType(PdfViewerScreen), findsNothing);
        expect(find.text(failed[where]!), findsNothing);
      });

      for (final outcome in [OpenOutcome.noApp, OpenOutcome.failed]) {
        testWidgets('${where.name}, ${outcome.name}: the in-app viewer', (
          tester,
        ) async {
          await open(tester, where, outcome);
          final viewer = tester.widget<PdfViewerScreen>(
            find.byType(PdfViewerScreen),
          );
          expect(viewer.title, 'a.pdf');
          expect(viewer.errorText, failed[where]);
        });
      }

      testWidgets('${where.name}: nothing to show gives the message', (
        tester,
      ) async {
        await open(tester, where, OpenOutcome.failed, readable: false);
        expect(find.byType(PdfViewerScreen), findsNothing);
        // it may wait for an earlier snackbar to leave first
        final message = find.text(failed[where]!);
        for (var i = 0; i < 40 && message.evaluate().isEmpty; i++) {
          await tester.pump(const Duration(milliseconds: 200));
        }
        expect(message, findsOneWidget);
      });
    }
  });

  group('PaymentHistoryScreen invoice download', () {
    Future<FakeDocumentSaver> pumpScreen(
      WidgetTester tester, {
      required ApiResult<InvoiceDownloadLink> link,
      FakeDocumentSaver? saver,
    }) async {
      final fake = saver ?? FakeDocumentSaver();
      await tester.pumpWidget(
        MaterialApp(
          home: PaymentHistoryScreen(
            service: _FakePayments(link),
            documentSaver: fake,
          ),
        ),
      );
      await tester.pumpAndSettle();
      return fake;
    }

    ApiResult<InvoiceDownloadLink> okLink() => const ApiResult(
      success: true,
      message: '',
      data: InvoiceDownloadLink(
        url: 'https://files.test/invoice.pdf',
        invoiceNumber: 'INV-2026-0007',
      ),
    );

    testWidgets('downloads inside the app and saves invoice_<number>.pdf', (tester) async {
      final saver = await pumpScreen(tester, link: okLink());

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(saver.fetched.single.toString(), 'https://files.test/invoice.pdf');
      expect(saver.saved.single.$2, 'invoice_INV-2026-0007.pdf');
      expect(find.text('Saved to Downloads'), findsOneWidget);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('a failed download shows the invoice message', (tester) async {
      final saver = await pumpScreen(
        tester,
        link: okLink(),
        saver: FakeDocumentSaver(failFetch: true),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(
        find.text("Couldn't download invoice INV-2026-0007. Please try again."),
        findsOneWidget,
      );
      expect(saver.saved, isEmpty);
    });

    testWidgets('a refused link keeps the server message', (tester) async {
      await pumpScreen(
        tester,
        link: const ApiResult(
          success: false,
          message: 'Invoice is still being generated.',
          statusCode: 409,
        ),
      );

      await tester.tap(find.byType(OutlinedButton));
      await tester.pumpAndSettle();

      expect(find.text('Invoice is still being generated.'), findsOneWidget);
    });
  });
}

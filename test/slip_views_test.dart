import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/models/medical_record_models.dart';
import 'package:humancare_connect/widgets/slips/certificate_slip_view.dart';
import 'package:humancare_connect/widgets/slips/slip_tokens.dart';

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

const _patient = {'name': 'Asha Rao', 'gender': 'Female', 'dob': '1990-05-12'};

const _longName =
    'Amoxicillin and Potassium Clavulanate Extended Release Dispersible';

MedicalCertificateRecord _cert({bool signed = false, bool long = false}) =>
    MedicalCertificateRecord(
      id: '66f1a2b3c4d5e6f75098aa72',
      diagnosis: long ? '$_longName reaction ' * 3 : 'Viral fever',
      doctor: const DoctorSummary(name: 'Meera Nair'),
      enrollment: DoctorEnrollment(
        specialization: 'General Physician',
        qualification: 'MBBS',
        medicalRegistrationNumber: long
            ? 'TEST-Medical-License-Number-0000000000000000000'
            : 'MH-2014-55231',
        medicalCouncilName: 'Maharashtra Medical Council',
        clinicName: long ? 'The $_longName Clinic' : 'Sunrise Clinic',
        clinicAddress: '12 Park Road, Pune 411001, India',
      ),
      recommendation: long ? 'Rest at home. ' * 40 : 'Rest at home',
      restFromDate: '2026-11-23',
      restToDate: '2026-11-26',
      notes: 'Review if symptoms continue',
      issuedDate: '2026-11-23',
      isSigned: signed,
      signedAt: signed ? '2026-11-23T17:42:00.000' : '',
    );

/// The real fonts, so that "does it fit" means something.
Future<void> _loadFonts() async {
  Future<ByteData> bytes(String path) async =>
      ByteData.sublistView(await File(path).readAsBytes());
  final families = {
    kSlipFont: [
      'assets/fonts/Inter-Regular.ttf',
      'assets/fonts/Inter-Medium.ttf',
      'assets/fonts/Inter-SemiBold.ttf',
      'assets/pdf/Inter-Bold.ttf',
      'assets/pdf/Inter-BoldItalic.ttf',
    ],
    'Inter': ['assets/fonts/Inter-Regular.ttf'],
  };
  for (final entry in families.entries) {
    final loader = FontLoader(entry.key);
    for (final path in entry.value) {
      loader.addFont(bytes(path));
    }
    await loader.load();
  }
}

/// Shows [slip] [width] wide on a phone of [screen] width, with the slip's
/// images loaded.
Future<void> _show(
  WidgetTester tester,
  Widget slip, {
  required double screen,
  double? width,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(screen, 4000);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(textScale)),
          child: Scaffold(
            body: SingleChildScrollView(
              child: Center(
                child: SizedBox(width: width ?? screen, child: slip),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  final context = tester.element(find.byType(Scaffold));
  await tester.runAsync(() async {
    await precacheImage(const AssetImage(kSlipLogo), context);
    await precacheImage(const AssetImage(kSlipQr), context);
  });
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(_loadFonts);

  group('certificate', () {
    Widget view(MedicalCertificateRecord record) => CertificateSlipView(
      record: record,
      patient: _patient,
      signature: record.isSigned ? _png : null,
    );

    Rect page(WidgetTester tester) =>
        tester.getRect(find.byKey(const ValueKey('certificate page')));

    test('the scale follows the width, between half and full size', () {
      expect(CertificateSlipView.scaleFor(200), 0.5);
      expect(CertificateSlipView.scaleFor(397), 0.5);
      expect(CertificateSlipView.scaleFor(595.5), 0.75);
      expect(CertificateSlipView.scaleFor(794), 1);
      expect(CertificateSlipView.scaleFor(1200), 1);
    });

    for (final screen in [320.0, 360.0, 412.0]) {
      testWidgets('on a ${screen.toInt()} phone: half size, scrolls sideways', (
        tester,
      ) async {
        await _show(
          tester,
          view(_cert(signed: true)),
          screen: screen,
          width: screen - 56,
        );

        expect(tester.takeException(), isNull);
        expect(page(tester).width, 397);
        // A4: 794 x 1123, halved.
        expect(page(tester).height, closeTo(561.5, 0.5));
        final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last);
        expect(
          scroll.position.maxScrollExtent,
          closeTo(397 - (screen - 56 - 16), 0.5),
        );
      });
    }

    testWidgets('with room to spare it shrinks to fit and does not scroll', (
      tester,
    ) async {
      await _show(tester, view(_cert()), screen: 700, width: 600);

      expect(page(tester).width, 576); // 600 less the 12 px padding each side
      final scroll = tester.state<ScrollableState>(find.byType(Scrollable).last);
      expect(scroll.position.maxScrollExtent, 0);
    });

    testWidgets('signed shows the signature instead of the note', (
      tester,
    ) async {
      await _show(tester, view(_cert(signed: true)), screen: 360, width: 304);
      expect(find.text('Signature'), findsOneWidget);
      expect(find.textContaining('system-generated'), findsNothing);

      await _show(tester, view(_cert()), screen: 360, width: 304);
      expect(find.text('Signature'), findsNothing);
      expect(find.textContaining('system-generated'), findsOneWidget);
    });

    testWidgets('the web texts', (tester) async {
      await _show(tester, view(_cert()), screen: 360, width: 304);

      for (final text in [
        'GLOBAL HEALTH PASSPORT',
        'Medical Certificate',
        'HC-CERT-5098AA72',
        'Issued: Nov 23, 2026',
        'Patient Name :',
        'Date of Issue :',
        'Age / Sex :',
        'Date of Birth :',
        'May 12, 1990',
        'FIELD',
        'DETAILS',
        'Diagnosis / Condition',
        'Recommendation',
        'Rest Period',
        'Nov 23, 2026 to Nov 26, 2026',
        'Additional Notes',
        'Dr. Meera Nair',
        'General Physician · MBBS',
        'Maharashtra Medical Council',
      ]) {
        expect(find.text(text), findsOneWidget, reason: text);
      }
    });

    testWidgets('long values stay inside the page', (tester) async {
      for (final signed in [true, false]) {
        await _show(
          tester,
          view(_cert(signed: signed, long: true)),
          screen: 320,
          width: 264,
          textScale: 1.5,
        );

        expect(tester.takeException(), isNull);
        expect(page(tester).width, 397);
        // The page grows instead of cutting text off.
        expect(page(tester).height, greaterThan(561.5));
      }
    });
  });
}

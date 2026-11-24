import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/models/medical_record_models.dart';
import 'package:humancare_connect/models/visit_note_models.dart';
import 'package:humancare_connect/pdf/slip_pdf.dart';

/// Set SLIP_PDF_OUT to a folder to also save the PDFs for a visual check
/// against the web PDFs; SLIP_PDF_SIG can point to a signature PNG.
final String? _out = Platform.environment['SLIP_PDF_OUT'];

Uint8List? _signature() {
  final path = Platform.environment['SLIP_PDF_SIG'];
  if (path == null || !File(path).existsSync()) return null;
  return File(path).readAsBytesSync();
}

void _save(String name, Uint8List bytes) {
  final dir = _out;
  if (dir == null) return;
  Directory(dir).createSync(recursive: true);
  File('$dir/$name.pdf').writeAsBytesSync(bytes);
}

int _pages(Uint8List bytes) =>
    RegExp(r'/Type\s*/Page\b').allMatches(String.fromCharCodes(bytes)).length;

bool _isPdf(Uint8List bytes) => String.fromCharCodes(bytes.take(5)) == '%PDF-';

const _patient = {'name': 'Satish Dalvi Technical Team'};
final _signedAt = DateTime(2026, 11, 23, 17, 42).toIso8601String();
final _created = DateTime(2026, 11, 23, 10).toIso8601String();

PrescriptionRecord _rx({int medicines = 1, bool signed = true}) =>
    PrescriptionRecord(
      id: 'rx1',
      diagnosis: 'gsdgrsg',
      doctor: const DoctorSummary(id: 'd1', name: 'Test Doctor'),
      enrollment: const DoctorEnrollment(
        specialization: 'Gastroenterology',
        medicalRegistrationNumber: 'TEST-Medical License Number',
      ),
      medicines: [
        for (var i = 0; i < medicines; i++)
          const PrescriptionMedicine(
            name: 'sgeg',
            dosage: '578',
            frequency: 'Morning (01), Afternoon (01), Night (01) - After Food',
            duration: '852',
          ),
      ],
      instructions: 'sgbv',
      createdAt: _created,
      isSigned: signed,
      signedAt: signed ? _signedAt : '',
    );

MedicalCertificateRecord _cert({bool signed = true, String notes = 'dvsv'}) =>
    MedicalCertificateRecord(
      id: '66aa5098aa72',
      diagnosis: 'dfvd',
      doctor: const DoctorSummary(id: 'd1', name: 'Test Doctor'),
      enrollment: const DoctorEnrollment(
        specialization: 'Gastroenterology',
        qualification: 'NP',
        clinicName: 'TEST-Clinic / Practice Name',
        clinicAddress: 'TEST-Clinic Address',
        medicalRegistrationNumber: 'TEST-Medical License Number',
        medicalCouncilName: 'TEST-Medical Council Name',
      ),
      recommendation: 'dsvsv',
      restFromDate: '2026-11-12',
      restToDate: '2026-11-03',
      notes: notes,
      issuedDate: '2026-11-23',
      createdAt: _created,
      isSigned: signed,
      signedAt: signed ? _signedAt : '',
    );

VisitNoteReport _note({
  String symptoms = 'sCd',
  String plan = 'dvdsvs',
  String note = 'dvsdavv',
}) => VisitNoteReport.fromJson({
  '_id': 'r1',
  'reportNumber': 'HCR-2026-0005',
  'patient': {'name': 'Satish Dalvi Technical Team'},
  'consultation': {
    'date': '2026-12-04',
    'time': '10:30 AM',
    'mode': 'Video Consultation',
  },
  'physician': {
    'name': 'Test Doctor',
    'registrationNumber': 'TEST-Medical License Number',
    'speciality': 'Gastroenterology',
    'country': 'CA',
  },
  'symptoms': symptoms,
  'clinicalFindings': 'dvdsv',
  'plan': plan,
  'note': note,
  'signedAt': _signedAt,
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SlipPdf prescription', () {
    test('one medicine fits on one page', () async {
      final bytes = await SlipPdf.prescription(
        _rx(),
        patient: _patient,
        signature: _signature(),
        country: 'Canada',
      );
      _save('rx', bytes);
      expect(_isPdf(bytes), isTrue);
      expect(_pages(bytes), 1);
    });

    test('25 medicines flow onto more pages', () async {
      final bytes = await SlipPdf.prescription(
        _rx(medicines: 25),
        patient: _patient,
        signature: _signature(),
        country: 'Canada',
      );
      _save('rx_25', bytes);
      expect(_pages(bytes), greaterThan(1));
    });

    test('unsigned, no signature image and empty fields still build', () async {
      final bytes = await SlipPdf.prescription(
        const PrescriptionRecord(id: '', diagnosis: ''),
        patient: const {},
      );
      _save('rx_empty', bytes);
      expect(_isPdf(bytes), isTrue);
      final signedNoImage = await SlipPdf.prescription(
        _rx(),
        patient: _patient,
      );
      expect(_isPdf(signedNoImage), isTrue);
    });
  });

  group('SlipPdf certificate', () {
    test('signed certificate is one page', () async {
      final bytes = await SlipPdf.certificate(
        _cert(),
        patient: _patient,
        signature: _signature(),
      );
      _save('cert', bytes);
      expect(_pages(bytes), 1);
    });

    test('unsigned certificate, empty fields and very long notes build', () async {
      final unsigned = await SlipPdf.certificate(
        _cert(signed: false),
        patient: _patient,
      );
      _save('cert_unsigned', unsigned);
      expect(_isPdf(unsigned), isTrue);

      final empty = await SlipPdf.certificate(
        const MedicalCertificateRecord(id: '', diagnosis: ''),
        patient: const {},
      );
      expect(_isPdf(empty), isTrue);

      final long = await SlipPdf.certificate(
        _cert(notes: List.filled(300, 'A long line of notes.').join('\n')),
        patient: _patient,
        signature: _signature(),
      );
      _save('cert_long', long);
      expect(_pages(long), greaterThan(1));
    });
  });

  group('SlipPdf visit note', () {
    test('short note is one page', () async {
      final bytes = await SlipPdf.visitNote(
        _note(),
        signature: _signature(),
        country: 'Canada',
      );
      _save('visit', bytes);
      expect(_pages(bytes), 1);
    });

    test('long symptoms flow onto more pages', () async {
      final longText = List.filled(
        300,
        'Symptom line with some words.',
      ).join('\n');
      final bytes = await SlipPdf.visitNote(
        _note(symptoms: longText, plan: longText),
        signature: _signature(),
        country: 'Canada',
      );
      _save('visit_long', bytes);
      expect(_pages(bytes), greaterThan(1));
    });

    test('amendments are listed', () async {
      final report = VisitNoteReport.fromJson({
        '_id': 'r1',
        'reportNumber': 'HCR-2026-0005',
        'patient': {'name': 'Satish Dalvi Technical Team'},
        'physician': {'name': 'Test Doctor', 'country': 'CA'},
        'symptoms': 'sCd',
        'clinicalFindings': 'dvdsv',
        'plan': 'dvdsvs',
        'signedAt': _signedAt,
        'amendments': [
          {
            '_id': 'a1',
            'authorName': 'Dr Rao',
            'reason': 'Typo',
            'text': 'Fixed the dose',
            'createdAt': '2026-11-24T09:00:00.000Z',
          },
          {
            '_id': 'a2',
            'authorName': 'Dr Rao',
            'reason': 'Missing detail',
            'text': 'Added the follow-up plan',
            'createdAt': '2026-11-25T09:00:00.000Z',
          },
        ],
      });
      final bytes = await SlipPdf.visitNote(report, signature: _signature());
      _save('visit_amend', bytes);
      expect(_pages(bytes), 1);
    });

    test('missing signature still builds', () async {
      final bytes = await SlipPdf.visitNote(_note());
      expect(_isPdf(bytes), isTrue);
    });
  });
}

import 'dart:typed_data';

import 'package:flutter/material.dart' show Color;
import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../config/app_design_system.dart';
import '../models/visit_note_models.dart';

/// Builds the Visit Note PDF a patient downloads. Same content as the web
/// `VisitNoteSlip` PDF (banner, patient and consultation details, symptoms,
/// consultation details, physician details with signature, amendments), laid
/// out in the same header / banner / footer style as the app's prescription
/// and certificate PDFs. A long note flows onto further pages.
class VisitNotePdf {
  const VisitNotePdf._();

  static PdfColor _pdfColor(Color color) => PdfColor.fromInt(color.toARGB32());

  static PdfColor get _brand => _pdfColor(AppColors.primary);
  static PdfColor get _brandDeep => _pdfColor(AppColors.primaryDeep);
  static PdfColor get _brandTint =>
      _pdfColor(AppColors.primary.withValues(alpha: 0.06));

  /// `signature` is the doctor's PNG, or `null` — the PDF is still created
  /// without it (web: "a missing signature image must not block the download").
  /// `countryName` is the physician's country already resolved to a name.
  static Future<Uint8List> build(
    VisitNoteReport report, {
    Uint8List? signature,
    String? countryName,
    pw.MemoryImage? logo,
  }) async {
    final logoImage = logo ?? await _loadLogo();
    final pdf = pw.Document();
    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        footer: (_) => _footer(),
        build: (_) => _body(
          report,
          logoImage,
          signature,
          (countryName ?? '').trim().isNotEmpty
              ? countryName!.trim()
              : report.physicianCountry,
        ),
      ),
    );
    return pdf.save();
  }

  static Future<pw.MemoryImage?> _loadLogo() async {
    try {
      final bytes = await rootBundle.load('assets/logo-2.png');
      return pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  static String _dash(String value) => value.trim().isEmpty ? '-' : value;

  static List<pw.Widget> _body(
    VisitNoteReport report,
    pw.MemoryImage? logo,
    Uint8List? signature,
    String country,
  ) {
    final when = report.consultationWhen.replaceAll('·', '-');
    return [
      _header(logo),
      _banner(report),
      pw.SizedBox(height: 14),
      _infoRow(
        ['Patient Name', report.patientName],
        ['Gender', report.patientGender],
      ),
      _infoRow(
        ['DOB', report.patientDob],
        ['Age', report.patientAge],
      ),
      _infoRow(
        ['Consultation', when],
        ['Mode', report.modeLabel],
      ),
      pw.SizedBox(height: 8),
      ..._section('Symptoms', report.symptoms),
      pw.SizedBox(height: 6),
      pw.Text(
        'Consultation Details',
        style: pw.TextStyle(
          fontSize: 13,
          color: _brandDeep,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      pw.SizedBox(height: 4),
      ..._section('Clinical Findings', report.clinicalFindings),
      ..._section('Plan / Treatment', report.plan),
      if (report.note.trim().isNotEmpty) ..._section('Note', report.note),
      pw.SizedBox(height: 8),
      _physicianBox(report, country, signature),
      if (report.amendments.isNotEmpty) ..._amendments(report),
    ];
  }

  static pw.Widget _header(pw.MemoryImage? logo) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: pw.BoxDecoration(
        border: pw.Border(bottom: pw.BorderSide(color: _brandTint, width: 1.5)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          if (logo != null)
            pw.Image(logo, height: 42)
          else
            pw.Text(
              'Humancare Connect',
              style: pw.TextStyle(
                fontSize: 18,
                fontWeight: pw.FontWeight.bold,
                color: _brandDeep,
              ),
            ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Global Health Passport',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: _brand,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(width: 44, height: 3, color: _brand),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _banner(VisitNoteReport report) {
    return pw.Container(
      color: _brandTint,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Text(
              'Visit Note',
              style: pw.TextStyle(
                fontSize: 13,
                color: _brandDeep,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Report ID : ${report.reportNumber}',
                style: pw.TextStyle(
                  fontSize: 10,
                  color: _brandDeep,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                'Date : ${formatVisitNoteDate(report.signedAt)}',
                style: const pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.grey600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static pw.Widget _infoRow(List<String> left, List<String> right) {
    pw.Widget cell(List<String> field) => pw.Expanded(
      child: pw.Padding(
        padding: const pw.EdgeInsets.only(right: 12, bottom: 6),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              '${field[0]} : ',
              style: pw.TextStyle(
                fontSize: 10,
                color: _brandDeep,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
            pw.Expanded(
              child: pw.Text(
                _dash(field[1]),
                style: const pw.TextStyle(fontSize: 10),
              ),
            ),
          ],
        ),
      ),
    );

    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [cell(left), cell(right)],
    );
  }

  /// A label bar followed by the text. Each piece is its own top-level item
  /// so that a very long note can continue onto the next page.
  static List<pw.Widget> _section(String label, String text) {
    return [
      pw.Container(
        width: double.infinity,
        color: _brandTint,
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        margin: const pw.EdgeInsets.only(top: 6),
        child: pw.Text(
          label,
          style: pw.TextStyle(
            fontSize: 10,
            color: _brandDeep,
            fontWeight: pw.FontWeight.bold,
          ),
        ),
      ),
      pw.Paragraph(
        text: _dash(text),
        style: const pw.TextStyle(fontSize: 10, lineSpacing: 2),
        margin: const pw.EdgeInsets.fromLTRB(10, 5, 10, 0),
      ),
    ];
  }

  static pw.Widget _physicianBox(
    VisitNoteReport report,
    String country,
    Uint8List? signature,
  ) {
    pw.Widget field(String label, String value) => pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 5),
      child: pw.Row(
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 10, color: PdfColors.grey700),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Text(
              _dash(value),
              textAlign: pw.TextAlign.right,
              style: pw.TextStyle(
                fontSize: 10,
                color: _brandDeep,
                fontWeight: pw.FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    final signedAt = formatVisitNoteDateTime(report.signedAt);
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(border: pw.Border.all(color: _brandTint)),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'PHYSICIAN DETAILS',
            style: pw.TextStyle(
              fontSize: 9,
              color: _brand,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          field("Doctor's Name", report.physicianName),
          field('Medical Reg No', report.physicianRegistrationNumber),
          field('Speciality', report.physicianSpeciality),
          field('Country', country),
          pw.SizedBox(height: 4),
          pw.Text(
            'Signature',
            style: pw.TextStyle(
              fontSize: 9,
              color: _brandDeep,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 3),
          pw.SizedBox(
            height: 44,
            width: 160,
            child: signature == null
                ? pw.SizedBox()
                : pw.Image(
                    pw.MemoryImage(signature),
                    fit: pw.BoxFit.contain,
                    alignment: pw.Alignment.centerLeft,
                  ),
          ),
          pw.SizedBox(height: 3),
          pw.Text(
            signedAt.isEmpty
                ? 'Digitally signed'
                : 'Digitally signed - $signedAt',
            style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _amendments(VisitNoteReport report) {
    return [
      pw.SizedBox(height: 10),
      pw.Text(
        'AMENDMENTS',
        style: pw.TextStyle(
          fontSize: 11,
          color: _brandDeep,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
      for (var i = 0; i < report.amendments.length; i++) ...[
        pw.SizedBox(height: 6),
        pw.Text(
          'Amendment ${i + 1} - ${report.amendments[i].authorName} - '
          '${formatVisitNoteDateTime(report.amendments[i].createdAt)}',
          style: const pw.TextStyle(fontSize: 9, color: PdfColors.grey600),
        ),
        ..._section('Reason', report.amendments[i].reason),
        ..._section('Correction', report.amendments[i].text),
      ],
    ];
  }

  static pw.Widget _footer() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: _brandDeep,
      child: pw.Text(
        'This document is generated electronically and is valid without a physical signature.  support@humancareconnect.co',
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
      ),
    );
  }
}

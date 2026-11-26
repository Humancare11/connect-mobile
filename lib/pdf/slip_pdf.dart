import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/medical_record_models.dart';
import '../models/visit_note_models.dart';

/// Draws the Prescription, Medical Certificate and Visit Note PDFs so they look
/// like the web PDFs (`RxSlip.jsx` classic layout, `MedicalCertificateSlip.jsx`,
/// `VisitNoteSlip.jsx` on the `uat` branch).
///
/// The web slips are laid out in CSS pixels (800 px wide for the prescription,
/// 794 px for the other two) and then scaled onto an A4 page. Every size below
/// is therefore written as the web's pixel value and multiplied by [_Scale.k].
class SlipPdf {
  const SlipPdf._();

  // ── Public builders ───────────────────────────────────────────────────────

  /// `patient` is the signed-in user's stored profile (name, gender, dob).
  static Future<Uint8List> prescription(
    PrescriptionRecord record, {
    required Map<String, String> patient,
    Uint8List? signature,
    String country = '',
  }) async {
    final kit = await _Kit.load(_Scale.rx, spaceWords: true);
    final k = kit.s;
    final children = <pw.Widget>[
      ..._rxHeader(kit),
      ..._rxTitle(kit, _fmtIn(record.createdAt)),
      ..._rxPatientPanel(kit, patient),
      _padded(
        k,
        44,
        pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(0, k.px(1.2), 0, k.px(10)),
          child: _rxFieldRow(kit, 'Diagnosis :', record.diagnosis),
        ),
      ),
      _padded(
        k,
        44,
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(4)),
          child: kit.tx(
            'Medications',
            style: kit.t(16, w: 700, color: _navy),
          ),
        ),
      ),
      _padded(
        k,
        44,
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(10)),
          child: kit.tx(
            'Rx',
            style: kit.t(22, w: 700, italic: true, color: _rxAccent),
          ),
        ),
      ),
      ..._rxMedicineTable(kit, record.medicines),
      pw.SizedBox(height: k.px(26)),
      _padded(
        k,
        44,
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(11.2)),
          child: _rxFieldRow(kit, 'Advice :', record.instructions),
        ),
      ),
      _padded(
        k,
        44,
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(12)),
          // The backend has no allergy field, so this stays blank like the web.
          child: _rxFieldRow(kit, 'Allergy :', ''),
        ),
      ),
      _padded(
        k,
        44,
        // No bottom gap: the web's 12 px margin collapses into the 22 px
        // margin above the PHYSICIAN DETAILS tab.
        pw.Padding(
          padding: pw.EdgeInsets.zero,
          child: _rxFieldRow(
            kit,
            'Follow-up Date :',
            _fmtIn(record.followUpDate),
          ),
        ),
      ),
      ..._rxPhysician(kit, record, country, signature),
    ];
    // The web prescription is not a fixed-height page: its footer follows the
    // content (the web's gap, measured against its PDF) instead of sitting at the bottom of the paper.
    return _render(kit, children, _rxFooter(kit), gap: k.px(17.6), pin: false);
  }

  static Future<Uint8List> certificate(
    MedicalCertificateRecord record, {
    required Map<String, String> patient,
    Uint8List? signature,
  }) async {
    final kit = await _Kit.load(_Scale.cert);
    final k = kit.s;

    final patientName = (patient['name'] ?? '').trim();
    final dob = (patient['dob'] ?? '').trim();
    final age = _ageYears(dob);
    final gender = (patient['gender'] ?? '').trim();
    final ageSex = [
      if (age.isNotEmpty) '$age yrs',
      if (gender.isNotEmpty) gender,
    ].join(' / ');
    final issued = _fmtUs(
      record.issuedDate.isNotEmpty ? record.issuedDate : record.createdAt,
    );
    final id = record.id.trim();
    final certId = id.isEmpty
        ? '—'
        : 'HC-CERT-${(id.length > 8 ? id.substring(id.length - 8) : id).toUpperCase()}';
    final diagnosis = record.diagnosis.trim();

    final rows = <List<String>>[
      ['Diagnosis / Condition', diagnosis.isEmpty ? '—' : diagnosis],
      if (record.recommendation.trim().isNotEmpty)
        ['Recommendation', record.recommendation],
      if (record.restFromDate.isNotEmpty || record.restToDate.isNotEmpty)
        [
          'Rest Period',
          _restPeriod(record.restFromDate, record.restToDate),
        ],
      if (record.notes.trim().isNotEmpty) ['Additional Notes', record.notes],
    ];

    final children = <pw.Widget>[
      ..._certHeader(kit),
      _certBand(
        kit,
        title: 'Medical Certificate',
        subtitle: diagnosis.isEmpty ? null : diagnosis,
        subtitleLabel: 'Reason:',
        right1: certId,
        right1Bold: true,
        right2: 'Issued: $issued',
      ),
      _padded(
        k,
        40,
        pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(0, k.px(20), 0, k.px(16)),
          child: _fieldGrid(kit, [
            ['Patient Name', patientName],
            ['Date of Issue', issued],
            ['Age / Sex', ageSex.isEmpty ? '—' : ageSex],
            if (dob.isNotEmpty) ['Date of Birth', _fmtUs(dob)],
          ]),
        ),
      ),
      _gradientDivider(kit),
      pw.SizedBox(height: k.px(18)),
      _padded(
        k,
        40,
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(16)),
          child: _accentBox(
            kit,
            kit.rich(
              text: pw.TextSpan(
                style: kit.t(13, color: _body, height: 1.7),
                children: [
                  const pw.TextSpan(text: 'This is to certify that '),
                  pw.TextSpan(
                    text: patientName.isEmpty ? 'the patient' : patientName,
                    style: kit.t(13, w: 700, color: _navy, height: 1.7),
                  ),
                  pw.TextSpan(text: ageSex.isEmpty ? ', ' : ', $ageSex, '),
                  const pw.TextSpan(
                    text: 'has been examined and is suffering from ',
                  ),
                  pw.TextSpan(
                    text: diagnosis.isEmpty ? '—' : diagnosis,
                    style: kit.t(13, w: 700, color: _body, height: 1.7),
                  ),
                  const pw.TextSpan(text: '.'),
                ],
              ),
            ),
          ),
        ),
      ),
      ..._detailTable(kit, rows, header: const ['Field', 'Details']),
      pw.SizedBox(height: k.px(16)),
      _padded(k, 40, _doctorCard(kit, record, signature)),
      pw.SizedBox(height: k.px(10)),
      _padded(k, 40, _validityNote(kit)),
    ];
    return _render(kit, children, _certFooter(kit), gap: k.px(10));
  }

  static Future<Uint8List> visitNote(
    VisitNoteReport report, {
    Uint8List? signature,
    String country = '',
  }) async {
    final kit = await _Kit.load(_Scale.cert, spaceWords: true);
    final k = kit.s;

    final detailRows = <List<String>>[
      ['Clinical Findings :', report.clinicalFindings],
      ['Plan / Treatment :', report.plan],
      if (report.note.trim().isNotEmpty) ['Note :', report.note],
    ];
    final physicianFields = <List<String>>[
      ["Doctor's Name", report.physicianName],
      ['Medical Reg No', report.physicianRegistrationNumber],
      ['Speciality', report.physicianSpeciality],
      ['Country', country],
    ];
    final dob = report.patientDob.trim();
    // The stored value, as the web shows it (e.g. 1990-05-12).
    final dobText = dob.isEmpty ? '—' : dob;

    final children = <pw.Widget>[
      // A touch less letter spacing: the pdf package sets Inter a little
      // wider than the browser, so this keeps the web's line width.
      ..._certHeader(kit, taglineSpacing: 1.3),
      _certBand(
        kit,
        title: 'Visit Note',
        right1: 'Report ID : ${report.reportNumber}',
        right2: 'Date : ${_fmtIn(report.signedAt)}',
      ),
      _padded(
        k,
        40,
        pw.Padding(
          padding: pw.EdgeInsets.fromLTRB(0, k.px(21.6), 0, k.px(16)),
          child: _fieldGrid(kit, [
            ['Patient Name', report.patientName],
            ['Gender', _orDash(report.patientGender)],
            ['DOB', dobText],
            ['Age', _orDash(report.patientAge)],
            ['Consultation', _orDash(report.consultationWhen)],
            ['Mode', report.modeLabel],
          ]),
        ),
      ),
      _gradientDivider(kit),
      pw.SizedBox(height: k.px(18)),
      for (final entry in _chunks(report.symptoms).asMap().entries)
        _padded(
          k,
          40,
          pw.Padding(
            padding: pw.EdgeInsets.only(bottom: k.px(16.8)),
            child: _accentBox(
              kit,
              kit.rich(
                text: pw.TextSpan(
                  style: kit.t(13, color: _body, height: 1.7),
                  children: [
                    if (entry.key == 0)
                      pw.TextSpan(
                        text: 'Symptoms : ',
                        style: kit.t(13, w: 700, color: _navy, height: 1.7),
                      ),
                    pw.TextSpan(text: entry.value),
                  ],
                ),
              ),
            ),
          ),
        ),
      _padded(
        k,
        40,
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(8.8)),
          child: kit.tx(
            'Consultation Details',
            style: kit.t(14, w: 700, color: _navy),
          ),
        ),
      ),
      ..._detailTable(kit, detailRows, rowPadding: 10.2),
      pw.SizedBox(height: k.px(16.8)),
      _padded(
        k,
        40,
        _physicianCard(kit, physicianFields, signature, report.signedAt),
      ),
      if (report.amendments.isNotEmpty) ..._amendments(kit, report),
    ];
    return _render(kit, children, _certFooter(kit), gap: k.px(10));
  }

  // ── Page ──────────────────────────────────────────────────────────────────

  /// Space kept free at the bottom of every page that is not the last one. The
  /// footer on the last page is drawn over this space so it reaches the edge.
  static const double _bottomGutter = 18;

  static pw.Document _document(_Kit kit, List<pw.Widget> children) {
    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        pageTheme: pw.PageTheme(
          pageFormat: PdfPageFormat.a4,
          margin: pw.EdgeInsets.zero,
          theme: pw.ThemeData.withFont(base: kit.regular, bold: kit.bold),
        ),
        // Later pages get a little air above the content (web: 24 px).
        header: (context) => context.pageNumber > 1
            ? pw.SizedBox(height: kit.s.px(24))
            : pw.SizedBox(),
        footer: (_) => pw.SizedBox(height: _bottomGutter),
        build: (_) => children,
      ),
    );
    return doc;
  }

  /// The web draws the footer once, at the bottom of the last page. The page
  /// layout cannot say how much room is left on the last page, so the content
  /// is laid out once with a probe at its end, and then again with a spacer
  /// that pushes the footer to the bottom edge (or onto a new page when the
  /// footer does not fit under the content).
  static Future<Uint8List> _render(
    _Kit kit,
    List<pw.Widget> body,
    pw.Widget footer, {
    required double gap,
    bool pin = true,
  }) async {
    if (!pin) {
      return _document(kit, [...body, pw.SizedBox(height: gap), footer]).save();
    }
    final probe = _Probe(footer);
    await _document(kit, [...body, probe]).save();

    final footerHeight = probe.footerHeight;
    final room = probe.contentBottom - footerHeight - gap;
    final pageHeight = PdfPageFormat.a4.height;
    final spacer = room >= 0.5
        ? room + gap
        : pageHeight - kit.s.px(24) - footerHeight;

    return _document(kit, [
      ...body,
      if (room < 0.5) pw.NewPage(),
      pw.SizedBox(height: spacer),
      _FooterBox(footer, bleed: _bottomGutter),
    ]).save();
  }

  // ── Prescription (classic layout) ─────────────────────────────────────────

  static List<pw.Widget> _rxHeader(_Kit kit) {
    final k = kit.s;
    return [
      pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(k.px(44), k.px(28), k.px(44), k.px(16)),
        child: pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Image(kit.logo, width: k.px(150)),
        ),
      ),
      pw.Row(
        children: [
          pw.Expanded(
            flex: 58,
            child: pw.Container(
              height: k.px(4),
              decoration: pw.BoxDecoration(
                color: _navy,
                borderRadius: pw.BorderRadius.only(
                  topRight: pw.Radius.circular(k.px(3)),
                  bottomRight: pw.Radius.circular(k.px(3)),
                ),
              ),
            ),
          ),
          pw.Expanded(
            flex: 42,
            child: pw.Container(height: k.px(2), color: _rxAccent),
          ),
        ],
      ),
    ];
  }

  static List<pw.Widget> _rxTitle(_Kit kit, String date) {
    final k = kit.s;
    return [
      pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(k.px(44), k.px(22), k.px(44), k.px(18)),
        child: pw.Stack(
          alignment: pw.Alignment.center,
          children: [
            pw.Center(
              child: kit.tx(
                'prescription',
                style: kit.t(21, w: 700, color: _navy, ls: 0.2),
              ),
            ),
            pw.Positioned(
              right: k.px(4),
              top: k.px(2),
              child: kit.tx(
                'Date : $date',
                style: kit.t(12.5, w: 500, color: _rxMuted),
              ),
            ),
          ],
        ),
      ),
    ];
  }

  static List<pw.Widget> _rxPatientPanel(
    _Kit kit,
    Map<String, String> patient,
  ) {
    final k = kit.s;
    final name = (patient['name'] ?? '').trim();
    final dob = (patient['dob'] ?? '').trim();
    final gender = (patient['gender'] ?? '').trim();
    final age = _ageYears(dob);

    pw.Widget cell(String label, String value, {bool last = false}) {
      return pw.Expanded(
        child: pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: k.px(18),
            vertical: k.px(12),
          ),
          decoration: pw.BoxDecoration(
            border: last
                ? null
                : pw.Border(
                    right: pw.BorderSide(color: _rxLine, width: k.px(1.5)),
                  ),
          ),
          child: _rxLabelValue(kit, label, value),
        ),
      );
    }

    return [
      _padded(
        k,
        44,
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(26)),
          child: pw.Container(
            decoration: pw.BoxDecoration(
              color: _rxPanel,
              borderRadius: pw.BorderRadius.circular(k.px(10)),
              border: pw.Border.all(color: _rxLine, width: k.px(1.5)),
            ),
            child: pw.Column(
              children: [
                pw.Container(
                  width: double.infinity,
                  padding: pw.EdgeInsets.symmetric(
                    horizontal: k.px(18),
                    vertical: k.px(12),
                  ),
                  decoration: pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(color: _rxLine, width: k.px(1.5)),
                    ),
                  ),
                  child: _rxLabelValue(kit, 'Patient Name', name),
                ),
                pw.Row(
                  children: [
                    cell('Gender', _orDash(gender)),
                    // The stored value, as the web shows it.
                    cell('DOB', _orDash(dob)),
                    cell('Age', _orDash(age), last: true),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ];
  }

  static pw.Widget _rxLabelValue(_Kit kit, String label, String value) {
    return kit.rich(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '${label.toUpperCase()}  ',
            style: kit.t(12, w: 600, color: _rxMuted, ls: 0.4),
          ),
          pw.TextSpan(
            text: value,
            style: kit.t(14, w: 500, color: _rxInk),
          ),
        ],
      ),
    );
  }

  static pw.Widget _rxFieldRow(_Kit kit, String label, String value) {
    final k = kit.s;
    return kit.rich(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: label,
            style: kit.t(13, w: 700, color: _navy),
          ),
          pw.WidgetSpan(child: pw.SizedBox(width: k.px(6))),
          pw.TextSpan(text: value, style: kit.t(13, color: _rxInk)),
        ],
      ),
    );
  }

  /// Header, one widget per medicine row, so a long list flows onto further
  /// pages between rows. The outer corners are rounded on the header and the
  /// last row.
  static List<pw.Widget> _rxMedicineTable(
    _Kit kit,
    List<PrescriptionMedicine> medicines,
  ) {
    final k = kit.s;
    final radius = pw.Radius.circular(k.px(10));
    final widths = <int, pw.TableColumnWidth>{
      0: const pw.FlexColumnWidth(57),
      1: const pw.FlexColumnWidth(200),
      2: const pw.FlexColumnWidth(100),
      3: const pw.FlexColumnWidth(240),
      4: const pw.FlexColumnWidth(116),
    };
    final list = medicines.isEmpty
        ? const [PrescriptionMedicine()]
        : medicines;

    pw.Widget th(String text) => pw.Padding(
          padding: pw.EdgeInsets.symmetric(
            horizontal: k.px(10),
            vertical: k.px(11),
          ),
          child: kit.tx(
            text.toUpperCase(),
            textAlign: pw.TextAlign.center,
            style: kit.t(11.5, w: 600, color: PdfColors.white, ls: 0.4),
          ),
        );

    pw.Widget td(String text, {bool left = false, int w = 400, double size = 13}) =>
        pw.Padding(
          padding: pw.EdgeInsets.symmetric(
            horizontal: k.px(10),
            vertical: k.px(11),
          ),
          child: kit.tx(
            text,
            textAlign: left ? pw.TextAlign.left : pw.TextAlign.center,
            style: kit.t(size, w: w, color: _rxInk, height: size == 12 ? 1.5 : null),
          ),
        );

    final out = <pw.Widget>[
      _padded(
        k,
        44,
        pw.Container(
          decoration: pw.BoxDecoration(
            color: _navy,
            borderRadius: pw.BorderRadius.only(topLeft: radius, topRight: radius),
          ),
          child: pw.Table(
            columnWidths: widths,
            defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
            children: [
              pw.TableRow(
                children: [
                  th('Sr. No'),
                  th('Medicine'),
                  th('Dose'),
                  th('Timing'),
                  th('No. of Days'),
                ],
              ),
            ],
          ),
        ),
      ),
    ];

    for (var i = 0; i < list.length; i++) {
      final m = list[i];
      final isLast = i == list.length - 1;
      final fill = i.isOdd ? _rxPanel : PdfColors.white;
      out.add(
        _padded(
          k,
          44,
          pw.Container(
            constraints: pw.BoxConstraints(minHeight: k.px(46)),
            decoration: pw.BoxDecoration(
              color: fill,
              borderRadius: isLast
                  ? pw.BorderRadius.only(bottomLeft: radius, bottomRight: radius)
                  : null,
              border: isLast
                  ? pw.Border.all(color: _rxLine, width: k.px(1.5))
                  : pw.Border(
                      left: pw.BorderSide(color: _rxLine, width: k.px(1.5)),
                      right: pw.BorderSide(color: _rxLine, width: k.px(1.5)),
                      top: pw.BorderSide(color: _rxLine, width: k.px(1)),
                    ),
            ),
            child: pw.Table(
              columnWidths: widths,
              defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
              border: pw.TableBorder(
                verticalInside: pw.BorderSide(color: _rxLine, width: k.px(1)),
              ),
              children: [
                pw.TableRow(
                  children: [
                    td('${i + 1}'),
                    td(m.name, left: true, w: 500),
                    td(m.dosage),
                    td(m.frequency, size: 12),
                    td(m.duration),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  static List<pw.Widget> _rxPhysician(
    _Kit kit,
    PrescriptionRecord record,
    String country,
    Uint8List? signature,
  ) {
    final k = kit.s;
    final enrollment = record.enrollment;
    final doctorName = record.doctor.name;

    pw.Widget field(String label, String value) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            kit.tx(
              label.toUpperCase(),
              style: kit.t(12, w: 600, color: _rxMuted, ls: 0.4),
            ),
            // Web: 2 px label margin plus the field's 2 px gap.
            pw.SizedBox(height: k.px(4)),
            kit.tx(value, style: kit.t(14, w: 500, color: _rxInk)),
          ],
        );

    pw.Widget pair(pw.Widget a, pw.Widget b) => pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(13)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: a),
              pw.SizedBox(width: k.px(24)),
              pw.Expanded(child: b),
            ],
          ),
        );

    final signatureField = record.isSigned
        ? _signatureBlock(
            kit,
            signature,
            record.signedAt,
            labelStyle: kit.t(12, w: 600, color: _rxMuted, ls: 0.4),
            labelText: 'SIGNATURE',
            labelGap: 5.6,
          )
        : pw.SizedBox();

    return [
      pw.SizedBox(height: k.px(22.8)),
      _padded(
        k,
        44,
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.SizedBox(
            width: k.px(198),
            height: k.px(32),
            child: pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.CustomPaint(
                    painter: (canvas, size) {
                      // Navy tab with the right edge cut at an angle
                      // (web clip-path: 0 0, 100% 0, 90% 100%, 0 100%).
                      canvas
                        ..setFillColor(_navy)
                        ..moveTo(0, 0)
                        ..lineTo(size.x * 0.9, 0)
                        ..lineTo(size.x, size.y)
                        ..lineTo(0, size.y)
                        ..closePath()
                        ..fillPath();
                    },
                  ),
                ),
                pw.Positioned(
                  left: k.px(22),
                  top: 0,
                  bottom: 0,
                  child: pw.Center(
                    child: kit.tx(
                      'PHYSICIAN DETAILS',
                      style: kit.t(13, w: 700, color: PdfColors.white, ls: 0.4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      _padded(k, 44, pw.Container(height: k.px(2), color: _rxAccent)),
      pw.SizedBox(height: k.px(22.4)),
      _padded(
        k,
        44,
        pw.Column(
          children: [
            pair(
              field("Doctor's Name", doctorName),
              field('Medical Reg No', enrollment.medicalRegistrationNumber),
            ),
            pair(
              field('Speciality', enrollment.specialization),
              field('Date', _fmtIn(record.createdAt)),
            ),
            pair(field('Country', country), signatureField),
          ],
        ),
      ),
    ];
  }

  static pw.Widget _rxFooter(_Kit kit) {
    final k = kit.s;
    return pw.Column(
      children: [
        pw.Row(
          children: [
            pw.Expanded(
              flex: 42,
              child: pw.Container(height: k.px(2), color: _rxAccent),
            ),
            pw.Expanded(
              flex: 58,
              child: pw.Container(
                height: k.px(4),
                decoration: pw.BoxDecoration(
                  color: _navy,
                  borderRadius: pw.BorderRadius.only(
                    topLeft: pw.Radius.circular(k.px(3)),
                    bottomLeft: pw.Radius.circular(k.px(3)),
                  ),
                ),
              ),
            ),
          ],
        ),
        _footerBody(kit, topBorder: null),
      ],
    );
  }

  // ── Certificate / Visit Note shared pieces ────────────────────────────────

  static List<pw.Widget> _certHeader(_Kit kit, {double taglineSpacing = 1.5}) {
    final k = kit.s;
    return [
      pw.Container(
        height: k.px(6),
        decoration: const pw.BoxDecoration(
          gradient: pw.LinearGradient(
            begin: pw.Alignment.centerLeft,
            end: pw.Alignment.centerRight,
            colors: [_navyDark, _navy, _accent],
            stops: [0, 0.6, 1],
          ),
        ),
      ),
      pw.Container(
        padding: pw.EdgeInsets.fromLTRB(k.px(40), k.px(18), k.px(40), k.px(16)),
        decoration: pw.BoxDecoration(
          border: pw.Border(
            bottom: pw.BorderSide(color: _light, width: k.px(2)),
          ),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Image(kit.logo, height: k.px(68)),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                kit.tx(
                  'GLOBAL HEALTH PASSPORT',
                  style: kit.t(11, w: 700, color: _navy, ls: taglineSpacing),
                ),
                pw.SizedBox(height: k.px(4)),
                pw.Container(
                  width: k.px(48),
                  height: k.px(4),
                  decoration: pw.BoxDecoration(
                    color: _navy,
                    borderRadius: pw.BorderRadius.circular(k.px(2)),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  static pw.Widget _certBand(
    _Kit kit, {
    required String title,
    String? subtitle,
    String subtitleLabel = '',
    required String right1,
    bool right1Bold = false,
    required String right2,
  }) {
    final k = kit.s;
    return pw.Container(
      padding: pw.EdgeInsets.symmetric(horizontal: k.px(40), vertical: k.px(10)),
      decoration: pw.BoxDecoration(
        color: _light,
        border: pw.Border(
          bottom: pw.BorderSide(color: _border, width: k.px(1)),
        ),
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                kit.tx(title, style: kit.t(13, w: 700, color: _navy)),
                if (subtitle != null) ...[
                  pw.SizedBox(height: k.px(2)),
                  kit.rich(
                    text: pw.TextSpan(
                      children: [
                        pw.TextSpan(
                          text: '$subtitleLabel ',
                          style: kit.t(12, w: 700, color: _muted),
                        ),
                        pw.TextSpan(
                          text: subtitle,
                          style: kit.t(12, color: _muted),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              kit.tx(
                right1,
                style: right1Bold
                    ? kit.t(11, w: 600, color: _navy)
                    : kit.t(11, color: _muted),
              ),
              kit.tx(right2, style: kit.t(11, color: _muted)),
            ],
          ),
        ],
      ),
    );
  }

  /// The label / underlined value pairs, two per row.
  static pw.Widget _fieldGrid(_Kit kit, List<List<String>> fields) {
    final k = kit.s;
    pw.Widget one(List<String> f) => pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.end,
          children: [
            kit.tx(
              '${f[0]} :',
              style: kit.t(12, w: 700, color: _navy, ls: 0.3),
            ),
            pw.SizedBox(width: k.px(6)),
            pw.Expanded(
              child: pw.Container(
                padding: pw.EdgeInsets.only(bottom: k.px(2)),
                decoration: pw.BoxDecoration(
                  border: pw.Border(
                    bottom: pw.BorderSide(color: _border, width: k.px(1.2)),
                  ),
                ),
                child: kit.tx(
                  f[1].isEmpty ? ' ' : f[1],
                  style: kit.t(13, color: _body),
                ),
              ),
            ),
          ],
        );

    final rows = <pw.Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      rows.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(12)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Expanded(child: one(fields[i])),
              pw.SizedBox(width: k.px(48)),
              pw.Expanded(
                child: i + 1 < fields.length
                    ? one(fields[i + 1])
                    : pw.SizedBox(),
              ),
            ],
          ),
        ),
      );
    }
    return pw.Padding(
      // The last row's gap is not part of the design.
      padding: pw.EdgeInsets.only(bottom: -k.px(12)),
      child: pw.Column(children: rows),
    );
  }

  static pw.Widget _gradientDivider(_Kit kit) {
    final k = kit.s;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(horizontal: k.px(40)),
      child: pw.Container(
        height: k.px(1),
        decoration: const pw.BoxDecoration(
          gradient: pw.LinearGradient(
            begin: pw.Alignment.centerLeft,
            end: pw.Alignment.centerRight,
            colors: [_navy, PdfColors.white],
          ),
        ),
      ),
    );
  }

  /// Soft box with a navy bar on the left (web: Diagnosis / Symptoms /
  /// "This is to certify" box).
  static pw.Widget _accentBox(_Kit kit, pw.Widget child) {
    final k = kit.s;
    final r = k.px(6);
    return pw.Stack(
      children: [
        pw.Container(
          width: double.infinity,
          padding: pw.EdgeInsets.fromLTRB(
            k.px(4 + 12),
            k.px(14),
            k.px(16),
            k.px(14),
          ),
          decoration: pw.BoxDecoration(
            color: _soft,
            border: pw.Border.all(color: _border, width: k.px(1)),
            borderRadius: pw.BorderRadius.circular(r),
          ),
          child: child,
        ),
        pw.Positioned(
          left: 0,
          top: 0,
          bottom: 0,
          child: pw.Container(
            width: k.px(4),
            decoration: pw.BoxDecoration(
              color: _navy,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(r),
                bottomLeft: pw.Radius.circular(r),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Two-column table (label | value). `header` adds the navy FIELD / DETAILS
  /// row. Long values are cut into several rows so one row never has to be
  /// taller than a page.
  /// One widget per table row (each padded to the page margins), so a long
  /// table flows onto further pages between rows.
  static List<pw.Widget> _detailTable(
    _Kit kit,
    List<List<String>> rows, {
    List<String>? header,
    double rowPadding = 10,
  }) {
    final k = kit.s;
    var rowIndex = 0;

    // Borders are drawn per cell: neighbours share one line.
    pw.Widget cell(
      int col,
      String text,
      pw.TextStyle style,
      PdfColor fill, {
      PdfColor? edge,
      double? vertical,
    }) {
      final side = pw.BorderSide(color: edge ?? _border, width: k.px(1));
      return pw.Container(
        padding: pw.EdgeInsets.symmetric(
          horizontal: k.px(16),
          vertical: k.px(vertical ?? rowPadding),
        ),
        decoration: pw.BoxDecoration(
          color: fill,
          border: pw.Border(
            left: col == 0 ? side : pw.BorderSide.none,
            right: side,
            bottom: side,
            top: rowIndex == 0 ? side : pw.BorderSide.none,
          ),
        ),
        child: kit.tx(text, style: style),
      );
    }

    pw.Widget oneRow(List<pw.Widget> cells) => _padded(
      k,
      40,
      pw.Table(
        columnWidths: const {
          0: pw.FlexColumnWidth(30),
          1: pw.FlexColumnWidth(70),
        },
        defaultVerticalAlignment: pw.TableCellVerticalAlignment.full,
        children: [pw.TableRow(children: cells)],
      ),
    );

    final out = <pw.Widget>[];
    if (header != null) {
      final style = kit.t(12, w: 700, color: PdfColors.white, ls: 0.5);
      out.add(
        oneRow([
          cell(0, header[0].toUpperCase(), style, _navy, edge: _navy, vertical: 9),
          cell(1, header[1].toUpperCase(), style, _navy, edge: _navy, vertical: 9),
        ]),
      );
      rowIndex++;
    }
    var shade = 0;
    for (final row in rows) {
      final parts = _chunks(row[1]);
      for (var p = 0; p < parts.length; p++) {
        final fill = shade.isOdd ? _soft : PdfColors.white;
        out.add(
          oneRow([
            cell(0, p == 0 ? row[0] : '', kit.t(12, w: 700, color: _navy), fill),
            cell(1, parts[p], kit.t(13, color: _body), fill),
          ]),
        );
        rowIndex++;
      }
      shade++;
    }
    return out;
  }

  static pw.Widget _doctorCard(
    _Kit kit,
    MedicalCertificateRecord record,
    Uint8List? signature,
  ) {
    final k = kit.s;
    final e = record.enrollment;
    final name = record.doctor.name.trim().isEmpty ? '—' : record.doctor.name;
    final initial = name.isEmpty ? '' : name.substring(0, 1).toUpperCase();
    final sub = [e.specialization, e.qualification]
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    final clinicName = e.clinicName.trim().isEmpty
        ? 'Humancare Connect'
        : e.clinicName;
    final clinicAddress = e.clinicAddress.trim().isEmpty
        ? _address
        : e.clinicAddress;
    final r = k.px(8);

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: k.px(1)),
        borderRadius: pw.BorderRadius.circular(r),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: k.px(16),
              vertical: k.px(9),
            ),
            decoration: pw.BoxDecoration(
              color: _light,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(r),
                topRight: pw.Radius.circular(r),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                pw.Container(
                  width: k.px(32),
                  height: k.px(32),
                  alignment: pw.Alignment.center,
                  decoration: const pw.BoxDecoration(
                    color: _navy,
                    shape: pw.BoxShape.circle,
                  ),
                  child: kit.tx(
                    initial,
                    style: kit.t(14, w: 700, color: PdfColors.white),
                  ),
                ),
                pw.SizedBox(width: k.px(10)),
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Row(
                        children: [
                          kit.tx(
                            'Dr. $name',
                            style: kit.t(13, w: 700, color: _navy),
                          ),
                          pw.SizedBox(width: k.px(5)),
                          pw.SvgImage(
                            svg: _tickSvg,
                            width: k.px(17),
                            height: k.px(17),
                          ),
                        ],
                      ),
                      if (sub.isNotEmpty)
                        kit.tx(sub, style: kit.t(11, color: _muted)),
                    ],
                  ),
                ),
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.end,
                  children: [
                    if (e.medicalRegistrationNumber.trim().isNotEmpty)
                      kit.rich(
                        text: pw.TextSpan(
                          children: [
                            pw.TextSpan(
                              text: 'Reg. No: ',
                              style: kit.t(11, color: _muted),
                            ),
                            pw.TextSpan(
                              text: e.medicalRegistrationNumber,
                              style: kit.t(11, w: 700, color: _navy),
                            ),
                          ],
                        ),
                      ),
                    if (e.medicalCouncilName.trim().isNotEmpty)
                      kit.tx(
                        e.medicalCouncilName,
                        style: kit.t(10, color: _muted),
                      ),
                  ],
                ),
              ],
            ),
          ),
          pw.Container(height: k.px(1), color: _border),
          pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: k.px(16),
              vertical: k.px(14),
            ),
            decoration: pw.BoxDecoration(
              color: _soft,
              borderRadius: pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(r),
                bottomRight: pw.Radius.circular(r),
              ),
            ),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      kit.tx(
                        clinicName,
                        style: kit.t(12, w: 600, color: _body, height: 1.7),
                      ),
                      kit.tx(
                        clinicAddress,
                        style: kit.t(12, color: _muted, height: 1.7),
                      ),
                    ],
                  ),
                ),
                pw.SizedBox(width: k.px(20)),
                if (record.isSigned)
                  _signatureBlock(kit, signature, record.signedAt)
                else
                  pw.SizedBox(
                    width: k.px(220),
                    child: kit.tx(
                      'This is a system-generated certificate and does not '
                      'require a signature or stamp.',
                      textAlign: pw.TextAlign.center,
                      style: kit.t(11, color: _muted, height: 1.6),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static pw.Widget _validityNote(_Kit kit) {
    final k = kit.s;
    final style = kit.t(11, color: _noteText, height: 1.5);
    return pw.Container(
      width: double.infinity,
      padding: pw.EdgeInsets.symmetric(horizontal: k.px(16), vertical: k.px(7)),
      decoration: pw.BoxDecoration(
        color: _noteBg,
        border: pw.Border.all(color: _noteBorder, width: k.px(1)),
        borderRadius: pw.BorderRadius.circular(k.px(6)),
      ),
      child: kit.rich(
        text: pw.TextSpan(
          style: style,
          children: [
            pw.TextSpan(
              text: 'Note:',
              style: kit.t(11, w: 700, color: _noteText, height: 1.5),
            ),
            const pw.TextSpan(
              text: ' This certificate is issued based on the medical '
                  'examination conducted via Humancare Connect telehealth '
                  'platform. It is valid as an official medical document for '
                  'the purpose stated above.',
            ),
          ],
        ),
      ),
    );
  }

  static pw.Widget _physicianCard(
    _Kit kit,
    List<List<String>> fields,
    Uint8List? signature,
    String signedAt,
  ) {
    final k = kit.s;
    final r = k.px(8);

    pw.Widget field(List<String> f) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            kit.tx(f[0], style: kit.t(12, w: 700, color: _navy)),
            pw.SizedBox(height: k.px(1.2)),
            kit.tx(f[1], style: kit.t(13, color: _body)),
          ],
        );

    final rows = <pw.Widget>[];
    for (var i = 0; i < fields.length; i += 2) {
      rows.add(
        pw.Padding(
          padding: pw.EdgeInsets.only(bottom: k.px(11.2)),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(child: field(fields[i])),
              pw.SizedBox(width: k.px(24)),
              pw.Expanded(
                child: i + 1 < fields.length
                    ? field(fields[i + 1])
                    : pw.SizedBox(),
              ),
            ],
          ),
        ),
      );
    }

    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: _border, width: k.px(1)),
        borderRadius: pw.BorderRadius.circular(r),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: k.px(16),
              vertical: k.px(9),
            ),
            decoration: pw.BoxDecoration(
              color: _light,
              borderRadius: pw.BorderRadius.only(
                topLeft: pw.Radius.circular(r),
                topRight: pw.Radius.circular(r),
              ),
            ),
            child: kit.tx(
              'PHYSICIAN DETAILS',
              style: kit.t(13, w: 700, color: _navy, ls: 0.4),
            ),
          ),
          pw.Container(height: k.px(1), color: _border),
          pw.Container(
            padding: pw.EdgeInsets.fromLTRB(
              k.px(16),
              k.px(13.2),
              k.px(16),
              k.px(15.6),
            ),
            decoration: pw.BoxDecoration(
              color: _soft,
              borderRadius: pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(r),
                bottomRight: pw.Radius.circular(r),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                ...rows,
                _signatureBlock(kit, signature, signedAt, captionGap: 3.2),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static List<pw.Widget> _amendments(_Kit kit, VisitNoteReport report) {
    final k = kit.s;
    final r = k.px(8);
    final border = pw.BorderSide(color: _border, width: k.px(1));
    final list = report.amendments;
    final out = <pw.Widget>[
      pw.SizedBox(height: k.px(16)),
      _padded(
        k,
        40,
        pw.Container(
          width: double.infinity,
          padding: pw.EdgeInsets.symmetric(
            horizontal: k.px(16),
            vertical: k.px(9),
          ),
          decoration: pw.BoxDecoration(
            color: _light,
            border: pw.Border.all(color: _border, width: k.px(1)),
            borderRadius: pw.BorderRadius.only(
              topLeft: pw.Radius.circular(r),
              topRight: pw.Radius.circular(r),
            ),
          ),
          child: kit.tx(
            'AMENDMENTS',
            style: kit.t(13, w: 700, color: _navy, ls: 0.4),
          ),
        ),
      ),
    ];
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      final isLast = i == list.length - 1;
      final when = formatVisitNoteDateTime(a.createdAt);
      out.add(
        _padded(
          k,
          40,
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: k.px(16),
              vertical: k.px(12),
            ),
            decoration: pw.BoxDecoration(
              color: i.isOdd ? _soft : PdfColors.white,
              border: isLast
                  ? pw.Border.all(color: _border, width: k.px(1))
                  : pw.Border(left: border, right: border, top: border),
              borderRadius: isLast
                  ? pw.BorderRadius.only(
                      bottomLeft: pw.Radius.circular(r),
                      bottomRight: pw.Radius.circular(r),
                    )
                  : null,
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                kit.tx(
                  'Amendment ${i + 1} · ${a.authorName} · $when',
                  style: kit.t(11, color: _muted),
                ),
                pw.SizedBox(height: k.px(4)),
                kit.rich(
                  text: pw.TextSpan(
                    style: kit.t(13, color: _body, height: 1.6),
                    children: [
                      pw.TextSpan(
                        text: 'Reason : ',
                        style: kit.t(13, w: 700, color: _navy, height: 1.6),
                      ),
                      pw.TextSpan(text: _clip(a.reason)),
                    ],
                  ),
                ),
                kit.rich(
                  text: pw.TextSpan(
                    style: kit.t(13, color: _body, height: 1.6),
                    children: [
                      pw.TextSpan(
                        text: 'Correction : ',
                        style: kit.t(13, w: 700, color: _navy, height: 1.6),
                      ),
                      pw.TextSpan(text: _clip(a.text)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return out;
  }

  static pw.Widget _certFooter(_Kit kit) {
    final k = kit.s;
    return _footerBody(
      kit,
      topBorder: pw.Border(
        top: pw.BorderSide(color: _accent, width: k.px(3)),
      ),
    );
  }

  // ── Footer & signature ────────────────────────────────────────────────────

  static pw.Widget _footerBody(_Kit kit, {pw.Border? topBorder}) {
    final k = kit.s;
    final isRx = k == _Scale.rx;
    final textColor = isRx ? _rxMuted : _footMuted;
    final iconColor = '#12296B';

    pw.Widget line(String icon, String text) => pw.Row(
          mainAxisSize: pw.MainAxisSize.min,
          children: [
            pw.SvgImage(
              svg: _iconSvg(icon, iconColor),
              width: k.px(16),
              height: k.px(16),
            ),
            pw.SizedBox(width: k.px(7)),
            kit.tx(text, style: kit.t(13, color: textColor, height: 1.9)),
          ],
        );

    return pw.Container(
      padding: pw.EdgeInsets.fromLTRB(k.px(30), k.px(10), k.px(30), k.px(10)),
      decoration: pw.BoxDecoration(
        color: _rxPanel,
        border: topBorder,
        // The web prescription is a rounded card.
        borderRadius: isRx
            ? pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(k.px(14)),
                bottomRight: pw.Radius.circular(k.px(14)),
              )
            : null,
      ),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Container(
            width: k.px(100),
            height: k.px(100),
            padding: pw.EdgeInsets.all(k.px(4)),
            decoration: pw.BoxDecoration(
              color: PdfColors.white,
              borderRadius: pw.BorderRadius.circular(k.px(6)),
              border: pw.Border.all(color: _rxLine, width: k.px(1)),
            ),
            child: pw.Image(kit.qr, fit: pw.BoxFit.contain),
          ),
          pw.Padding(
            padding: pw.EdgeInsets.symmetric(horizontal: k.px(20)),
            child: pw.Column(
              mainAxisSize: pw.MainAxisSize.min,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                line('phone', _phone),
                line('email', _email),
                line('location', _address),
              ],
            ),
          ),
          pw.Opacity(
            opacity: 0.85,
            child: pw.Image(kit.logo, height: k.px(100)),
          ),
        ],
      ),
    );
  }

  static pw.Widget _signatureBlock(
    _Kit kit,
    Uint8List? signature,
    String signedAt, {
    pw.TextStyle? labelStyle,
    String labelText = 'Signature',
    double labelGap = 4,
    double captionGap = 4,
  }) {
    final k = kit.s;
    final when = _signedWhen(signedAt);
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      mainAxisSize: pw.MainAxisSize.min,
      children: [
        kit.tx(
          labelText,
          style: labelStyle ?? kit.t(12, w: 700, color: _navy),
        ),
        pw.SizedBox(height: k.px(labelGap)),
        pw.SizedBox(
          height: k.px(56),
          width: k.px(220),
          child: signature == null
              ? pw.SizedBox()
              : pw.Image(
                  pw.MemoryImage(signature),
                  fit: pw.BoxFit.contain,
                  alignment: pw.Alignment.centerLeft,
                ),
        ),
        pw.SizedBox(height: k.px(captionGap)),
        kit.tx(
          when.isEmpty ? 'Digitally signed' : 'Digitally signed · $when',
          style: kit.t(11, color: _isRxScale(k) ? _rxMuted : _muted),
        ),
      ],
    );
  }

  static bool _isRxScale(_Scale s) => s == _Scale.rx;

  // ── Helpers ───────────────────────────────────────────────────────────────

  static pw.Widget _padded(_Scale k, double sidePx, pw.Widget child) =>
      pw.Padding(
        padding: pw.EdgeInsets.symmetric(horizontal: k.px(sidePx)),
        child: child,
      );

  static String _orDash(String value) => value.trim().isEmpty ? '—' : value;

  /// Web `fmtDate` (en-IN): "23 Nov 2026".
  static String _fmtIn(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return DateFormat('dd MMM yyyy', 'en_US').format(date.toLocal());
  }

  /// Certificate `fmtDate` (en-US, 2-digit day): "Nov 23, 2026".
  static String _fmtUs(String? value) {
    final raw = (value ?? '').trim();
    if (raw.isEmpty) return '—';
    final date = DateTime.tryParse(raw);
    if (date == null) return raw;
    return DateFormat('MMM dd, yyyy', 'en_US').format(date.toLocal());
  }

  static String _signedWhen(String signedAt) {
    final raw = signedAt.trim();
    if (raw.isEmpty) return '';
    final date = DateTime.tryParse(raw);
    if (date == null) return '';
    final local = date.toLocal();
    return '${DateFormat('dd MMM yyyy', 'en_US').format(local)} '
        '${DateFormat('hh:mm a', 'en_US').format(local)}';
  }

  static String _restPeriod(String from, String to) {
    if (from.isNotEmpty && to.isNotEmpty) {
      return '${_fmtUs(from)} to ${_fmtUs(to)}';
    }
    if (from.isNotEmpty) return 'From ${_fmtUs(from)}';
    return 'Until ${_fmtUs(to)}';
  }

  /// Whole years, or '' when unknown or under one (web: `calcAge`, 0 is blank).
  static String _ageYears(String dob) {
    final birth = DateTime.tryParse(dob.trim());
    if (birth == null) return '';
    final now = DateTime.now();
    var age = now.year - birth.year;
    if (now.month < birth.month ||
        (now.month == birth.month && now.day < birth.day)) {
      age -= 1;
    }
    return age > 0 ? '$age' : '';
  }

  /// Cuts long text into pieces a page can hold. Short text comes back as one
  /// piece. Cuts fall on line breaks, else on spaces.
  static List<String> _chunks(
    String text, {
    int maxChars = 1500,
    int maxLines = 20,
  }) {
    if (text.length <= maxChars && '\n'.allMatches(text).length < maxLines) {
      return [text];
    }
    final out = <String>[];
    var current = StringBuffer();
    void flush() {
      if (current.isNotEmpty) out.add(current.toString());
      current = StringBuffer();
    }

    for (final line in text.split('\n')) {
      var rest = line;
      while (rest.length > maxChars) {
        var cut = rest.lastIndexOf(' ', maxChars);
        if (cut <= 0) cut = maxChars;
        if (current.length + cut > maxChars) flush();
        current.writeln(rest.substring(0, cut));
        rest = rest.substring(cut).trimLeft();
      }
      if (current.length + rest.length + 1 > maxChars ||
          '\n'.allMatches(current.toString()).length >= maxLines) {
        flush();
      }
      current.writeln(rest);
    }
    flush();
    return out.map((s) => s.trimRight()).toList();
  }

  static String _clip(String text) => text;

  // ── Constants (hex values from the web slip) ──────────────────────────────

  static const PdfColor _navy = PdfColor.fromInt(0xFF12296B);
  static const PdfColor _navyDark = PdfColor.fromInt(0xFF0C1D4F);
  static const PdfColor _accent = PdfColor.fromInt(0xFF1E63D6);
  static const PdfColor _light = PdfColor.fromInt(0xFFEEF1F8);
  static const PdfColor _soft = PdfColor.fromInt(0xFFF6F8FC);
  static const PdfColor _border = PdfColor.fromInt(0xFFD9DDE6);
  static const PdfColor _muted = PdfColor.fromInt(0xFF7A8194);
  static const PdfColor _body = PdfColor.fromInt(0xFF1F2433);
  static const PdfColor _footMuted = PdfColor.fromInt(0xFF667085);
  static const PdfColor _noteBg = PdfColor.fromInt(0xFFFFFBEB);
  static const PdfColor _noteBorder = PdfColor.fromInt(0xFFFDE68A);
  static const PdfColor _noteText = PdfColor.fromInt(0xFF92400E);

  static const PdfColor _rxAccent = PdfColor.fromInt(0xFF4A9FE0);
  static const PdfColor _rxInk = PdfColor.fromInt(0xFF1C2230);
  static const PdfColor _rxMuted = PdfColor.fromInt(0xFF667085);
  static const PdfColor _rxLine = PdfColor.fromInt(0xFFDDE2EA);
  static const PdfColor _rxPanel = PdfColor.fromInt(0xFFF7F9FC);

  static const String _phone = '+1 (302) 303-9993';
  static const String _email = 'support@humancareconnect.co';
  static const String _address =
      '4 Peddlers Row #1091 Newark, DE 19702, United States';

  // Icon paths copied from the web's SlipContactIcon.jsx.
  static const Map<String, String> _iconPaths = {
    'phone':
        'M6.6 10.8a15.1 15.1 0 0 0 6.6 6.6l2.2-2.2a1 1 0 0 1 1-.25c1.1.37 2.3.57 3.6.57a1 1 0 0 1 1 1V20a1 1 0 0 1-1 1C10.6 21 3 13.4 3 4a1 1 0 0 1 1-1h3.5a1 1 0 0 1 1 1c0 1.25.2 2.45.57 3.57a1 1 0 0 1-.25 1z',
    'email':
        'M20 4H4a2 2 0 0 0-2 2v12a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V6a2 2 0 0 0-2-2zm0 4-8 5-8-5V6l8 5 8-5z',
    'location':
        'M12 2a7 7 0 0 0-7 7c0 5.25 7 13 7 13s7-7.75 7-13a7 7 0 0 0-7-7zm0 9.5A2.5 2.5 0 1 1 12 6.5a2.5 2.5 0 0 1 0 5z',
  };

  static String _iconSvg(String name, String color) =>
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<path fill="$color" d="${_iconPaths[name]}"/></svg>';

  // Verified tick from MedicalCertificateSlip.jsx.
  static const String _tickSvg =
      '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
      '<path fill="#1E63D6" d="M12 1.5l2.6 1.9 3.2-.1 1 3.1 2.6 1.9-1 3.1 1 3.1-2.6 1.9-1 3.1-3.2-.1L12 22.5l-2.6-1.9-3.2.1-1-3.1-2.6-1.9 1-3.1-1-3.1 2.6-1.9 1-3.1 3.2.1z"/>'
      '<path fill="none" stroke="#FFFFFF" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M7.8 12.3l2.8 2.8 5.6-5.8"/>'
      '</svg>';
}

/// CSS pixel → PDF point factor. The web fits its slip width onto A4 width.
class _Scale {
  const _Scale._(this.k);
  final double k;

  /// Prescription slip: 800 px wide.
  static const rx = _Scale._(595.28 / 800);

  /// Certificate and Visit Note slips: 794 px wide.
  static const cert = _Scale._(595.28 / 794);

  double px(double v) => v * k;
}

/// Records, while the document is laid out, how high the footer is and where
/// the content on the last page ends (distance from the page bottom).
class _Probe extends pw.Widget {
  _Probe(this.footer);

  final pw.Widget footer;
  double footerHeight = 0;
  double contentBottom = 0;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    footer.layout(
      context,
      pw.BoxConstraints(
        minWidth: constraints.maxWidth,
        maxWidth: constraints.maxWidth,
      ),
      parentUsesSize: true,
    );
    footerHeight = footer.box!.height;
    box = PdfRect(0, 0, constraints.maxWidth, 0);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    contentBottom = box!.bottom;
  }
}

/// The footer, `bleed` shorter than it looks: it paints over the page's bottom
/// gutter so it reaches the edge of the paper.
class _FooterBox extends pw.SingleChildWidget {
  _FooterBox(pw.Widget child, {this.bleed = 0}) : super(child: child);

  final double bleed;

  @override
  void layout(
    pw.Context context,
    pw.BoxConstraints constraints, {
    bool parentUsesSize = false,
  }) {
    final width = constraints.maxWidth;
    child!.layout(
      context,
      pw.BoxConstraints(minWidth: width, maxWidth: width),
      parentUsesSize: true,
    );
    final childHeight = child!.box!.height;
    box = PdfRect(0, 0, width, childHeight - bleed);
    child!.box = PdfRect(0, -bleed, width, childHeight);
  }

  @override
  void paint(pw.Context context) {
    super.paint(context);
    paintChild(context);
  }
}

/// Fonts and images shared by the three documents.
class _Kit {
  _Kit({
    required this.s,
    required this.regular,
    required this.medium,
    required this.semi,
    required this.bold,
    required this.boldItalic,
    required this.logo,
    required this.qr,
    required this.spaceWords,
  });

  final _Scale s;
  final bool spaceWords;
  final pw.Font regular;
  final pw.Font medium;
  final pw.Font semi;
  final pw.Font bold;
  final pw.Font boldItalic;
  final pw.MemoryImage logo;
  final pw.MemoryImage qr;

  static Future<_Kit> load(_Scale scale, {bool spaceWords = false}) async {
    Future<pw.Font> font(String path) async =>
        pw.Font.ttf(await rootBundle.load(path));
    Future<pw.MemoryImage> image(String path) async =>
        pw.MemoryImage((await rootBundle.load(path)).buffer.asUint8List());

    final fonts = await Future.wait([
      font('assets/fonts/Inter-Regular.ttf'),
      font('assets/fonts/Inter-Medium.ttf'),
      font('assets/fonts/Inter-SemiBold.ttf'),
      font('assets/pdf/Inter-Bold.ttf'),
      font('assets/pdf/Inter-BoldItalic.ttf'),
    ]);
    final images = await Future.wait([
      image('assets/pdf/prescription-logo.png'),
      image('assets/pdf/footer-qr.png'),
    ]);
    return _Kit(
      s: scale,
      spaceWords: spaceWords,
      regular: fonts[0],
      medium: fonts[1],
      semi: fonts[2],
      bold: fonts[3],
      boldItalic: fonts[4],
      logo: images[0],
      qr: images[1],
    );
  }

  /// Text style with the web's pixel size and CSS weight (400/500/600/700).
  pw.TextStyle t(
    double px, {
    int w = 400,
    bool italic = false,
    PdfColor color = PdfColors.black,
    double ls = 0,
    double? height,
  }) {
    final font = italic
        ? boldItalic
        : switch (w) {
            >= 700 => bold,
            >= 600 => semi,
            >= 500 => medium,
            _ => regular,
          };
    // The web slip inherits a line height of 1.5 unless a block sets its own.
    final lh = height ?? 1.5;
    final size = s.px(px);
    return pw.TextStyle(
      font: font,
      fontSize: size,
      color: color,
      letterSpacing: ls == 0 ? null : s.px(ls),
      // The pdf package leaves the letter spacing out between words; the web
      // adds it there too. `_space` is the width of Inter's space.
      wordSpacing: ls == 0 || !spaceWords ? null : 1 + ls / (px * _space),
      // `height` is only read back by tx/rich below (the pdf package does not
      // use it for layout); lineSpacing is the extra gap between wrapped lines.
      height: lh,
      lineSpacing: math.max(0, (lh - _natural) * size),
    );
  }

  /// A line of Inter is about this many times the font size tall in the pdf
  /// package; CSS line-height adds the rest as half-leading above and below.
  static const double _natural = 1.165;

  /// Width of a space in Inter, as a share of the font size.
  static const double _space = 0.25;

  pw.Widget _lead(pw.TextStyle style, pw.Widget child) {
    final size = style.fontSize ?? 12;
    final pad = math.max(0.0, ((style.height ?? 1.5) - _natural) * size / 2);
    if (pad == 0) return child;
    return pw.Padding(
      padding: pw.EdgeInsets.symmetric(vertical: pad),
      child: child,
    );
  }

  /// `Text` with CSS-like line height.
  pw.Widget tx(
    String text, {
    required pw.TextStyle style,
    pw.TextAlign? textAlign,
  }) => _lead(style, pw.Text(text, style: style, textAlign: textAlign));

  /// `RichText` with CSS-like line height (taken from the first styled span).
  pw.Widget rich({required pw.TextSpan text}) {
    pw.TextStyle? style = text.style;
    if (style == null && text.children != null) {
      for (final c in text.children!) {
        if (c is pw.TextSpan && c.style != null) {
          style = c.style;
          break;
        }
      }
    }
    final child = pw.RichText(text: text);
    return style == null ? child : _lead(style, child);
  }
}

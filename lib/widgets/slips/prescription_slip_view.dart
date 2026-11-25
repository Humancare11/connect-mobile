import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/medical_record_models.dart';
import 'slip_tokens.dart';

/// The prescription on screen, as the web shows it on a phone: the classic
/// `RxSlip.jsx` layout with `RxSlip.css`'s mobile rules. It reflows; only the
/// medicine table scrolls sideways. (The PDF is built by `slip_pdf.dart`.)
class PrescriptionSlipView extends StatelessWidget {
  const PrescriptionSlipView({
    super.key,
    required this.record,
    required this.patient,
    this.country = '',
    this.signature,
  });

  final PrescriptionRecord record;

  /// The signed-in user's stored profile (name, gender, dob).
  final Map<String, String> patient;

  /// The doctor's country as a name.
  final String country;
  final Uint8List? signature;

  @override
  Widget build(BuildContext context) {
    // The web's `max-width: 420px` rules.
    final small = MediaQuery.sizeOf(context).width <= 420;

    return Container(
      decoration: const BoxDecoration(
        color: SlipColors.wrap,
        border: Border(top: BorderSide(color: SlipColors.wrapLine)),
      ),
      padding: EdgeInsets.all((small ? 8 : 12) + 5),
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(small ? 8 : 14),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0F12296B),
              blurRadius: 8,
              offset: Offset(0, 2),
            ),
            BoxShadow(
              color: Color(0x1412296B),
              blurRadius: 32,
              offset: Offset(0, 12),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ..._header(small),
            _title(small),
            _patientPanel(small),
            _fieldRow('Diagnosis :', record.diagnosis),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: Text(
                'Medications',
                style: slipText(
                  16,
                  weight: FontWeight.w700,
                  color: SlipColors.navy,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
              child: Text(
                'Rx',
                style: slipText(
                  22,
                  weight: FontWeight.w700,
                  color: SlipColors.rxAccent,
                ).copyWith(fontStyle: FontStyle.italic),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 18),
              child: _MedicineTable(medicines: record.medicines),
            ),
            _fieldRow('Advice :', record.instructions),
            // The backend has no allergy field, so this stays blank, as on web.
            _fieldRow('Allergy :', ''),
            _fieldRow('Follow-up Date :', slipDate(record.followUpDate)),
            ..._physician(),
            ..._footer(),
          ],
        ),
      ),
    );
  }

  /// The two-tone rule: a thick navy part (58%) and a thin light blue one.
  /// In the footer it is mirrored.
  Widget _rule({bool footer = false}) {
    final thick = Expanded(
      flex: 58,
      child: Container(
        height: 4,
        decoration: BoxDecoration(
          color: SlipColors.navy,
          borderRadius: footer
              ? const BorderRadius.horizontal(left: Radius.circular(3))
              : const BorderRadius.horizontal(right: Radius.circular(3)),
        ),
      ),
    );
    final thin = Expanded(
      flex: 42,
      child: Container(height: 2, color: SlipColors.rxAccent),
    );
    return Row(children: footer ? [thin, thick] : [thick, thin]);
  }

  List<Widget> _header(bool small) {
    return [
      Padding(
        padding: small
            ? const EdgeInsets.fromLTRB(12, 14, 12, 10)
            : const EdgeInsets.fromLTRB(16, 18, 16, 12),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Image.asset(
            kSlipLogo,
            width: 110,
            semanticLabel: 'Clinic logo',
          ),
        ),
      ),
      _rule(),
    ];
  }

  Widget _title(bool small) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'prescription',
            style: slipText(
              small ? 18 : 21,
              weight: FontWeight.w700,
              color: SlipColors.navy,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Date : ${slipDate(record.createdAt)}',
            style: slipText(
              12.5,
              weight: FontWeight.w500,
              color: SlipColors.rxMuted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _patientPanel(bool small) {
    final dob = (patient['dob'] ?? '').trim();
    final gender = (patient['gender'] ?? '').trim();
    final age = slipAge(dob);
    String orDash(String value) => value.isEmpty ? '—' : value;
    const line = BorderSide(color: SlipColors.rxLine, width: 1.5);

    Widget cell(String label, String value, Border? border) => Container(
      decoration: BoxDecoration(border: border),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.end,
        children: [
          Text(label.toUpperCase(), style: _labelStyle),
          Text(value, style: _valueStyle),
        ],
      ),
    );

    return Container(
      margin: small
          ? const EdgeInsets.fromLTRB(10, 0, 10, 14)
          : const EdgeInsets.fromLTRB(14, 0, 14, 18),
      decoration: BoxDecoration(
        color: SlipColors.rxPanel,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SlipColors.rxLine, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The stored values, as the web screen shows them (the DOB too).
          cell(
            'Patient Name',
            (patient['name'] ?? '').trim(),
            const Border(bottom: line, right: line),
          ),
          cell('Gender', orDash(gender), const Border(bottom: line)),
          cell('DOB', orDash(dob), const Border(bottom: line)),
          cell('Age', orDash(age), null),
        ],
      ),
    );
  }

  static final TextStyle _labelStyle = slipText(
    12,
    weight: FontWeight.w600,
    color: SlipColors.rxMuted,
    letterSpacing: 0.4,
  );

  static final TextStyle _valueStyle = slipText(
    14,
    weight: FontWeight.w500,
    color: SlipColors.rxInk,
  );

  /// "Label : value"; a long value moves under its label.
  Widget _fieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          Text(
            label,
            style: slipText(
              13,
              weight: FontWeight.w700,
              color: SlipColors.navy,
            ),
          ),
          if (value.trim().isNotEmpty)
            Text(value, style: slipText(13, color: SlipColors.rxInk)),
        ],
      ),
    );
  }

  List<Widget> _physician() {
    Widget field(String label, String value) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: _labelStyle),
        const SizedBox(height: 4),
        Text(value, style: _valueStyle),
      ],
    );

    final fields = <Widget>[
      field("Doctor's Name", record.doctor.name),
      field('Medical Reg No', record.enrollment.medicalRegistrationNumber),
      field('Speciality', record.enrollment.specialization),
      field('Date', slipDate(record.createdAt)),
      field('Country', country),
      if (record.isSigned)
        SlipSignatureBlock(
          signedAt: record.signedAt,
          signature: signature,
          labelText: 'SIGNATURE',
          labelStyle: _labelStyle,
          labelGap: 6,
        ),
    ];

    return [
      // 22 above the ribbon; the field row before it already left 12.
      const SizedBox(height: 10),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Align(
          alignment: Alignment.centerLeft,
          child: ClipPath(
            clipper: const _RibbonClipper(),
            child: Container(
              color: SlipColors.navy,
              padding: const EdgeInsets.fromLTRB(22, 8, 40, 8),
              child: Text(
                'PHYSICIAN DETAILS',
                style: slipText(
                  13,
                  weight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.4,
                ),
              ),
            ),
          ),
        ),
      ),
      Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 14),
        color: SlipColors.rxAccent,
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(14, 20, 14, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              if (i > 0) const SizedBox(height: 14),
              fields[i],
            ],
          ],
        ),
      ),
    ];
  }

  List<Widget> _footer() {
    return [
      const SizedBox(height: 26),
      _rule(footer: true),
      Container(
        color: SlipColors.rxPanel,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          children: [
            const SlipQr(),
            const SizedBox(height: 20),
            const SlipContactLines(color: SlipColors.rxMuted),
            const SizedBox(height: 20),
            Opacity(
              opacity: 0.85,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 100),
                child: Image.asset(kSlipLogo, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    ];
  }
}

/// The web's `clip-path: polygon(0 0, 100% 0, 90% 100%, 0 100%)`.
class _RibbonClipper extends CustomClipper<Path> {
  const _RibbonClipper();

  @override
  Path getClip(Size size) => Path()
    ..lineTo(size.width, 0)
    ..lineTo(size.width * 0.9, size.height)
    ..lineTo(0, size.height)
    ..close();

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// Sr. No / Medicine / Dose / Timing / No. of Days. Its columns are sized the
/// way the browser sizes the web table, and it scrolls sideways when they do
/// not fit.
class _MedicineTable extends StatelessWidget {
  const _MedicineTable({required this.medicines});

  final List<PrescriptionMedicine> medicines;

  static const _headers = [
    'SR. NO',
    'MEDICINE',
    'DOSE',
    'TIMING',
    'NO. OF DAYS',
  ];

  /// The web's column width hints.
  static const _preferred = [40.0, 140.0, 70.0, 170.0, 80.0];

  static const _padding = EdgeInsets.symmetric(horizontal: 10, vertical: 11);
  static const _line = BorderSide(color: SlipColors.rxLine);

  static final _headerStyle = slipText(
    11.5,
    weight: FontWeight.w600,
    color: Colors.white,
    letterSpacing: 0.4,
  );
  static final _cellStyle = slipText(13, color: SlipColors.rxInk);
  static final _nameStyle = slipText(
    13,
    weight: FontWeight.w500,
    color: SlipColors.rxInk,
  );
  static final _timingStyle = slipText(12, color: SlipColors.rxInk);

  static TextStyle _styleFor(int column) => switch (column) {
    1 => _nameStyle,
    3 => _timingStyle,
    _ => _cellStyle,
  };

  /// The narrowest each column can be: its longest word. Timing may break
  /// anywhere (web `word-break: break-word`), so only its heading counts.
  List<double> _minimumWidths(BuildContext context, List<List<String>> rows) {
    final scaler = MediaQuery.textScalerOf(context);
    double widest(String text, TextStyle style) {
      var width = 0.0;
      for (final word in text.split(RegExp(r'\s+'))) {
        final painter = TextPainter(
          text: TextSpan(text: word, style: style),
          textDirection: TextDirection.ltr,
          textScaler: scaler,
        )..layout();
        width = math.max(width, painter.width);
        painter.dispose();
      }
      return width;
    }

    return [
      for (var column = 0; column < _headers.length; column++)
        [
              widest(_headers[column], _headerStyle),
              if (column != 3)
                for (final row in rows) widest(row[column], _styleFor(column)),
            ].reduce(math.max).ceilToDouble() +
            _padding.horizontal +
            1,
    ];
  }

  List<double> _widths(List<double> minimum, double available) {
    final preferred = [
      for (var i = 0; i < minimum.length; i++)
        math.max(minimum[i], _preferred[i]),
    ];
    final least = minimum.fold(0.0, (a, b) => a + b);
    final most = preferred.fold(0.0, (a, b) => a + b);
    if (available <= least) return minimum;
    if (available >= most) return preferred;
    final share = (available - least) / (most - least);
    return [
      for (var i = 0; i < minimum.length; i++)
        minimum[i] + (preferred[i] - minimum[i]) * share,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final list = medicines.isEmpty ? const [PrescriptionMedicine()] : medicines;
    final rows = [
      for (var i = 0; i < list.length; i++)
        [
          '${i + 1}',
          list[i].name,
          list[i].dosage,
          list[i].frequency,
          list[i].duration,
        ],
    ];

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: SlipColors.rxLine, width: 1.5),
      ),
      // The decoration's border already insets the child.
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8.5),
        child: LayoutBuilder(
          builder: (context, box) {
            final widths = _widths(_minimumWidths(context, rows), box.maxWidth);
            return SingleChildScrollView(
              key: const ValueKey('medicine table'),
              scrollDirection: Axis.horizontal,
              child: Column(
                children: [
                  _row(widths, _headers, header: true),
                  for (var i = 0; i < rows.length; i++)
                    _row(widths, rows[i], shaded: i.isOdd),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _row(
    List<double> widths,
    List<String> cells, {
    bool header = false,
    bool shaded = false,
  }) {
    // One fill for the whole row, so no seams show between the cells.
    return ColoredBox(
      color: header
          ? SlipColors.navy
          : shaded
          ? SlipColors.rxPanel
          : Colors.white,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var column = 0; column < cells.length; column++)
              Container(
                width: widths[column],
                padding: _padding,
                alignment: !header && column == 1
                    ? Alignment.centerLeft
                    : Alignment.center,
                decoration: BoxDecoration(
                  border: header
                      ? null
                      : Border(
                          top: _line,
                          right: column == cells.length - 1
                              ? BorderSide.none
                              : _line,
                        ),
                ),
                child: Text(
                  cells[column],
                  textAlign: !header && column == 1
                      ? TextAlign.left
                      : TextAlign.center,
                  style: header ? _headerStyle : _styleFor(column),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../models/medical_record_models.dart';
import 'slip_tokens.dart';

/// The medical certificate on screen, as the web's My Records shows it: the
/// fixed 794 x 1123 page of `MedicalCertificateSlip.jsx`, scaled down to fit
/// the width but never below half size, after which it scrolls sideways.
class CertificateSlipView extends StatelessWidget {
  const CertificateSlipView({
    super.key,
    required this.record,
    required this.patient,
    this.signature,
  });

  static const double pageWidth = 794;
  static const double pageHeight = 1123;
  static const double minScale = 0.5;

  static double scaleFor(double available) =>
      math.max(minScale, math.min(1, available / pageWidth));

  final MedicalCertificateRecord record;

  /// The signed-in user's stored profile (name, gender, dob).
  final Map<String, String> patient;
  final Uint8List? signature;

  @override
  Widget build(BuildContext context) {
    final padding = MediaQuery.sizeOf(context).width <= 420 ? 8.0 : 12.0;

    return Container(
      decoration: const BoxDecoration(
        color: SlipColors.wrap,
        border: Border(top: BorderSide(color: SlipColors.wrapLine)),
      ),
      child: LayoutBuilder(
        builder: (context, box) {
          final available = math.max(0.0, box.maxWidth - padding * 2);
          final width = pageWidth * scaleFor(available);
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.all(padding),
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: available),
              child: Center(
                child: SizedBox(
                  key: const ValueKey('certificate page'),
                  width: width,
                  child: FittedBox(
                    fit: BoxFit.fitWidth,
                    // A picture of a fixed page: the phone's font size setting
                    // would only push its text out of place.
                    child: MediaQuery.withNoTextScaling(child: _page()),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _page() {
    final name = (patient['name'] ?? '').trim();
    final dob = (patient['dob'] ?? '').trim();
    final age = slipAge(dob);
    final gender = (patient['gender'] ?? '').trim();
    final ageSex = [
      if (age.isNotEmpty) '$age yrs',
      if (gender.isNotEmpty) gender,
    ].join(' / ');
    final issued = certificateDate(
      record.issuedDate.isNotEmpty ? record.issuedDate : record.createdAt,
    );
    final diagnosis = record.diagnosis.trim();

    return Container(
      width: pageWidth,
      color: Colors.white,
      constraints: const BoxConstraints(minHeight: pageHeight),
      child: Column(
        // Keeps the footer at the bottom of the page.
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ..._header(),
              _banner(diagnosis, issued),
              _patientFields(name, issued, ageSex, dob),
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 40),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      SlipColors.navy,
                      SlipColors.navy.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 18, 40, 0),
                child: _statement(name, ageSex, diagnosis),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: _details(diagnosis),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 16, 40, 0),
                child: _doctorCard(),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(40, 10, 40, 0),
                child: _validityNote(),
              ),
            ],
          ),
          _footer(),
        ],
      ),
    );
  }

  List<Widget> _header() {
    return [
      Container(
        height: 6,
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [SlipColors.navyDark, SlipColors.navy, SlipColors.accent],
            stops: [0, 0.6, 1],
          ),
        ),
      ),
      Container(
        padding: const EdgeInsets.fromLTRB(40, 18, 40, 16),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: SlipColors.light, width: 2)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Image.asset(
              kSlipLogo,
              height: 68,
              semanticLabel: 'Humancare Connect',
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  kSlipTagline.toUpperCase(),
                  style: slipText(
                    11,
                    weight: FontWeight.w700,
                    color: SlipColors.navy,
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  width: 48,
                  height: 4,
                  decoration: BoxDecoration(
                    color: SlipColors.navy,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ];
  }

  Widget _banner(String diagnosis, String issued) {
    final id = record.id.trim();
    final certificateId = id.isEmpty
        ? '—'
        : 'HC-CERT-${(id.length > 8 ? id.substring(id.length - 8) : id).toUpperCase()}';
    final small = slipText(11, color: SlipColors.muted);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 10),
      decoration: const BoxDecoration(
        color: SlipColors.light,
        border: Border(bottom: BorderSide(color: SlipColors.border)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Medical Certificate',
                  style: slipText(
                    13,
                    weight: FontWeight.w700,
                    color: SlipColors.navy,
                  ),
                ),
                if (diagnosis.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      style: slipText(12, color: SlipColors.muted),
                      children: [
                        TextSpan(
                          text: 'Reason:',
                          style: slipText(
                            12,
                            weight: FontWeight.w700,
                            color: SlipColors.muted,
                          ),
                        ),
                        TextSpan(text: ' $diagnosis'),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                certificateId,
                style: slipText(
                  11,
                  weight: FontWeight.w600,
                  color: SlipColors.navy,
                ),
              ),
              Text('Issued: $issued', style: small),
            ],
          ),
        ],
      ),
    );
  }

  Widget _patientFields(String name, String issued, String ageSex, String dob) {
    final fields = <Widget>[
      _infoField('Patient Name', name),
      _infoField('Date of Issue', issued),
      _infoField('Age / Sex', ageSex.isEmpty ? '—' : ageSex),
      if (dob.isNotEmpty) _infoField('Date of Birth', certificateDate(dob)),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 20, 40, 16),
      child: Column(
        children: [
          for (var i = 0; i < fields.length; i += 2) ...[
            if (i > 0) const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(child: fields[i]),
                const SizedBox(width: 48),
                Expanded(
                  child: i + 1 < fields.length
                      ? fields[i + 1]
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _infoField(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          '$label :',
          style: slipText(
            12,
            weight: FontWeight.w700,
            color: SlipColors.navy,
            letterSpacing: 0.3,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Container(
            padding: const EdgeInsets.only(bottom: 2),
            decoration: const BoxDecoration(
              border: Border(
                bottom: BorderSide(color: SlipColors.border, width: 1.2),
              ),
            ),
            child: Text(value.isEmpty ? ' ' : value, style: slipText(13)),
          ),
        ),
      ],
    );
  }

  Widget _statement(String name, String ageSex, String diagnosis) {
    final style = slipText(13, height: 1.7);
    final bold = style.copyWith(fontWeight: FontWeight.w700);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: SlipColors.soft,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SlipColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          const Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 4,
            child: ColoredBox(color: SlipColors.navy),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: Text.rich(
                TextSpan(
                  style: style,
                  children: [
                    const TextSpan(text: 'This is to certify that '),
                    TextSpan(
                      text: name.isEmpty ? 'the patient' : name,
                      style: bold.copyWith(color: SlipColors.navy),
                    ),
                    TextSpan(text: ageSex.isEmpty ? ', ' : ', $ageSex, '),
                    const TextSpan(
                      text: 'has been examined and is suffering from ',
                    ),
                    TextSpan(
                      text: diagnosis.isEmpty ? '—' : diagnosis,
                      style: bold,
                    ),
                    const TextSpan(text: '.'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _details(String diagnosis) {
    final from = record.restFromDate;
    final to = record.restToDate;
    final rows = <(String, String)>[
      ('Diagnosis / Condition', diagnosis.isEmpty ? '—' : diagnosis),
      if (record.recommendation.trim().isNotEmpty)
        ('Recommendation', record.recommendation),
      if (from.isNotEmpty || to.isNotEmpty)
        (
          'Rest Period',
          from.isNotEmpty && to.isNotEmpty
              ? '${certificateDate(from)} to ${certificateDate(to)}'
              : from.isNotEmpty
              ? 'From ${certificateDate(from)}'
              : 'Until ${certificateDate(to)}',
        ),
      if (record.notes.trim().isNotEmpty) ('Additional Notes', record.notes),
    ];

    Widget row(
      String left,
      String right, {
      required TextStyle leftStyle,
      required TextStyle rightStyle,
      required Color fill,
      required Color line,
      required double vertical,
      bool first = false,
    }) {
      final side = BorderSide(color: line);
      final padding = EdgeInsets.symmetric(horizontal: 16, vertical: vertical);
      // One fill for the whole row, so no seam shows between the two cells.
      return ColoredBox(
        color: fill,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 3,
                child: Container(
                  padding: padding,
                  decoration: BoxDecoration(
                    border: Border(
                      top: first ? side : BorderSide.none,
                      left: side,
                      right: side,
                      bottom: side,
                    ),
                  ),
                  child: Text(left, style: leftStyle),
                ),
              ),
              Expanded(
                flex: 7,
                child: Container(
                  padding: padding,
                  decoration: BoxDecoration(
                    border: Border(
                      top: first ? side : BorderSide.none,
                      right: side,
                      bottom: side,
                    ),
                  ),
                  child: Text(right, style: rightStyle),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final headerStyle = slipText(
      12,
      weight: FontWeight.w700,
      color: Colors.white,
      letterSpacing: 0.5,
    );

    return Column(
      children: [
        row(
          'FIELD',
          'DETAILS',
          leftStyle: headerStyle,
          rightStyle: headerStyle,
          fill: SlipColors.navy,
          line: SlipColors.navy,
          vertical: 9,
          first: true,
        ),
        for (var i = 0; i < rows.length; i++)
          row(
            rows[i].$1,
            rows[i].$2,
            leftStyle: slipText(
              12,
              weight: FontWeight.w700,
              color: SlipColors.navy,
            ),
            rightStyle: slipText(13),
            fill: i.isOdd ? SlipColors.soft : Colors.white,
            line: SlipColors.border,
            vertical: 10,
          ),
      ],
    );
  }

  Widget _doctorCard() {
    final name = record.doctor.name.trim().isEmpty
        ? '—'
        : record.doctor.name.trim();
    final enrollment = record.enrollment;
    final subtitle = [
      enrollment.specialization,
      enrollment.qualification,
    ].where((value) => value.isNotEmpty).join(' · ');
    final clinicName = enrollment.clinicName.isEmpty
        ? 'Humancare Connect'
        : enrollment.clinicName;
    final clinicAddress = enrollment.clinicAddress.isEmpty
        ? kSlipAddress
        : enrollment.clinicAddress;
    final small = slipText(11, color: SlipColors.muted);

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: SlipColors.border),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(7),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
              decoration: const BoxDecoration(
                color: SlipColors.light,
                border: Border(bottom: BorderSide(color: SlipColors.border)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: const BoxDecoration(
                      color: SlipColors.navy,
                      shape: BoxShape.circle,
                    ),
                    child: Text(
                      name.characters.first.toUpperCase(),
                      style: slipText(
                        14,
                        weight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                'Dr. $name',
                                style: slipText(
                                  13,
                                  weight: FontWeight.w700,
                                  color: SlipColors.navy,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            const CustomPaint(
                              size: Size(17, 17),
                              painter: _VerifiedTickPainter(),
                            ),
                          ],
                        ),
                        if (subtitle.isNotEmpty) Text(subtitle, style: small),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 300),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (enrollment.medicalRegistrationNumber.isNotEmpty)
                          Text.rich(
                            textAlign: TextAlign.right,
                            TextSpan(
                              style: small,
                              children: [
                                const TextSpan(text: 'Reg. No: '),
                                TextSpan(
                                  text: enrollment.medicalRegistrationNumber,
                                  style: slipText(
                                    11,
                                    weight: FontWeight.w700,
                                    color: SlipColors.navy,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        if (enrollment.medicalCouncilName.isNotEmpty)
                          Text(
                            enrollment.medicalCouncilName,
                            textAlign: TextAlign.right,
                            style: slipText(10, color: SlipColors.muted),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Container(
              color: SlipColors.soft,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          clinicName,
                          style: slipText(
                            12,
                            weight: FontWeight.w600,
                            height: 1.7,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          clinicAddress,
                          style: slipText(
                            12,
                            color: SlipColors.muted,
                            height: 1.7,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  if (record.isSigned)
                    // The signature replaces the "system-generated" note.
                    SlipSignatureBlock(
                      signedAt: record.signedAt,
                      signature: signature,
                      labelText: 'Signature',
                      labelStyle: slipText(
                        12,
                        weight: FontWeight.w700,
                        color: SlipColors.navy,
                      ),
                    )
                  else
                    SizedBox(
                      width: 220,
                      child: Text(
                        'This is a system-generated certificate and does not require a signature or stamp.',
                        textAlign: TextAlign.center,
                        // `Inter` has no italic face, so this one is slanted
                        // from the regular weight (InterSlip's is bold).
                        style:
                            slipText(
                              11,
                              color: SlipColors.muted,
                              height: 1.6,
                            ).copyWith(
                              fontFamily: 'Inter',
                              fontStyle: FontStyle.italic,
                            ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _validityNote() {
    final style = slipText(11, color: SlipColors.noteText);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
      decoration: BoxDecoration(
        color: SlipColors.noteBg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SlipColors.noteBorder),
      ),
      child: Text.rich(
        TextSpan(
          style: style,
          children: [
            TextSpan(
              text: 'Note:',
              style: style.copyWith(fontWeight: FontWeight.w700),
            ),
            const TextSpan(
              text:
                  ' This certificate is issued based on the medical examination conducted via Humancare Connect telehealth platform. It is valid as an official medical document for the purpose stated above.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer() {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 10),
      decoration: const BoxDecoration(
        color: SlipColors.rxPanel,
        border: Border(top: BorderSide(color: SlipColors.accent, width: 3)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const SlipQr(),
          const SizedBox(width: 20),
          const Flexible(child: SlipContactLines(color: SlipColors.footMuted)),
          const SizedBox(width: 20),
          Opacity(opacity: 0.85, child: Image.asset(kSlipLogo, height: 100)),
        ],
      ),
    );
  }
}

/// The blue verified badge beside the doctor's name (the web's SVG path).
class _VerifiedTickPainter extends CustomPainter {
  const _VerifiedTickPainter();

  static const _badge = [
    Offset(12, 1.5),
    Offset(14.6, 3.4),
    Offset(17.8, 3.3),
    Offset(18.8, 6.4),
    Offset(21.4, 8.3),
    Offset(20.4, 11.4),
    Offset(21.4, 14.5),
    Offset(18.8, 16.4),
    Offset(17.8, 19.5),
    Offset(14.6, 19.4),
    Offset(12, 22.5),
    Offset(9.4, 20.6),
    Offset(6.2, 20.7),
    Offset(5.2, 17.6),
    Offset(2.6, 15.7),
    Offset(3.6, 12.6),
    Offset(2.6, 9.5),
    Offset(5.2, 7.6),
    Offset(6.2, 4.5),
    Offset(9.4, 4.6),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / 24, size.height / 24);
    canvas.drawPath(
      Path()..addPolygon(_badge, true),
      Paint()..color = SlipColors.accent,
    );
    canvas.drawPath(
      Path()
        ..moveTo(7.8, 12.3)
        ..relativeLineTo(2.8, 2.8)
        ..relativeLineTo(5.6, -5.8),
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.2
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Colours, texts and small pieces shared by the on-screen prescription and
/// medical certificate. The values are the web slips' (`RxSlip.css`,
/// `MedicalCertificateSlip.jsx`), the same ones `lib/pdf/slip_pdf.dart` uses.
abstract final class SlipColors {
  static const navy = Color(0xFF12296B);
  static const navyDark = Color(0xFF0C1D4F);
  static const accent = Color(0xFF1E63D6);
  static const light = Color(0xFFEEF1F8);
  static const soft = Color(0xFFF6F8FC);
  static const border = Color(0xFFD9DDE6);
  static const muted = Color(0xFF7A8194);
  static const body = Color(0xFF1F2433);
  static const footMuted = Color(0xFF667085);
  static const noteBg = Color(0xFFFFFBEB);
  static const noteBorder = Color(0xFFFDE68A);
  static const noteText = Color(0xFF92400E);

  // Prescription (classic layout).
  static const rxAccent = Color(0xFF4A9FE0);
  static const rxInk = Color(0xFF1C2230);
  static const rxMuted = Color(0xFF667085);
  static const rxLine = Color(0xFFDDE2EA);
  static const rxPanel = Color(0xFFF7F9FC);

  // The area of the record card the slip sits on (`.mr-slip-wrap`).
  static const wrap = Color(0xFFF1F5F9);
  static const wrapLine = Color(0xFFE2E8F0);
}

const String kSlipPhone = '+1 (302) 303-9993';
const String kSlipEmail = 'support@humancareconnect.co';
const String kSlipAddress =
    '4 Peddlers Row #1091 Newark, DE 19702, United States';
const String kSlipTagline = 'Global Health Passport';

const String kSlipLogo = 'assets/pdf/prescription-logo.png';
const String kSlipQr = 'assets/pdf/footer-qr.png';

/// Inter with its bold faces, registered apart from `Inter` so that bold text
/// elsewhere in the app does not change.
const String kSlipFont = 'InterSlip';

/// A text style in the web's pixel size and CSS weight, with its line height.
TextStyle slipText(
  double size, {
  FontWeight weight = FontWeight.w400,
  Color color = SlipColors.body,
  double letterSpacing = 0,
  double height = 1.5,
}) {
  return TextStyle(
    inherit: false,
    fontFamily: kSlipFont,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
    leadingDistribution: TextLeadingDistribution.even,
    textBaseline: TextBaseline.alphabetic,
  );
}

/// Web `fmtDate` of the prescription (en-IN): "23 Nov 2026".
String slipDate(String value) => _format(value, 'dd MMM yyyy');

/// Web `fmtDate` of the certificate (en-US): "Nov 23, 2026", "—" when empty.
String certificateDate(String value) =>
    value.trim().isEmpty ? '—' : _format(value, 'MMM dd, yyyy');

String _format(String value, String pattern) {
  final raw = value.trim();
  if (raw.isEmpty) return '';
  final date = DateTime.tryParse(raw);
  if (date == null) return raw;
  return DateFormat(pattern, 'en_US').format(date.toLocal());
}

/// Whole years, or '' when unknown or under one (web `calcAge`).
String slipAge(String dob, {DateTime? now}) {
  final birth = DateTime.tryParse(dob.trim());
  if (birth == null) return '';
  final today = now ?? DateTime.now();
  var age = today.year - birth.year;
  if (today.month < birth.month ||
      (today.month == birth.month && today.day < birth.day)) {
    age -= 1;
  }
  return age > 0 ? '$age' : '';
}

/// The doctor's signature: label, image (56 high, 220 wide at most) and the
/// "Digitally signed" caption. The space is kept while the image loads.
class SlipSignatureBlock extends StatelessWidget {
  const SlipSignatureBlock({
    super.key,
    required this.signedAt,
    required this.labelText,
    required this.labelStyle,
    this.signature,
    this.labelGap = 4,
  });

  final String signedAt;
  final String labelText;
  final TextStyle labelStyle;
  final Uint8List? signature;
  final double labelGap;

  static String caption(String signedAt) {
    final date = DateTime.tryParse(signedAt.trim());
    if (date == null) return 'Digitally signed';
    final local = date.toLocal();
    return 'Digitally signed · '
        '${DateFormat('dd MMM yyyy', 'en_US').format(local)} '
        '${DateFormat('hh:mm a', 'en_US').format(local)}';
  }

  @override
  Widget build(BuildContext context) {
    final image = signature;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(labelText, style: labelStyle),
        SizedBox(height: labelGap),
        SizedBox(
          height: 56,
          child: image == null
              ? null
              : ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: Image.memory(
                    image,
                    height: 56,
                    fit: BoxFit.contain,
                    alignment: Alignment.centerLeft,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => const SizedBox.shrink(),
                  ),
                ),
        ),
        const SizedBox(height: 4),
        Text(caption(signedAt), style: slipText(11, color: SlipColors.muted)),
      ],
    );
  }
}

/// The footer's QR code in its bordered box.
class SlipQr extends StatelessWidget {
  const SlipQr({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 100,
      height: 100,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: SlipColors.rxLine),
      ),
      child: Image.asset(kSlipQr, fit: BoxFit.contain),
    );
  }
}

/// Phone, email and address with the web's navy icons.
class SlipContactLines extends StatelessWidget {
  const SlipContactLines({super.key, required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    Widget line(IconData icon, String text) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: SlipColors.navy),
        const SizedBox(width: 7),
        Flexible(
          child: Text(text, style: slipText(13, color: color, height: 1.9)),
        ),
      ],
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line(Icons.phone, kSlipPhone),
        line(Icons.email, kSlipEmail),
        line(Icons.location_on, kSlipAddress),
      ],
    );
  }
}

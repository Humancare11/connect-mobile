import 'dart:typed_data';

import 'package:pdf/widgets.dart' as pw;

import '../models/visit_note_models.dart';
import '../pdf/slip_pdf.dart';

/// Builds the Visit Note PDF a patient downloads. The drawing lives in
/// `SlipPdf` (lib/pdf/slip_pdf.dart) so the three documents share one look,
/// the same as the web `VisitNoteSlip` PDF.
class VisitNotePdf {
  const VisitNotePdf._();

  /// `signature` is the doctor's PNG, or `null` - the PDF is still created
  /// without it (web: "a missing signature image must not block the download").
  /// `countryName` is the physician's country already resolved to a name.
  /// `logo` is kept for older callers; the web logo is bundled with the app.
  static Future<Uint8List> build(
    VisitNoteReport report, {
    Uint8List? signature,
    String? countryName,
    pw.MemoryImage? logo,
  }) {
    final country = (countryName ?? '').trim().isNotEmpty
        ? countryName!.trim()
        : report.physicianCountry;
    return SlipPdf.visitNote(report, signature: signature, country: country);
  }
}

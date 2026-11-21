import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../config/app_design_system.dart';
import '../models/visit_note_models.dart';
import '../services/visit_notes_service.dart';
import '../widgets/visit_note_widgets.dart';
import 'visit_note_pdf.dart';

/// "Visit Note Preview" for the patient: the signed note laid out as the
/// letterhead paper, with a Download PDF button. Read only (only the doctor can
/// add amendments). Same content as the web `/user/my-visit-notes/:reportId`.
class VisitNoteDetailScreen extends StatefulWidget {
  const VisitNoteDetailScreen({
    super.key,
    required this.reportId,
    this.service,
    this.sharePdf,
  });

  final String reportId;

  // Injectable for tests; the defaults are the real service / sharing sheet.
  final VisitNotesService? service;
  final Future<void> Function(Uint8List bytes, String filename)? sharePdf;

  @override
  State<VisitNoteDetailScreen> createState() => _VisitNoteDetailScreenState();
}

class _VisitNoteDetailScreenState extends State<VisitNoteDetailScreen> {
  late final VisitNotesService _service =
      widget.service ?? VisitNotesService();

  VisitNoteReport? _report;
  Uint8List? _signature;
  String _country = '';
  bool _loading = true;
  bool _notFound = false;
  String _error = '';
  bool _downloading = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _notFound = false;
      _error = '';
    });
    final result = await _service.fetchOne(widget.reportId, silent: true);
    if (!mounted) return;

    final report = result.data;
    if (!result.success || report == null) {
      setState(() {
        _loading = false;
        // The server answers 404 (never 403) for a report that is not the
        // patient's own, and 400 for a malformed id.
        _notFound = result.statusCode == 404 || result.statusCode == 400;
        _error = _notFound
            ? ''
            : (result.message.isNotEmpty
                  ? result.message
                  : 'Could not load this Visit Note.');
      });
      return;
    }

    setState(() {
      _report = report;
      _signature = _service.cachedSignature(report.id);
      _loading = false;
    });
    _loadExtras(report);
  }

  /// The signature and the country name are extras: if either fails the note
  /// is still shown.
  Future<void> _loadExtras(VisitNoteReport report) async {
    final signature = await _service.fetchSignature(report.id);
    final country = await _service.countryName(report.physicianCountry);
    if (!mounted) return;
    setState(() {
      _signature = signature ?? _signature;
      _country = country;
    });
  }

  static Future<void> _defaultSharePdf(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

  Future<void> _download() async {
    final report = _report;
    if (report == null || _downloading) return;
    setState(() => _downloading = true);
    try {
      final signature =
          _signature ?? await _service.fetchSignatureWithRetry(report.id);
      final country = _country.isNotEmpty
          ? _country
          : await _service.countryName(report.physicianCountry);
      final bytes = await VisitNotePdf.build(
        report,
        signature: signature,
        countryName: country,
      );
      await (widget.sharePdf ?? _defaultSharePdf)(
        bytes,
        'visit-note_${report.reportNumber}.pdf',
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not create the PDF. Please try again.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVisitNoteCanvas,
      appBar: AppBar(
        title: Text(
          'Visit Note Preview',
          style: AppType.body(
            size: 18,
            weight: FontWeight.w800,
          ).copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    final report = _report;
    if (_notFound) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: const [
          VisitNoteEmptyState(
            icon: Icons.assignment_outlined,
            title: 'Visit Note not found',
            message: 'It may not exist, or you may not have access to it.',
          ),
        ],
      );
    }
    if (report == null) {
      return ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [VisitNoteErrorBanner(message: _error, onRetry: _load)],
      );
    }

    return RefreshIndicator(
      color: AppColors.primary,
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        children: [
          OutlinedButton.icon(
            onPressed: _downloading ? null : _download,
            icon: _downloading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download_rounded, size: 18),
            label: Text(_downloading ? 'Generating...' : 'Download PDF'),
            style: OutlinedButton.styleFrom(
              foregroundColor: AppColors.primary,
              side: const BorderSide(color: AppColors.primary),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
          ),
          const SizedBox(height: 14),
          _VisitNoteSlip(
            report: report,
            signature: _signature,
            country: _country.isNotEmpty ? _country : report.physicianCountry,
          ),
        ],
      ),
    );
  }
}

Color get _brand => AppColors.primary;
Color get _brandDeep => AppColors.primaryDeep;
Color get _brandTint => AppColors.primary.withValues(alpha: 0.08);

/// The Visit Note paper: same letterhead, banner and panels as the app's
/// prescription and certificate slips, with the Visit Note content.
class _VisitNoteSlip extends StatelessWidget {
  const _VisitNoteSlip({
    required this.report,
    required this.signature,
    required this.country,
  });

  final VisitNoteReport report;
  final Uint8List? signature;
  final String country;

  @override
  Widget build(BuildContext context) {
    final signedAt = formatVisitNoteDateTime(report.signedAt);
    return Container(
      decoration: BoxDecoration(
        color: _brandTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      padding: const EdgeInsets.all(10),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(3),
          boxShadow: AppShadows.subtle,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const _SlipHeader(),
            _Banner(report: report),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _InfoPanel(
                    label: 'Patient',
                    rows: [
                      ['Patient Name', report.patientName],
                      ['Gender', report.patientGender],
                      ['DOB', report.patientDob],
                      ['Age', report.patientAge],
                    ],
                  ),
                  const SizedBox(height: 10),
                  _InfoPanel(
                    label: 'Consultation',
                    rows: [
                      ['Consultation', report.consultationWhen],
                      ['Mode', report.modeLabel],
                    ],
                  ),
                  const SizedBox(height: 14),
                  _SymptomsBox(text: report.symptoms),
                  const SizedBox(height: 16),
                  Text(
                    'Consultation Details',
                    style: AppType.body(
                      size: 14,
                      weight: FontWeight.w800,
                    ).copyWith(color: _brandDeep),
                  ),
                  const SizedBox(height: 8),
                  _DetailRow(
                    label: 'Clinical Findings :',
                    value: report.clinicalFindings,
                    shaded: false,
                  ),
                  _DetailRow(
                    label: 'Plan / Treatment :',
                    value: report.plan,
                    shaded: true,
                  ),
                  if (report.note.trim().isNotEmpty)
                    _DetailRow(
                      label: 'Note :',
                      value: report.note,
                      shaded: false,
                    ),
                  const SizedBox(height: 16),
                  _InfoPanel(
                    label: 'Physician Details',
                    rows: [
                      ["Doctor's Name", report.physicianName],
                      ['Medical Reg No', report.physicianRegistrationNumber],
                      ['Speciality', report.physicianSpeciality],
                      ['Country', country],
                    ],
                    footer: _SignatureBlock(
                      signedAt: signedAt,
                      signature: signature,
                    ),
                  ),
                  if (report.amendments.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    _Amendments(amendments: report.amendments),
                  ],
                  const SizedBox(height: 16),
                ],
              ),
            ),
            const _SlipFooter(),
          ],
        ),
      ),
    );
  }
}

class _SlipHeader extends StatelessWidget {
  const _SlipHeader();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _brandTint, width: 2)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo-2.png',
            height: 42,
            errorBuilder: (_, error, stackTrace) {
              return Text(
                'Humancare Connect',
                style: AppType.display(size: 16, color: _brandDeep),
              );
            },
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Global Health Passport',
                style: AppType.body(
                  size: 10,
                  weight: FontWeight.w900,
                ).copyWith(color: _brand, letterSpacing: 1.0),
              ),
              const SizedBox(height: 5),
              SizedBox(
                width: 48,
                child: Divider(color: _brand, thickness: 4),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.report});

  final VisitNoteReport report;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _brandTint,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Visit Note',
              style: AppType.body(
                size: 14,
                weight: FontWeight.w900,
              ).copyWith(color: _brandDeep),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Report ID : ${report.reportNumber}',
                style: AppType.body(
                  size: 12,
                  weight: FontWeight.w900,
                ).copyWith(color: _brandDeep),
              ),
              const SizedBox(height: 2),
              Text(
                'Date : ${formatVisitNoteDate(report.signedAt)}',
                style: AppType.body(
                  size: 11,
                ).copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.label, required this.rows, this.footer});

  final String label;
  final List<List<String>> rows;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(border: Border.all(color: _brandTint)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: AppType.body(
              size: 10,
              weight: FontWeight.w900,
            ).copyWith(color: _brand, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    row[0],
                    style: AppType.body(
                      size: 12,
                    ).copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.length > 1 && row[1].trim().isNotEmpty
                          ? row[1]
                          : '-',
                      textAlign: TextAlign.right,
                      style: AppType.body(
                        size: 12,
                        weight: FontWeight.w800,
                      ).copyWith(color: _brandDeep),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (footer != null) ...[const SizedBox(height: 6), footer!],
        ],
      ),
    );
  }
}

class _SymptomsBox extends StatelessWidget {
  const _SymptomsBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
      decoration: BoxDecoration(
        color: _brandTint,
        border: Border(left: BorderSide(color: _brand, width: 4)),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text.rich(
        TextSpan(
          children: [
            TextSpan(
              text: 'Symptoms : ',
              style: AppType.body(
                size: 13,
                weight: FontWeight.w800,
              ).copyWith(color: _brandDeep),
            ),
            TextSpan(
              text: text.trim().isEmpty ? '-' : text,
              style: AppType.body(
                size: 13,
                height: 1.6,
              ).copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.shaded,
  });

  final String label;
  final String value;
  final bool shaded;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: shaded ? _brandTint : AppColors.surface,
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppType.body(
              size: 12,
              weight: FontWeight.w800,
            ).copyWith(color: _brandDeep),
          ),
          const SizedBox(height: 4),
          Text(
            value.trim().isEmpty ? '-' : value,
            style: AppType.body(
              size: 13,
              height: 1.5,
            ).copyWith(color: AppColors.textPrimary),
          ),
        ],
      ),
    );
  }
}

class _SignatureBlock extends StatelessWidget {
  const _SignatureBlock({required this.signedAt, this.signature});

  final String signedAt;
  final Uint8List? signature;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Signature',
          style: AppType.body(
            size: 12,
            weight: FontWeight.w800,
          ).copyWith(color: _brand),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 56,
          child: signature == null
              ? null
              : Image.memory(
                  signature!,
                  height: 56,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  gaplessPlayback: true,
                  errorBuilder: (_, _, _) => const SizedBox.shrink(),
                ),
        ),
        const SizedBox(height: 4),
        Text(
          signedAt.isEmpty
              ? 'Digitally signed'
              : 'Digitally signed · $signedAt',
          style: AppType.body(
            size: 11,
          ).copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _Amendments extends StatelessWidget {
  const _Amendments({required this.amendments});

  final List<VisitNoteAmendment> amendments;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: _brandTint)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: _brandTint,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            child: Text(
              'AMENDMENTS',
              style: AppType.body(
                size: 12,
                weight: FontWeight.w900,
              ).copyWith(color: _brandDeep, letterSpacing: 0.6),
            ),
          ),
          for (var i = 0; i < amendments.length; i++)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: i.isOdd ? _brandTint : AppColors.surface,
                border: i == 0
                    ? null
                    : Border(top: BorderSide(color: AppColors.border)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Amendment ${i + 1} · ${amendments[i].authorName} · '
                    '${formatVisitNoteDateTime(amendments[i].createdAt)}',
                    style: AppType.body(
                      size: 11,
                    ).copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Reason : ',
                          style: AppType.body(
                            size: 13,
                            weight: FontWeight.w800,
                          ).copyWith(color: _brandDeep),
                        ),
                        TextSpan(
                          text: amendments[i].reason,
                          style: AppType.body(
                            size: 13,
                            height: 1.5,
                          ).copyWith(color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(
                          text: 'Correction : ',
                          style: AppType.body(
                            size: 13,
                            weight: FontWeight.w800,
                          ).copyWith(color: _brandDeep),
                        ),
                        TextSpan(
                          text: amendments[i].text,
                          style: AppType.body(
                            size: 13,
                            height: 1.5,
                          ).copyWith(color: AppColors.textPrimary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SlipFooter extends StatelessWidget {
  const _SlipFooter();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: _brandDeep,
      child: Text(
        'This document is generated electronically and is valid without a physical signature.',
        textAlign: TextAlign.center,
        style: AppType.body(size: 11.5).copyWith(color: Colors.white),
      ),
    );
  }
}

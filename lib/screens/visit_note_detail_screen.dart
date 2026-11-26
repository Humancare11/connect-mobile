import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../models/visit_note_models.dart';
import '../services/document_saver.dart';
import '../services/visit_notes_service.dart';
import '../widgets/slips/slip_pdf_view.dart';
import '../widgets/visit_note_widgets.dart';
import 'visit_note_pdf.dart';

/// "Visit Note Preview" for the patient: the signed note shown as the PDF
/// paper itself, with a Download PDF button. Read only (only the doctor can
/// add amendments). Same content as the web `/user/my-visit-notes/:reportId`.
class VisitNoteDetailScreen extends StatefulWidget {
  const VisitNoteDetailScreen({
    super.key,
    required this.reportId,
    this.service,
    this.documentSaver,
  });

  final String reportId;

  // Injectable for tests; the defaults are the real service / file saver.
  final VisitNotesService? service;
  final DocumentSaver? documentSaver;

  @override
  State<VisitNoteDetailScreen> createState() => _VisitNoteDetailScreenState();
}

class _VisitNoteDetailScreenState extends State<VisitNoteDetailScreen> {
  late final VisitNotesService _service =
      widget.service ?? VisitNotesService();

  VisitNoteReport? _report;
  Uint8List? _signature;
  String _country = '';
  // The document is drawn once the signature and country have been tried.
  bool _extrasLoaded = false;
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
      _extrasLoaded = false;
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
      _extrasLoaded = true;
    });
  }

  late final DocumentSaver _saver =
      widget.documentSaver ?? const DocumentSaver();

  /// Everything that shows on the paper.
  String _version(VisitNoteReport report) => [
    report.id,
    report.reportNumber,
    report.patientName,
    report.patientGender,
    report.patientDob,
    report.patientAge,
    report.consultationWhen,
    report.modeLabel,
    report.symptoms,
    report.clinicalFindings,
    report.plan,
    report.note,
    report.physicianName,
    report.physicianRegistrationNumber,
    report.physicianSpeciality,
    report.signedAt,
    for (final a in report.amendments) ...[
      a.authorName,
      a.reason,
      a.text,
      a.createdAt,
    ],
    _country,
    _signature != null,
  ].join('\u001f');

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
      SavedDocument document;
      try {
        document = await _saver.save(
          bytes,
          'visit-note_${report.reportNumber}.pdf',
        );
      } catch (_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text(DocumentSaver.downloadFailedText)),
        );
        return;
      }
      if (!mounted) return;
      // The screen picks up a signature that only the download got.
      setState(() => _signature = signature ?? _signature);
      await announceSaved(
        ScaffoldMessenger.of(context),
        _saver,
        document,
        navigator: Navigator.of(context, rootNavigator: true),
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
          if (_extrasLoaded)
            // The same PDF the Download button saves.
            SlipPdfView(
              key: ValueKey('visit note ${report.id}'),
              label: 'Visit Note',
              version: _version(report),
              buildPdf: () => VisitNotePdf.build(
                report,
                signature: _signature,
                countryName: _country,
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: CircularProgressIndicator(color: AppColors.primary),
              ),
            ),
        ],
      ),
    );
  }
}


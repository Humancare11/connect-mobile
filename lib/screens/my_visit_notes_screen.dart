import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

import '../config/app_design_system.dart';
import '../models/visit_note_models.dart';
import '../services/visit_notes_service.dart';
import '../widgets/visit_note_widgets.dart';
import 'visit_note_detail_screen.dart';
import 'visit_note_pdf.dart';

/// Patient "My Visit Notes": finalised Visit Notes (newest first), with
/// completed consultations that have no signed note yet shown inline as
/// "Report pending". Drafts are never sent to the patient. Same behaviour as
/// the web `/user/my-visit-notes` page.
class MyVisitNotesScreen extends StatefulWidget {
  const MyVisitNotesScreen({super.key, this.service, this.sharePdf});

  // Injectable for tests; the defaults are the real service / sharing sheet.
  final VisitNotesService? service;
  final Future<void> Function(Uint8List bytes, String filename)? sharePdf;

  @override
  State<MyVisitNotesScreen> createState() => _MyVisitNotesScreenState();
}

class _MyVisitNotesScreenState extends State<MyVisitNotesScreen> {
  late final VisitNotesService _service =
      widget.service ?? VisitNotesService();

  List<VisitNoteListItem> _items = const [];
  bool _loading = true;
  String _error = '';
  String _downloadingId = '';

  @override
  void initState() {
    super.initState();
    _load(withLoader: true);
  }

  Future<void> _load({bool withLoader = false}) async {
    if (withLoader) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }
    final result = await _service.fetchMine(silent: true);
    if (!mounted) return;
    setState(() {
      _loading = false;
      if (result.success && result.data != null) {
        _items = result.data!.items;
        _error = '';
      } else {
        _error = result.message.isNotEmpty
            ? result.message
            : 'Could not load your Visit Notes.';
      }
    });
  }

  static Future<void> _defaultSharePdf(Uint8List bytes, String filename) =>
      Printing.sharePdf(bytes: bytes, filename: filename);

  Future<void> _download(VisitNoteReport report) async {
    if (_downloadingId.isNotEmpty) return;
    setState(() => _downloadingId = report.id);
    try {
      // A missing signature image must not block the download (web does the
      // same): the PDF is created without it.
      final signature = await _service.fetchSignatureWithRetry(report.id);
      final country = await _service.countryName(report.physicianCountry);
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
      if (mounted) setState(() => _downloadingId = '');
    }
  }

  void _open(VisitNoteReport report) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VisitNoteDetailScreen(
          reportId: report.id,
          service: _service,
          sharePdf: widget.sharePdf,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kVisitNoteCanvas,
      appBar: AppBar(
        title: Text(
          'My Visit Notes',
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
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _load(),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              if (_error.isNotEmpty) ...[
                VisitNoteErrorBanner(
                  message: _error,
                  onRetry: () => _load(withLoader: true),
                ),
                const SizedBox(height: 14),
              ],
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PATIENT ACCOUNT',
          style: AppType.body(
            size: 12,
            weight: FontWeight.w700,
          ).copyWith(color: AppColors.primary, letterSpacing: 1.1),
        ),
        const SizedBox(height: 6),
        Text('My Visit Notes', style: AppType.display(size: 25, height: 1.1)),
        const SizedBox(height: 6),
        Text(
          'All your consultation notes, newest first. Drafts are never shown here.',
          style: AppType.body(
            size: 14,
          ).copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 56),
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'Loading...',
              style: AppType.body(
                size: 13,
              ).copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    // A failed load already shows the banner above; an "empty" state would
    // wrongly say there is nothing.
    if (_items.isEmpty) {
      if (_error.isNotEmpty) return const SizedBox.shrink();
      return const VisitNoteEmptyState(
        icon: Icons.assignment_outlined,
        title: 'No consultations yet',
        message: "Your doctor's signed notes will appear here.",
      );
    }

    return Column(
      children: _items.map((item) {
        final report = item.report;
        return report != null
            ? _reportCard(report)
            : _pendingCard(item.pending!);
      }).toList(),
    );
  }

  Widget _iconBox(IconData icon) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Icon(icon, color: AppColors.primary, size: 24),
    );
  }

  Widget _reportCard(VisitNoteReport report) {
    final downloading = _downloadingId == report.id;
    final physician = report.physicianName.trim().isEmpty
        ? 'Doctor'
        : report.physicianName;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: visitNoteCardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _iconBox(Icons.assignment_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatVisitNoteDate(report.displayDate),
                      style: AppType.body(
                        size: 16,
                        weight: FontWeight.w800,
                      ).copyWith(color: AppColors.textPrimary),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        const VisitNoteTag(
                          label: 'Signed',
                          color: AppColors.success,
                        ),
                        if (report.isAmended)
                          const VisitNoteTag(
                            label: 'Amended',
                            color: AppColors.warning,
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '$physician · Video consultation · ${report.reportNumber}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppType.body(
                        size: 12.5,
                      ).copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: () => _open(report),
                icon: const Icon(Icons.visibility_outlined, size: 17),
                label: const Text('View'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
              TextButton.icon(
                onPressed: downloading ? null : () => _download(report),
                icon: downloading
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 17),
                label: const Text('Download PDF'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _pendingCard(VisitNotePending pending) {
    final who = pending.doctorName.trim().isNotEmpty
        ? '${pending.doctorName} is preparing this note'
        : 'Your doctor is preparing this note';
    final time = pending.time.trim().isNotEmpty ? ' · ${pending.time}' : '';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: visitNoteCardDecoration(),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _iconBox(Icons.hourglass_empty_rounded),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  formatVisitNoteDate(pending.date),
                  style: AppType.body(
                    size: 16,
                    weight: FontWeight.w800,
                  ).copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: 6),
                const VisitNoteTag(
                  label: 'Report pending',
                  color: AppColors.textSecondary,
                ),
                const SizedBox(height: 6),
                Text(
                  '$who$time',
                  style: AppType.body(
                    size: 12.5,
                  ).copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

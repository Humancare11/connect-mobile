import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../config/app_design_system.dart';
import '../models/medical_record_models.dart';
import '../pdf/slip_pdf.dart';
import '../services/document_saver.dart';
import '../services/document_signature_service.dart';
import '../services/medical_records_service.dart';
import '../services/socket_service.dart';
import '../services/token_storage_service.dart';
import '../services/visit_notes_service.dart';

enum _RecordsTab { prescriptions, certificates, reports }

// ── Shared brand-colour helpers ───────────────────────────────────────────────
// The "slip" facsimiles and the exported PDFs used to hardcode a blue medical
// palette. Both now derive from AppColors.primary so the whole app — screen,
// document preview, and downloaded PDF — shares one accent colour.
Color get _brand => AppColors.primary;
Color get _brandDeep => AppColors.primaryDeep;
Color get _brandTint => AppColors.primary.withValues(alpha: 0.08);


class MyRecordsPage extends StatefulWidget {
  const MyRecordsPage({
    super.key,
    this.initialTab = 'prescriptions',
    this.recordsService,
    this.signatureService,
    this.documentSaver,
    this.enableRealtime = true,
  });

  final String initialTab;

  // Injectable for tests; the defaults are the real services / file saver.
  final MedicalRecordsService? recordsService;
  final DocumentSignatureService? signatureService;
  final DocumentSaver? documentSaver;
  final bool enableRealtime;

  @override
  State<MyRecordsPage> createState() => _MyRecordsPageState();
}

class _MyRecordsPageState extends State<MyRecordsPage>
    with WidgetsBindingObserver {
  late final MedicalRecordsService _recordsService =
      widget.recordsService ?? MedicalRecordsService();
  late final DocumentSaver _saver =
      widget.documentSaver ?? const DocumentSaver();
  late final DocumentSignatureService _signatures =
      widget.signatureService ?? DocumentSignatureService();
  final Set<String> _loadingSignatures = {};
  final _tokenStorage = const TokenStorageService();
  Timer? _refreshTimer;
  DateTime? _lastFetchAt;

  // See the matching comment in appointments_screen.dart — resume and
  // socket-reconnect can both fire moments apart for the same backgrounding
  // event, so a background refresh that just ran doesn't need repeating.
  static const _minBackgroundRefreshInterval = Duration(seconds: 5);

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);
  // Warning banner accent (kept distinct from the brand colour on purpose).
  static const Color _warnBg = Color(0xFFFFF7ED);
  static const Color _warnBorder = Color(0xFFFED7AA);
  static const Color _warnIcon = Color(0xFFC2410C);
  static const Color _warnText = Color(0xFF9A3412);

  _RecordsTab _activeTab = _RecordsTab.prescriptions;
  List<PrescriptionRecord> _prescriptions = const [];
  List<MedicalCertificateRecord> _certificates = const [];
  List<MedicalReportRecord> _reports = const [];
  final Map<_RecordsTab, GlobalKey> _tabKeys = {
    for (final tab in _RecordsTab.values) tab: GlobalKey(),
  };
  Map<String, String> _patient = const {};
  String? _expandedId;
  String _error = '';
  String _downloadingId = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _activeTab = switch (widget.initialTab) {
      'certificates' => _RecordsTab.certificates,
      'reports' => _RecordsTab.reports,
      _ => _RecordsTab.prescriptions,
    };
    WidgetsBinding.instance.addPostFrameCallback((_) => _showActiveTab());
    _bootstrap();
    if (widget.enableRealtime) _connectRealtimeUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    if (widget.enableRealtime) {
      SocketService.instance.off('connect', _handleSocketConnected);
      SocketService.instance.off('new-prescription', _handleRealtimeUpdate);
      SocketService.instance.off('new-certificate', _handleRealtimeUpdate);
    }
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final patient = await _tokenStorage.getUserProfile();
    if (!mounted) return;
    setState(() => _patient = patient);
    await _loadRecords(withLoader: true);
  }

  /// Fetches the doctor's signature for a signed document (when its card is
  /// opened). A failure just leaves the slip's signature area empty; opening
  /// the card again retries.
  Future<void> _loadSignature(SignedDocumentKind kind, String id) async {
    if (_signatures.cached(kind, id) != null || !_loadingSignatures.add(id)) {
      return;
    }
    try {
      await _signatures.fetch(kind, id);
    } finally {
      _loadingSignatures.remove(id);
    }
    if (mounted) setState(() {});
  }

  /// The signature to embed in an exported PDF: `null` for an unsigned
  /// document. For a signed one it is loaded (with one retry) — if it still
  /// can't be, the export is stopped rather than producing a document that
  /// looks signed but has no signature.
  Future<Uint8List?> _signatureForExport(
    SignedDocumentKind kind,
    String id,
    bool isSigned,
  ) async {
    if (!isSigned) return null;
    final bytes = await _signatures.fetchWithRetry(kind, id);
    if (bytes == null) throw const _SignatureUnavailable();
    if (mounted) setState(() {});
    return bytes;
  }

  Future<void> _loadRecords({bool withLoader = false}) async {
    // Only block the screen with a spinner when there's nothing on it yet —
    // see the matching comment in appointments_screen.dart.
    final hasData = _prescriptions.isNotEmpty ||
        _certificates.isNotEmpty ||
        _reports.isNotEmpty;
    final showLoader = withLoader && !hasData;
    if (withLoader && mounted) {
      setState(() {
        _loading = showLoader;
        _error = '';
      });
    }

    // Always silent: this screen already renders its own loading state
    // above (the block right below), so the app-wide overlay would just be
    // a second, redundant spinner stacked on top of it.
    _lastFetchAt = DateTime.now();
    final snapshot = await _recordsService.fetchMyRecords(silent: true);
    if (!mounted) return;

    setState(() {
      _prescriptions = snapshot.prescriptions;
      _certificates = snapshot.certificates;
      _reports = snapshot.reports;
      _error = snapshot.error;
      _loading = false;
    });
  }

  Future<void> _connectRealtimeUpdates() async {
    WidgetsBinding.instance.addObserver(this);
    SocketService.instance.on('connect', _handleSocketConnected);
    SocketService.instance.on('new-prescription', _handleRealtimeUpdate);
    SocketService.instance.on('new-certificate', _handleRealtimeUpdate);

    if (SocketService.instance.connected) {
      await _joinPatientRoom();
    } else {
      SocketService.instance.connect();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _joinPatientRoom();
      _queueBackgroundRefresh();
    }
  }

  void _handleSocketConnected(dynamic _) {
    _joinPatientRoom();
    _queueBackgroundRefresh();
  }

  void _handleRealtimeUpdate(dynamic _) {
    _queueRefresh();
  }

  // See the matching comment in appointments_screen.dart.
  void _queueBackgroundRefresh() {
    final lastFetchAt = _lastFetchAt;
    if (lastFetchAt != null &&
        DateTime.now().difference(lastFetchAt) < _minBackgroundRefreshInterval) {
      return;
    }
    _queueRefresh();
  }

  void _queueRefresh() {
    _refreshTimer?.cancel();
    _refreshTimer = Timer(const Duration(milliseconds: 250), () {
      _refreshTimer = null;
      if (mounted) _loadRecords();
    });
  }

  Future<void> _joinPatientRoom() async {
    final profile = await _tokenStorage.getUserProfile();
    final userId = (profile['userId'] ?? '').trim();
    if (userId.isEmpty || !SocketService.instance.connected) return;

    SocketService.instance.emit('user-online', {
      'userId': userId,
      'role': 'user',
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: Text(
          'My Medical Records',
          style: AppType.body(size: 18, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _loadRecords(withLoader: true),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
            children: [
              _buildHeader(),
              const SizedBox(height: 16),
              _buildSummaryCards(),
              if (_error.isNotEmpty) ...[
                const SizedBox(height: 14),
                _buildErrorBanner(),
              ],
              const SizedBox(height: 16),
              _buildTabs(),
              const SizedBox(height: 18),
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
          'HUMANCARE CONNECT',
          style: AppType.body(size: 12, weight: FontWeight.w700)
              .copyWith(color: AppColors.primary, letterSpacing: 1.1),
        ),
        const SizedBox(height: 6),
        Text(
          'My Medical Records',
          style: AppType.display(size: 25, height: 1.1),
        ),
        const SizedBox(height: 6),
        Text(
          'Prescriptions and certificates from your consultations',
          style: AppType.body(size: 14)
              .copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }

  Widget _buildSummaryCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final cards = [
          Expanded(
            child: _summaryCard(
              icon: Icons.medication_outlined,
              count: _prescriptions.length,
              label: 'Prescriptions',
            ),
          ),
          const SizedBox(width: 12, height: 12),
          Expanded(
            child: _summaryCard(
              icon: Icons.description_outlined,
              count: _certificates.length,
              label: 'Certificates',
            ),
          ),
        ];
        final reportsCard = _summaryCard(
          icon: Icons.medical_services_outlined,
          count: _reports.length,
          label: 'Reports',
        );

        if (constraints.maxWidth < 360) {
          return Column(
            children: [
              _summaryCard(
                icon: Icons.medication_outlined,
                count: _prescriptions.length,
                label: 'Prescriptions',
              ),
              const SizedBox(height: 12),
              _summaryCard(
                icon: Icons.description_outlined,
                count: _certificates.length,
                label: 'Certificates',
              ),
              const SizedBox(height: 12),
              reportsCard,
            ],
          );
        }

        return Column(
          children: [
            Row(children: cards),
            const SizedBox(height: 12),
            reportsCard,
          ],
        );
      },
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required int count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: _brandTint,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('$count', style: AppType.display(size: 22)),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(size: 13)
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _warnBg,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: _warnBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: _warnIcon),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error,
              style: AppType.body(size: 13, weight: FontWeight.w600)
                  .copyWith(color: _warnText),
            ),
          ),
          TextButton(
            onPressed: () => _loadRecords(withLoader: true),
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppColors.border),
      ),
      // Three tabs are wider than a phone, so the bar scrolls sideways; each
      // tab keeps its own look and takes its natural width.
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _tabButton(
              tab: _RecordsTab.prescriptions,
              icon: Icons.medication_outlined,
              label: 'Prescriptions',
              count: _prescriptions.length,
            ),
            _tabButton(
              tab: _RecordsTab.certificates,
              icon: Icons.description_outlined,
              label: 'Medical Certificates',
              count: _certificates.length,
            ),
            _tabButton(
              tab: _RecordsTab.reports,
              icon: Icons.medical_services_outlined,
              label: 'Reports',
              count: _reports.length,
            ),
          ],
        ),
      ),
    );
  }

  /// Scrolls the tab bar so the selected tab is fully visible (e.g. when the
  /// page opens straight on Reports).
  void _showActiveTab() {
    final context = _tabKeys[_activeTab]?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: const Duration(milliseconds: 200),
      alignment: 0.5,
    );
  }

  Widget _tabButton({
    required _RecordsTab tab,
    required IconData icon,
    required String label,
    required int count,
  }) {
    final active = _activeTab == tab;
    // Not Expanded: the tab bar scrolls, so each tab sizes to its content.
    return Padding(
      padding: EdgeInsets.zero,
      child: InkWell(
        key: _tabKeys[tab],
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () {
          setState(() {
            _activeTab = tab;
            _expandedId = null;
          });
          _showActiveTab();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            color: active ? AppColors.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: active ? Colors.white : AppColors.textSecondary,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(size: 12.5, weight: FontWeight.w800)
                      .copyWith(
                    color: active ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.18)
                      : _brandTint,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  '$count',
                  style: AppType.body(size: 11, weight: FontWeight.w800)
                      .copyWith(
                    color: active ? Colors.white : AppColors.primary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
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
              'Loading records...',
              style: AppType.body(size: 13)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_activeTab == _RecordsTab.prescriptions) {
      if (_prescriptions.isEmpty) {
        return _emptyState(
          icon: Icons.medication_outlined,
          title: 'No prescriptions yet',
          message:
              'Prescriptions from your doctors will appear here after a completed consultation.',
        );
      }
      return Column(
        children: _prescriptions.map(_buildPrescriptionCard).toList(),
      );
    }

    if (_activeTab == _RecordsTab.reports) {
      if (_reports.isEmpty) {
        return _emptyState(
          icon: Icons.medical_services_outlined,
          title: 'No medical reports yet',
          message: 'Medical reports issued to you will appear here.',
        );
      }
      return Column(children: _reports.map(_buildReportCard).toList());
    }

    if (_certificates.isEmpty) {
      return _emptyState(
        icon: Icons.description_outlined,
        title: 'No certificates yet',
        message:
            'Medical certificates issued by your doctors will appear here.',
      );
    }

    return Column(children: _certificates.map(_buildCertificateCard).toList());
  }

  Widget _buildPrescriptionCard(PrescriptionRecord record) {
    final open = _expandedId == record.id;
    final doctorName = record.doctor.name.trim();
    final createdAt = _formatDate(record.createdAt);
    final appointmentDate = _formatDate(record.appointment.date);
    final subtitleParts = [
      doctorName.isNotEmpty ? 'Dr. $doctorName' : 'Dr. -',
      createdAt,
      if (record.appointment.date.trim().isNotEmpty) 'Appt: $appointmentDate',
    ];

    return _recordCard(
      id: record.id,
      icon: Icons.medication_outlined,
      title: record.diagnosis.isNotEmpty ? record.diagnosis : '-',
      subtitle: subtitleParts.join(' · '),
      open: open,
      onDownload: () => _downloadPrescription(record),
      onExpand: record.isSigned
          ? () => _loadSignature(SignedDocumentKind.prescription, record.id)
          : null,
      child: _PrescriptionSlip(
        record: record,
        patient: _patient,
        signature: _signatures.cached(SignedDocumentKind.prescription, record.id),
      ),
    );
  }

  Widget _buildCertificateCard(MedicalCertificateRecord record) {
    final open = _expandedId == record.id;
    final doctorName = record.doctor.name.trim();
    final issuedDate = _formatDate(
      record.issuedDate.isNotEmpty ? record.issuedDate : record.createdAt,
    );

    return _recordCard(
      id: record.id,
      icon: Icons.description_outlined,
      title: record.diagnosis.isNotEmpty ? record.diagnosis : '-',
      subtitle:
          '${doctorName.isNotEmpty ? 'Dr. $doctorName' : 'Dr. -'} · Issued: $issuedDate',
      open: open,
      onDownload: () => _downloadCertificate(record),
      onExpand: record.isSigned
          ? () => _loadSignature(SignedDocumentKind.certificate, record.id)
          : null,
      child: _CertificateSlip(
        record: record,
        patient: _patient,
        signature: _signatures.cached(SignedDocumentKind.certificate, record.id),
      ),
    );
  }

  /// An admin-issued medical report: the same card as a prescription or
  /// certificate, but static (the report is a PDF opened from the server, so
  /// there is nothing to expand). A voided report stays in the list, dimmed and
  /// flagged, without a PDF button.
  Widget _buildReportCard(MedicalReportRecord report) {
    final voided = report.isVoided;
    final isOpening = _downloadingId == report.id;
    final doctorName = report.doctorName.trim();
    final subtitle = [
      doctorName.isNotEmpty ? doctorName : 'Humancare',
      _formatDate(report.reportDate),
      if (report.reportNumber.trim().isNotEmpty) report.reportNumber.trim(),
    ].join(' · ');

    return Opacity(
      opacity: voided ? 0.75 : 1,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: _cardDecoration(),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _brandTint,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Icon(
                Icons.medical_services_outlined,
                color: AppColors.primary,
                size: 24,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text.rich(
                    TextSpan(
                      text: report.title.isNotEmpty ? report.title : '-',
                      children: [
                        if (voided)
                          WidgetSpan(
                            alignment: PlaceholderAlignment.middle,
                            child: Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _voidedBadge(),
                            ),
                          ),
                      ],
                    ),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(size: 16, weight: FontWeight.w800)
                        .copyWith(color: AppColors.textPrimary),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.body(size: 12.5)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  if (voided) ...[
                    const SizedBox(height: 4),
                    Text(
                      'This report is no longer valid. A corrected report may be issued separately.',
                      style: AppType.body(size: 12.5)
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ],
              ),
            ),
            if (!voided) ...[
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: isOpening ? null : () => _openReport(report),
                icon: isOpening
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.download_rounded, size: 17),
                label: const Text('PDF'),
                style: TextButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Same pill as the tab's count badge, in the warning (amber) colour.
  Widget _voidedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        'Voided',
        style: AppType.body(size: 11, weight: FontWeight.w800)
            .copyWith(color: AppColors.amberInk),
      ),
    );
  }

  /// Asks the server for a short-lived link to the report PDF, downloads it
  /// inside the app and saves it to the phone (like the invoice in Payment
  /// History).
  Future<void> _openReport(MedicalReportRecord report) async {
    if (_downloadingId.isNotEmpty) return;
    setState(() => _downloadingId = report.id);
    try {
      final result = await _recordsService.fetchReportDownloadLink(
        report.id,
        silent: true,
      );
      if (!mounted) return;
      if (!result.success || result.data == null) {
        _showSnack(
          result.message.isNotEmpty
              ? result.message
              : 'Could not open the report. Please try again.',
        );
        return;
      }

      final uri = Uri.tryParse(result.data!.url);
      SavedDocument? document;
      if (uri != null) {
        try {
          final bytes = await _saver.fetch(uri);
          final number = result.data!.reportNumber.isNotEmpty
              ? result.data!.reportNumber
              : report.reportNumber;
          document = await _saver.save(
            bytes,
            'report_${number.isNotEmpty ? number : report.id}.pdf',
          );
        } catch (_) {
          document = null;
        }
      }
      if (document == null) {
        _showSnack(DocumentSaver.downloadFailedText);
        return;
      }
      if (!mounted) return;
      await announceSaved(ScaffoldMessenger.of(context), _saver, document);
    } finally {
      if (mounted) setState(() => _downloadingId = '');
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _recordCard({
    required String id,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool open,
    required VoidCallback onDownload,
    required Widget child,
    VoidCallback? onExpand,
  }) {
    final isDownloading = _downloadingId == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() => _expandedId = open ? null : id);
              if (!open) onExpand?.call();
            },
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: _brandTint,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, color: AppColors.primary, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body(size: 16, weight: FontWeight.w800)
                              .copyWith(color: AppColors.textPrimary),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body(size: 12.5)
                              .copyWith(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: isDownloading ? null : onDownload,
                    icon: isDownloading
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded, size: 17),
                    label: const Text('PDF'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: Icon(Icons.keyboard_arrow_down_rounded,
                        color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: child,
            ),
            crossFadeState: open
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 180),
          ),
        ],
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: _cardDecoration(),
      child: Column(
        children: [
          Icon(icon, size: 48, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.display(size: 18),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.body(size: 13)
                .copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadPrescription(PrescriptionRecord record) async {
    final patientName = _safeFileSegment(_patient['name'] ?? 'patient');
    final date = record.createdAt.isNotEmpty
        ? (DateTime.tryParse(
                record.createdAt,
              )?.toIso8601String().split('T').first ??
              'rx')
        : 'rx';
    await _runPdfExport(
      id: record.id,
      filename: 'prescription_${patientName}_$date.pdf',
      builder: () => _buildPrescriptionPdf(record),
    );
  }

  Future<void> _downloadCertificate(MedicalCertificateRecord record) async {
    final patientName = _safeFileSegment(_patient['name'] ?? 'patient');
    final date = record.issuedDate.isNotEmpty
        ? record.issuedDate
        : (DateTime.tryParse(
                record.createdAt,
              )?.toIso8601String().split('T').first ??
              'cert');
    await _runPdfExport(
      id: record.id,
      filename: 'certificate_${patientName}_$date.pdf',
      builder: () => _buildCertificatePdf(record),
    );
  }

  Future<void> _runPdfExport({
    required String id,
    required String filename,
    required Future<Uint8List> Function() builder,
  }) async {
    setState(() => _downloadingId = id);
    try {
      final bytes = await builder();
      SavedDocument document;
      try {
        document = await _saver.save(bytes, filename);
      } catch (_) {
        _showSnack(DocumentSaver.downloadFailedText);
        return;
      }
      if (!mounted) return;
      await announceSaved(ScaffoldMessenger.of(context), _saver, document);
    } on _SignatureUnavailable {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            "Couldn't load the doctor's signature, so the PDF wasn't created. "
            'Please try again.',
          ),
        ),
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

  Future<Uint8List> _buildPrescriptionPdf(PrescriptionRecord record) async {
    final signature = await _signatureForExport(
      SignedDocumentKind.prescription,
      record.id,
      record.isSigned,
    );
    // Web shows the country as a name; the API sends the ISO code.
    String country = record.enrollment.country;
    try {
      country = await VisitNotesService().countryName(country);
    } catch (_) {}
    return SlipPdf.prescription(
      record,
      patient: _patient,
      signature: signature,
      country: country,
    );
  }

  Future<Uint8List> _buildCertificatePdf(
    MedicalCertificateRecord record,
  ) async {
    final signature = await _signatureForExport(
      SignedDocumentKind.certificate,
      record.id,
      record.isSigned,
    );
    return SlipPdf.certificate(
      record,
      patient: _patient,
      signature: signature,
    );
  }

  String _safeFileSegment(String value) {
    final trimmed = value.trim().isEmpty ? 'patient' : value.trim();
    return trimmed
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
  }

  String _formatDate(dynamic value) {
    final text = value?.toString().trim() ?? '';
    if (text.isEmpty) return '-';
    final date = DateTime.tryParse(text);
    if (date == null) return text;
    return DateFormat('dd MMM yyyy').format(date.toLocal());
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      border: Border.all(color: AppColors.border, width: 1.2),
      boxShadow: AppShadows.subtle,
    );
  }
}

/// "Digitally signed · 7 Nov 2026, 03:30 PM" (just "Digitally signed" when
/// the signing time is unknown).
String _signedCaption(String signedAt, {String separator = '·'}) {
  final date = DateTime.tryParse(signedAt);
  if (date == null) return 'Digitally signed';
  return 'Digitally signed $separator ${DateFormat('d MMM yyyy, hh:mm a').format(date.toLocal())}';
}

/// Thrown when a signed document's signature could not be loaded for a PDF
/// export (see `_signatureForExport`).
class _SignatureUnavailable implements Exception {
  const _SignatureUnavailable();
}

/// The doctor's signature on a slip: label, the image (56px high) and a
/// "Digitally signed" caption. While the image is still loading — or if it
/// could not be loaded — the space is kept empty so the layout doesn't jump.
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
          style: AppType.body(size: 12, weight: FontWeight.w800)
              .copyWith(color: _brand),
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
          _signedCaption(signedAt),
          style: AppType.body(size: 11).copyWith(color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

class _PrescriptionSlip extends StatelessWidget {
  const _PrescriptionSlip({
    required this.record,
    required this.patient,
    this.signature,
  });

  final PrescriptionRecord record;
  final Map<String, String> patient;
  final Uint8List? signature;

  @override
  Widget build(BuildContext context) {
    return _SlipShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SlipHeader(),
          _Banner(
            title: 'Medical Prescription',
            subtitle: 'Diagnosis - ${record.diagnosis}',
            code: _code(record.id),
            date: 'Issued ${_format(record.createdAt)}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _InfoPanel(
                    label: 'Patient',
                    rows: [
                      ['Name', patient['name'] ?? '-'],
                      ['Age / Sex', _ageSex(patient)],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _InfoPanel(
                    label: 'Physician',
                    rows: [
                      [
                        'Name',
                        'Dr. ${record.doctor.name.isNotEmpty ? record.doctor.name : '-'}',
                      ],
                      ['Reg. No.', '-'],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 18, 14, 0),
            child: Text(
              'Rx',
              style: TextStyle(
                fontSize: 28,
                color: _brandDeep,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
            child: _MedicineTable(medicines: record.medicines),
          ),
          Container(
            margin: const EdgeInsets.all(14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _brandTint,
              border: Border(left: BorderSide(color: _brandDeep, width: 3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _richLine(
                  'Instructions',
                  record.instructions.isNotEmpty ? record.instructions : '-',
                ),
                const SizedBox(height: 5),
                _richLine(
                  'Follow-up date',
                  record.followUpDate.isNotEmpty
                      ? _format(record.followUpDate)
                      : '-',
                ),
              ],
            ),
          ),
          if (record.isSigned)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
              child: _SignatureBlock(
                signedAt: record.signedAt,
                signature: signature,
              ),
            ),
          const _SlipFooter(),
        ],
      ),
    );
  }

  static Widget _richLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: AppType.body(size: 12.5).copyWith(color: AppColors.textSecondary),
        children: [
          TextSpan(
            text: '$label: ',
            style: TextStyle(color: _brand, fontWeight: FontWeight.w800),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }

  static String _format(String value) {
    final date = DateTime.tryParse(value);
    if (date == null) return value.trim().isEmpty ? '-' : value;
    return DateFormat('dd MMM yyyy').format(date.toLocal());
  }

  static String _ageSex(Map<String, String> patient) {
    final dob = DateTime.tryParse(patient['dob'] ?? '');
    final gender = patient['gender'] ?? '';
    var age = '';
    if (dob != null) {
      final now = DateTime.now();
      var years = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        years -= 1;
      }
      if (years > 0) age = '$years yrs';
    }
    final parts = [if (age.isNotEmpty) age, if (gender.isNotEmpty) gender];
    return parts.isEmpty ? '-' : parts.join(' / ');
  }

  static String _code(String id) {
    final suffix = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'HC-${suffix.toUpperCase()}';
  }
}

class _CertificateSlip extends StatelessWidget {
  const _CertificateSlip({
    required this.record,
    required this.patient,
    this.signature,
  });

  final MedicalCertificateRecord record;
  final Map<String, String> patient;
  final Uint8List? signature;

  @override
  Widget build(BuildContext context) {
    final patientName = (patient['name'] ?? '').isNotEmpty
        ? patient['name']!
        : 'the patient';
    final ageSex = _PrescriptionSlip._ageSex(patient);
    final issuedDate = record.issuedDate.isNotEmpty
        ? record.issuedDate
        : record.createdAt;

    return _SlipShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _SlipHeader(),
          _Banner(
            title: 'Medical Certificate',
            subtitle: 'Reason: ${record.diagnosis}',
            code: _code(record.id),
            date: 'Issued ${_PrescriptionSlip._format(issuedDate)}',
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Wrap(
              runSpacing: 10,
              spacing: 10,
              children: [
                SizedBox(
                  width: 280,
                  child: _InfoPanel(
                    label: 'Patient',
                    rows: [
                      ['Patient Name', patientName],
                      ['Age / Sex', ageSex],
                    ],
                  ),
                ),
                SizedBox(
                  width: 280,
                  child: _InfoPanel(
                    label: 'Document',
                    rows: [
                      ['Date of Issue', _PrescriptionSlip._format(issuedDate)],
                      if ((patient['dob'] ?? '').isNotEmpty)
                        [
                          'Date of Birth',
                          _PrescriptionSlip._format(patient['dob']!),
                        ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(14, 16, 14, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: AppColors.border, width: 1.4),
            ),
            child: Text(
              'This is to certify that $patientName, $ageSex, has been examined and is suffering from ${record.diagnosis}.',
              style: AppType.body(size: 13, height: 1.55)
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _CertificateDetailsTable(record: record),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _DoctorCertificateBox(record: record, signature: signature),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: Text(
              'Note: This certificate is issued based on the medical examination conducted via Humancare Connect telehealth platform. It is valid as an official medical document for the purpose stated above.',
              style: AppType.body(size: 11.5, height: 1.4)
                  .copyWith(color: const Color(0xFF92400E)),
            ),
          ),
          const _SlipFooter(lightFooter: true),
        ],
      ),
    );
  }

  static String _code(String id) {
    final suffix = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'HC-CERT-${suffix.toUpperCase()}';
  }
}

class _SlipShell extends StatelessWidget {
  const _SlipShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _brandTint,
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: 760,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(3),
            boxShadow: AppShadows.subtle,
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
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
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: _brandTint, width: 2)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/logo-2.png',
            height: 46,
            errorBuilder: (_, error, stackTrace) {
              return Text(
                'Humancare Connect',
                style: AppType.display(size: 18, color: _brandDeep),
              );
            },
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Global Health Passport',
                style: AppType.body(size: 11, weight: FontWeight.w900)
                    .copyWith(color: _brand, letterSpacing: 1.2),
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
  const _Banner({
    required this.title,
    required this.subtitle,
    required this.code,
    required this.date,
  });

  final String title;
  final String subtitle;
  final String code;
  final String date;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _brandTint,
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppType.body(size: 14, weight: FontWeight.w900)
                      .copyWith(color: _brandDeep),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: AppType.body(size: 12)
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                code,
                style: AppType.body(size: 12, weight: FontWeight.w900)
                    .copyWith(color: _brandDeep),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: AppType.body(size: 11)
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.label, required this.rows});

  final String label;
  final List<List<String>> rows;

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
            style: AppType.body(size: 10, weight: FontWeight.w900)
                .copyWith(color: _brand, letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    row[0],
                    style: AppType.body(size: 12)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.length > 1 && row[1].isNotEmpty ? row[1] : '-',
                      textAlign: TextAlign.right,
                      style: AppType.body(size: 12, weight: FontWeight.w800)
                          .copyWith(color: _brandDeep),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MedicineTable extends StatelessWidget {
  const _MedicineTable({required this.medicines});

  final List<PrescriptionMedicine> medicines;

  @override
  Widget build(BuildContext context) {
    final rows = medicines.isEmpty
        ? const [PrescriptionMedicine(name: '-')]
        : medicines;
    return Table(
      columnWidths: const {
        0: FixedColumnWidth(44),
        1: FlexColumnWidth(1.6),
        2: FlexColumnWidth(),
        3: FlexColumnWidth(),
        4: FlexColumnWidth(),
      },
      border: const TableBorder(
        horizontalInside: BorderSide(color: AppColors.border),
      ),
      children: [
        TableRow(
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: _brandDeep, width: 1.5)),
          ),
          children: [
            'No.',
            'Medicine',
            'Frequency',
            'Duration',
            'Notes',
          ].map((text) => _tableHeader(text)).toList(),
        ),
        ...rows.indexed.map((entry) {
          final med = entry.$2;
          return TableRow(
            children: [
              _tableCell('${entry.$1 + 1}'),
              _tableCell(
                [med.name, med.dosage].where((e) => e.isNotEmpty).join('\n'),
                bold: true,
              ),
              _tableCell(med.frequency),
              _tableCell(med.duration),
              _tableCell(med.notes),
            ],
          );
        }),
      ],
    );
  }

  static Widget _tableHeader(String text) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text.toUpperCase(),
        style: AppType.body(size: 10, weight: FontWeight.w900)
            .copyWith(color: AppColors.textSecondary),
      ),
    );
  }

  static Widget _tableCell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text.isEmpty ? '-' : text,
        style: AppType.body(
          size: 12,
          weight: bold ? FontWeight.w800 : FontWeight.w500,
          height: 1.25,
        ).copyWith(color: bold ? _brandDeep : AppColors.textPrimary),
      ),
    );
  }
}

class _CertificateDetailsTable extends StatelessWidget {
  const _CertificateDetailsTable({required this.record});

  final MedicalCertificateRecord record;

  @override
  Widget build(BuildContext context) {
    final rows = [
      ['Diagnosis / Condition', record.diagnosis],
      if (record.recommendation.isNotEmpty)
        ['Recommendation', record.recommendation],
      if (record.restFromDate.isNotEmpty || record.restToDate.isNotEmpty)
        ['Rest Period', _restPeriod(record.restFromDate, record.restToDate)],
      if (record.notes.isNotEmpty) ['Additional Notes', record.notes],
    ];

    return Table(
      border: TableBorder.all(color: AppColors.border),
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2.2)},
      children: [
        TableRow(
          decoration: BoxDecoration(color: _brand),
          children: ['Field', 'Details'].map((text) {
            return Padding(
              padding: const EdgeInsets.all(9),
              child: Text(
                text.toUpperCase(),
                style: AppType.body(size: 12, weight: FontWeight.w900)
                    .copyWith(color: Colors.white),
              ),
            );
          }).toList(),
        ),
        ...rows.map(
          (row) =>
              TableRow(children: [_cell(row[0], bold: true), _cell(row[1])]),
        ),
      ],
    );
  }

  static Widget _cell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.all(10),
      child: Text(
        text.isNotEmpty ? text : '-',
        style: AppType.body(
          size: 12.5,
          weight: bold ? FontWeight.w800 : FontWeight.w500,
          height: 1.35,
        ).copyWith(color: bold ? _brandDeep : AppColors.textPrimary),
      ),
    );
  }

  static String _restPeriod(String fromDate, String toDate) {
    if (fromDate.isNotEmpty && toDate.isNotEmpty) {
      return '${_PrescriptionSlip._format(fromDate)} to ${_PrescriptionSlip._format(toDate)}';
    }
    if (fromDate.isNotEmpty) {
      return 'From ${_PrescriptionSlip._format(fromDate)}';
    }
    return 'Until ${_PrescriptionSlip._format(toDate)}';
  }
}

class _DoctorCertificateBox extends StatelessWidget {
  const _DoctorCertificateBox({required this.record, this.signature});

  final MedicalCertificateRecord record;
  final Uint8List? signature;

  @override
  Widget build(BuildContext context) {
    final doctorName = record.doctor.name.isNotEmpty ? record.doctor.name : '-';
    final enrollment = record.enrollment;
    final subtitle = [
      enrollment.specialization,
      enrollment.qualification,
    ].where((value) => value.isNotEmpty).join(' - ');

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        border: Border.all(color: _brandTint),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: _brandTint,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: _brand,
                  child: Text(
                    doctorName.substring(0, 1).toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Dr. $doctorName',
                        style: AppType.body(size: 14, weight: FontWeight.w900)
                            .copyWith(color: _brandDeep),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: AppType.body(size: 11.5)
                              .copyWith(color: AppColors.textSecondary),
                        ),
                    ],
                  ),
                ),
                if (enrollment.medicalRegistrationNumber.isNotEmpty)
                  Text(
                    'Reg. No: ${enrollment.medicalRegistrationNumber}',
                    style: AppType.body(size: 11)
                        .copyWith(color: AppColors.textSecondary),
                  ),
              ],
            ),
          ),
          Container(
            color: AppColors.surface,
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      enrollment.clinicName.isNotEmpty
                          ? enrollment.clinicName
                          : 'Humancare Connect',
                      enrollment.clinicAddress.isNotEmpty
                          ? enrollment.clinicAddress
                          : '4 Peddlers Row #1091 Newark, DE 19702, United States',
                    ].join('\n'),
                    style: AppType.body(size: 12, height: 1.5)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ),
                const SizedBox(width: 12),
                if (record.isSigned)
                  // Signed: the doctor's signature replaces the
                  // "system-generated" note (as on the web).
                  SizedBox(
                    width: 210,
                    child: _SignatureBlock(
                      signedAt: record.signedAt,
                      signature: signature,
                    ),
                  )
                else
                  SizedBox(
                    width: 210,
                    child: Text(
                      'This is a system-generated certificate and does not require a signature or stamp.',
                      textAlign: TextAlign.center,
                      style: AppType.body(
                        size: 11,
                        height: 1.45,
                      ).copyWith(
                        color: AppColors.textSecondary,
                        fontStyle: FontStyle.italic,
                      ),
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
  const _SlipFooter({this.lightFooter = false});

  final bool lightFooter;

  @override
  Widget build(BuildContext context) {
    if (lightFooter) {
      return Container(
        padding: const EdgeInsets.all(12),
        color: _brandTint,
        child: Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: _brand, size: 46),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                '+1 (302) 303-9993\nsupport@humancareconnect.co\n4 Peddlers Row #1091 Newark, DE 19702, United States',
                style: AppType.body(size: 11.5, height: 1.45)
                    .copyWith(color: AppColors.textPrimary),
              ),
            ),
          ],
        ),
      );
    }

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
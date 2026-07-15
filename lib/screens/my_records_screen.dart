import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/medical_record_models.dart';
import '../services/medical_records_service.dart';
import '../services/socket_service.dart';
import '../services/token_storage_service.dart';

enum _RecordsTab { prescriptions, certificates }

class MyRecordsPage extends StatefulWidget {
  const MyRecordsPage({super.key, this.initialTab = 'prescriptions'});

  final String initialTab;

  @override
  State<MyRecordsPage> createState() => _MyRecordsPageState();
}

class _MyRecordsPageState extends State<MyRecordsPage>
    with WidgetsBindingObserver {
  final _recordsService = MedicalRecordsService();
  final _tokenStorage = const TokenStorageService();
  Timer? _refreshTimer;

  _RecordsTab _activeTab = _RecordsTab.prescriptions;
  List<PrescriptionRecord> _prescriptions = const [];
  List<MedicalCertificateRecord> _certificates = const [];
  Map<String, String> _patient = const {};
  String? _expandedId;
  String _error = '';
  String _downloadingId = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab == 'certificates'
        ? _RecordsTab.certificates
        : _RecordsTab.prescriptions;
    _bootstrap();
    _connectRealtimeUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    SocketService.instance.off('connect', _handleSocketConnected);
    SocketService.instance.off('new-prescription', _handleRealtimeUpdate);
    SocketService.instance.off('new-certificate', _handleRealtimeUpdate);
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final patient = await _tokenStorage.getUserProfile();
    if (!mounted) return;
    setState(() => _patient = patient);
    await _loadRecords(withLoader: true);
  }

  Future<void> _loadRecords({bool withLoader = false}) async {
    if (withLoader && mounted) {
      setState(() {
        _loading = true;
        _error = '';
      });
    }

    final snapshot = await _recordsService.fetchMyRecords();
    if (!mounted) return;

    setState(() {
      _prescriptions = snapshot.prescriptions;
      _certificates = snapshot.certificates;
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
      _queueRefresh();
    }
  }

  void _handleSocketConnected(dynamic _) {
    _joinPatientRoom();
    _queueRefresh();
  }

  void _handleRealtimeUpdate(dynamic _) {
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
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: AppBar(
        title: const Text(
          'My Medical Records',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF0B2545),
        elevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      body: SafeArea(
        child: RefreshIndicator(
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
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HUMANCARE CONNECT',
          style: TextStyle(
            color: Color(0xFF0D9488),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.1,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'My Medical Records',
          style: TextStyle(
            color: Color(0xFF111827),
            fontSize: 26,
            fontWeight: FontWeight.w900,
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Prescriptions and certificates from your consultations',
          style: TextStyle(color: Color(0xFF64748B), fontSize: 14),
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
            ],
          );
        }

        return Row(children: cards);
      },
    );
  }

  Widget _summaryCard({
    required IconData icon,
    required int count,
    required String label,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: const Color(0xFFE8F0FE),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: const Color(0xFF0D47A1), size: 24),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$count',
                  style: const TextStyle(
                    color: Color(0xFF111827),
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Color(0xFF64748B)),
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
        color: const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFED7AA)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFFC2410C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _error,
              style: const TextStyle(
                color: Color(0xFF9A3412),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          TextButton(
            onPressed: () => _loadRecords(withLoader: true),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
      ),
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
        ],
      ),
    );
  }

  Widget _tabButton({
    required _RecordsTab tab,
    required IconData icon,
    required String label,
    required int count,
  }) {
    final active = _activeTab == tab;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          setState(() {
            _activeTab = tab;
            _expandedId = null;
          });
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 11),
          decoration: BoxDecoration(
            color: active ? const Color(0xFF0D47A1) : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 17,
                color: active ? Colors.white : const Color(0xFF334155),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF334155),
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: active
                      ? Colors.white.withValues(alpha: 0.18)
                      : const Color(0xFFE8F0FE),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    color: active ? Colors.white : const Color(0xFF0D47A1),
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 56),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Loading records...'),
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
      iconColor: const Color(0xFF0D47A1),
      title: record.diagnosis.isNotEmpty ? record.diagnosis : '-',
      subtitle: subtitleParts.join(' - '),
      open: open,
      onDownload: () => _downloadPrescription(record),
      child: _PrescriptionSlip(record: record, patient: _patient),
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
      iconColor: const Color(0xFF0F766E),
      title: record.diagnosis.isNotEmpty ? record.diagnosis : '-',
      subtitle:
          '${doctorName.isNotEmpty ? 'Dr. $doctorName' : 'Dr. -'} - Issued: $issuedDate',
      open: open,
      onDownload: () => _downloadCertificate(record),
      child: _CertificateSlip(record: record, patient: _patient),
    );
  }

  Widget _recordCard({
    required String id,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required bool open,
    required VoidCallback onDownload,
    required Widget child,
  }) {
    final isDownloading = _downloadingId == id;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: _cardDecoration(),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expandedId = open ? null : id),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: iconColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Icon(icon, color: iconColor, size: 24),
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
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF64748B),
                            fontSize: 12.5,
                          ),
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
                      foregroundColor: const Color(0xFF0D47A1),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                  AnimatedRotation(
                    turns: open ? 0.5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(Icons.keyboard_arrow_down_rounded),
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
          Icon(icon, size: 48, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B)),
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
      await Printing.sharePdf(bytes: bytes, filename: filename);
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
    final pdf = pw.Document();
    final logo = await _loadPdfLogo();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => _pdfPrescriptionBody(record, logo),
      ),
    );
    return pdf.save();
  }

  Future<Uint8List> _buildCertificatePdf(
    MedicalCertificateRecord record,
  ) async {
    final pdf = pw.Document();
    final logo = await _loadPdfLogo();
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(24),
        build: (_) => _pdfCertificateBody(record, logo),
      ),
    );
    return pdf.save();
  }

  Future<pw.MemoryImage?> _loadPdfLogo() async {
    try {
      final bytes = await rootBundle.load('assets/Logo.png');
      return pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (_) {
      return null;
    }
  }

  pw.Widget _pdfPrescriptionBody(
    PrescriptionRecord record,
    pw.MemoryImage? logo,
  ) {
    final doctorName = record.doctor.name.isNotEmpty ? record.doctor.name : '-';
    final patientName = (_patient['name'] ?? '').isNotEmpty
        ? _patient['name']!
        : '-';
    final ageSex = _ageSex(_patient);
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue100),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _pdfHeader(logo),
          _pdfBanner(
            title: 'Medical Prescription',
            subtitle: 'Diagnosis - ${record.diagnosis}',
            code: _prescriptionCode(record.id),
            date: 'Issued ${_formatDate(record.createdAt)}',
          ),
          pw.SizedBox(height: 14),
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: _pdfInfoBox('Patient', [
                  ['Name', patientName],
                  ['Age / Sex', ageSex],
                ]),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _pdfInfoBox('Physician', [
                  ['Name', 'Dr. $doctorName'],
                  ['Reg. No.', '-'],
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Text(
            'Rx',
            style: pw.TextStyle(fontSize: 24, color: PdfColors.blue700),
          ),
          pw.SizedBox(height: 6),
          _pdfMedicineTable(record.medicines),
          pw.SizedBox(height: 18),
          _pdfNoteBox([
            [
              'Instructions',
              record.instructions.isNotEmpty ? record.instructions : '-',
            ],
            [
              'Follow-up date',
              record.followUpDate.isNotEmpty
                  ? _formatDate(record.followUpDate)
                  : '-',
            ],
          ]),
          pw.Spacer(),
          _pdfFooter(),
        ],
      ),
    );
  }

  pw.Widget _pdfCertificateBody(
    MedicalCertificateRecord record,
    pw.MemoryImage? logo,
  ) {
    final patientName = (_patient['name'] ?? '').isNotEmpty
        ? _patient['name']!
        : 'the patient';
    final doctorName = record.doctor.name.isNotEmpty ? record.doctor.name : '-';
    final issuedDate = record.issuedDate.isNotEmpty
        ? record.issuedDate
        : record.createdAt;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue100),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.stretch,
        children: [
          _pdfHeader(logo),
          _pdfBanner(
            title: 'Medical Certificate',
            subtitle: 'Reason: ${record.diagnosis}',
            code: _certificateCode(record.id),
            date: 'Issued ${_formatDate(issuedDate)}',
          ),
          pw.SizedBox(height: 16),
          pw.Row(
            children: [
              pw.Expanded(
                child: _pdfInfoBox('Patient', [
                  ['Patient Name', patientName],
                  ['Age / Sex', _ageSex(_patient)],
                ]),
              ),
              pw.SizedBox(width: 12),
              pw.Expanded(
                child: _pdfInfoBox('Document', [
                  ['Date of Issue', _formatDate(issuedDate)],
                  ['Date of Birth', _formatDate(_patient['dob'])],
                ]),
              ),
            ],
          ),
          pw.SizedBox(height: 16),
          pw.Container(
            padding: const pw.EdgeInsets.all(14),
            decoration: pw.BoxDecoration(
              color: PdfColors.blue50,
              border: pw.Border(
                left: pw.BorderSide(color: PdfColors.blue700, width: 3),
              ),
            ),
            child: pw.Text(
              'This is to certify that $patientName, ${_ageSex(_patient)}, has been examined and is suffering from ${record.diagnosis}.',
              style: const pw.TextStyle(fontSize: 12, lineSpacing: 4),
            ),
          ),
          pw.SizedBox(height: 14),
          _pdfDetailsTable(record),
          pw.SizedBox(height: 14),
          _pdfDoctorBox(record, doctorName),
          pw.SizedBox(height: 10),
          _pdfValidityNote(),
          pw.Spacer(),
          _pdfFooter(),
        ],
      ),
    );
  }

  pw.Widget _pdfHeader(pw.MemoryImage? logo) {
    return pw.Container(
      padding: const pw.EdgeInsets.fromLTRB(20, 14, 20, 14),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: PdfColors.blue100, width: 1.5),
        ),
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
                color: PdfColors.blue900,
              ),
            ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                'Global Health Passport',
                style: pw.TextStyle(
                  fontSize: 9,
                  color: PdfColors.blue700,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 5),
              pw.Container(width: 44, height: 3, color: PdfColors.blue700),
            ],
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfBanner({
    required String title,
    required String subtitle,
    required String code,
    required String date,
  }) {
    return pw.Container(
      color: PdfColors.blue50,
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: pw.Row(
        children: [
          pw.Expanded(
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  title,
                  style: pw.TextStyle(
                    fontSize: 13,
                    color: PdfColors.blue900,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
                pw.SizedBox(height: 3),
                pw.Text(
                  subtitle,
                  style: const pw.TextStyle(
                    fontSize: 10,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
          ),
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text(
                code,
                style: pw.TextStyle(
                  fontSize: 10,
                  color: PdfColors.blue900,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 3),
              pw.Text(
                date,
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

  pw.Widget _pdfInfoBox(String title, List<List<String>> rows) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue100),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            title.toUpperCase(),
            style: pw.TextStyle(
              fontSize: 9,
              color: PdfColors.blue700,
              fontWeight: pw.FontWeight.bold,
            ),
          ),
          pw.SizedBox(height: 8),
          ...rows.map(
            (row) => pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 5),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    row[0],
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey700,
                    ),
                  ),
                  pw.SizedBox(width: 8),
                  pw.Expanded(
                    child: pw.Text(
                      row[1].isNotEmpty ? row[1] : '-',
                      textAlign: pw.TextAlign.right,
                      style: pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.blue900,
                        fontWeight: pw.FontWeight.bold,
                      ),
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

  pw.Widget _pdfMedicineTable(List<PrescriptionMedicine> medicines) {
    final rows = medicines.isEmpty
        ? const [PrescriptionMedicine(name: '-')]
        : medicines;
    return pw.Table(
      border: pw.TableBorder(
        horizontalInside: const pw.BorderSide(color: PdfColors.grey300),
      ),
      columnWidths: const {
        0: pw.FixedColumnWidth(28),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(),
        3: pw.FlexColumnWidth(),
        4: pw.FlexColumnWidth(),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(color: PdfColors.blue900, width: 1.2),
            ),
          ),
          children: ['No.', 'Medicine', 'Frequency', 'Duration', 'Notes']
              .map(
                (text) => pw.Padding(
                  padding: const pw.EdgeInsets.all(7),
                  child: pw.Text(
                    text.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        ...rows.indexed.map((entry) {
          final med = entry.$2;
          return pw.TableRow(
            children: [
              _pdfCell('${entry.$1 + 1}'),
              _pdfCell(
                med.dosage.isNotEmpty ? '${med.name}\n${med.dosage}' : med.name,
                bold: true,
              ),
              _pdfCell(med.frequency),
              _pdfCell(med.duration),
              _pdfCell(med.notes),
            ],
          );
        }),
      ],
    );
  }

  pw.Widget _pdfCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(7),
      child: pw.Text(
        text.isNotEmpty ? text : '-',
        style: pw.TextStyle(
          fontSize: 9,
          color: bold ? PdfColors.blue900 : PdfColors.grey800,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _pdfNoteBox(List<List<String>> rows) {
    return pw.Container(
      padding: const pw.EdgeInsets.all(12),
      color: PdfColors.blue50,
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: rows.map((row) {
          return pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 5),
            child: pw.RichText(
              text: pw.TextSpan(
                children: [
                  pw.TextSpan(
                    text: '${row[0]}: ',
                    style: pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.blue900,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.TextSpan(
                    text: row[1],
                    style: const pw.TextStyle(
                      fontSize: 10,
                      color: PdfColors.grey800,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  pw.Widget _pdfDetailsTable(MedicalCertificateRecord record) {
    final rows = <List<String>>[
      ['Diagnosis / Condition', record.diagnosis],
      if (record.recommendation.isNotEmpty)
        ['Recommendation', record.recommendation],
      if (record.restFromDate.isNotEmpty || record.restToDate.isNotEmpty)
        ['Rest Period', _restPeriod(record.restFromDate, record.restToDate)],
      if (record.notes.isNotEmpty) ['Additional Notes', record.notes],
    ];

    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.blue200),
      columnWidths: const {
        0: pw.FlexColumnWidth(1.1),
        1: pw.FlexColumnWidth(2.2),
      },
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.blue700),
          children: ['Field', 'Details']
              .map(
                (text) => pw.Padding(
                  padding: const pw.EdgeInsets.all(8),
                  child: pw.Text(
                    text.toUpperCase(),
                    style: pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.white,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        ...rows.map(
          (row) => pw.TableRow(
            children: [
              _pdfCertificateCell(row[0], bold: true),
              _pdfCertificateCell(row[1]),
            ],
          ),
        ),
      ],
    );
  }

  pw.Widget _pdfCertificateCell(String text, {bool bold = false}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.all(8),
      child: pw.Text(
        text.isNotEmpty ? text : '-',
        style: pw.TextStyle(
          fontSize: 10,
          color: bold ? PdfColors.blue900 : PdfColors.grey800,
          fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
        ),
      ),
    );
  }

  pw.Widget _pdfDoctorBox(MedicalCertificateRecord record, String doctorName) {
    final enrollment = record.enrollment;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.blue100),
      ),
      child: pw.Column(
        children: [
          pw.Container(
            color: PdfColors.blue50,
            padding: const pw.EdgeInsets.all(10),
            child: pw.Row(
              children: [
                pw.Expanded(
                  child: pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text(
                        'Dr. $doctorName',
                        style: pw.TextStyle(
                          fontSize: 11,
                          color: PdfColors.blue900,
                          fontWeight: pw.FontWeight.bold,
                        ),
                      ),
                      if (enrollment.specialization.isNotEmpty ||
                          enrollment.qualification.isNotEmpty)
                        pw.Text(
                          [
                            enrollment.specialization,
                            enrollment.qualification,
                          ].where((item) => item.isNotEmpty).join(' - '),
                          style: const pw.TextStyle(
                            fontSize: 9,
                            color: PdfColors.grey700,
                          ),
                        ),
                    ],
                  ),
                ),
                if (enrollment.medicalRegistrationNumber.isNotEmpty)
                  pw.Text(
                    'Reg. No: ${enrollment.medicalRegistrationNumber}',
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
              ],
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.all(10),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Expanded(
                  child: pw.Text(
                    [
                      enrollment.clinicName.isNotEmpty
                          ? enrollment.clinicName
                          : 'Humancare Connect',
                      enrollment.clinicAddress.isNotEmpty
                          ? enrollment.clinicAddress
                          : '4 Peddlers Row #1091 Newark, DE 19702, United States',
                    ].join('\n'),
                    style: const pw.TextStyle(
                      fontSize: 9,
                      color: PdfColors.grey700,
                    ),
                  ),
                ),
                pw.SizedBox(width: 14),
                pw.Text(
                  'This is a system-generated certificate and does not require a signature or stamp.',
                  textAlign: pw.TextAlign.center,
                  style: const pw.TextStyle(
                    fontSize: 8,
                    color: PdfColors.grey600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  pw.Widget _pdfValidityNote() {
    return pw.Container(
      padding: const pw.EdgeInsets.all(8),
      color: PdfColors.amber50,
      child: pw.Text(
        'Note: This certificate is issued based on the medical examination conducted via Humancare Connect telehealth platform. It is valid as an official medical document for the purpose stated above.',
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.orange900),
      ),
    );
  }

  pw.Widget _pdfFooter() {
    return pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: PdfColors.blue900,
      child: pw.Text(
        'This document is generated electronically and is valid without a physical signature.  support@humancareconnect.co',
        textAlign: pw.TextAlign.center,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.white),
      ),
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

  String _ageSex(Map<String, String> patient) {
    final dob = patient['dob'] ?? '';
    final gender = patient['gender'] ?? '';
    final age = _ageFromDob(dob);
    final parts = [
      if (age.isNotEmpty) '$age yrs',
      if (gender.isNotEmpty) gender,
    ];
    return parts.isEmpty ? '-' : parts.join(' / ');
  }

  String _ageFromDob(String dob) {
    final birthDate = DateTime.tryParse(dob);
    if (birthDate == null) return '';
    final now = DateTime.now();
    var age = now.year - birthDate.year;
    if (now.month < birthDate.month ||
        (now.month == birthDate.month && now.day < birthDate.day)) {
      age -= 1;
    }
    return age > 0 ? '$age' : '';
  }

  String _prescriptionCode(String id) {
    final suffix = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'HC-${suffix.toUpperCase()}';
  }

  String _certificateCode(String id) {
    final suffix = id.length > 8 ? id.substring(id.length - 8) : id;
    return 'HC-CERT-${suffix.toUpperCase()}';
  }

  String _restPeriod(String fromDate, String toDate) {
    if (fromDate.isNotEmpty && toDate.isNotEmpty) {
      return '${_formatDate(fromDate)} to ${_formatDate(toDate)}';
    }
    if (fromDate.isNotEmpty) return 'From ${_formatDate(fromDate)}';
    return 'Until ${_formatDate(toDate)}';
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.045),
          blurRadius: 14,
          offset: const Offset(0, 5),
        ),
      ],
    );
  }
}

class _PrescriptionSlip extends StatelessWidget {
  const _PrescriptionSlip({required this.record, required this.patient});

  final PrescriptionRecord record;
  final Map<String, String> patient;

  static const _primary = Color(0xFF0D47A1);
  static const _accent = Color(0xFF1565C0);
  static const _light = Color(0xFFE8F0FE);

  @override
  Widget build(BuildContext context) {
    return _SlipShell(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SlipHeader(light: _light),
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
                color: _accent,
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
            decoration: const BoxDecoration(
              color: _light,
              border: Border(left: BorderSide(color: _accent, width: 3)),
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
          const _SlipFooter(),
        ],
      ),
    );
  }

  static Widget _richLine(String label, String value) {
    return RichText(
      text: TextSpan(
        style: const TextStyle(color: Color(0xFF475569), fontSize: 12.5),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              color: _primary,
              fontWeight: FontWeight.w800,
            ),
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
  const _CertificateSlip({required this.record, required this.patient});

  final MedicalCertificateRecord record;
  final Map<String, String> patient;

  static const _light = Color(0xFFE8F0FE);

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
          const _SlipHeader(light: _light),
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
              color: const Color(0xFFF8FAFF),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _light, width: 1.4),
            ),
            child: Text(
              'This is to certify that $patientName, $ageSex, has been examined and is suffering from ${record.diagnosis}.',
              style: const TextStyle(height: 1.55, color: Color(0xFF1A1A2E)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _CertificateDetailsTable(record: record),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: _DoctorCertificateBox(record: record),
          ),
          Container(
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Text(
              'Note: This certificate is issued based on the medical examination conducted via Humancare Connect telehealth platform. It is valid as an official medical document for the purpose stated above.',
              style: TextStyle(
                color: Color(0xFF92400E),
                fontSize: 11.5,
                height: 1.4,
              ),
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
        color: const Color(0xFFE8F0FE),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Container(
          width: 760,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(3),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 8,
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: child,
        ),
      ),
    );
  }
}

class _SlipHeader extends StatelessWidget {
  const _SlipHeader({this.light = const Color(0xFFE8F0FE)});

  final Color light;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 18, 22, 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: light, width: 2)),
      ),
      child: Row(
        children: [
          Image.asset(
            'assets/Logo.png',
            height: 46,
            errorBuilder: (_, error, stackTrace) {
              return const Text(
                'Humancare Connect',
                style: TextStyle(
                  color: Color(0xFF0D47A1),
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              );
            },
          ),
          const Spacer(),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'Global Health Passport',
                style: TextStyle(
                  color: Color(0xFF1565C0),
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                ),
              ),
              SizedBox(height: 5),
              SizedBox(
                width: 48,
                child: Divider(color: Color(0xFF1565C0), thickness: 4),
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
      color: const Color(0xFFE8F0FE),
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Color(0xFF0D47A1),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: Color(0xFF475569),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                code,
                style: const TextStyle(
                  color: Color(0xFF0D47A1),
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                date,
                style: const TextStyle(color: Color(0xFF64748B), fontSize: 11),
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
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFE8F0FE)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              color: Color(0xFF1565C0),
              fontSize: 10,
              fontWeight: FontWeight.w900,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Text(
                    row[0],
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      row.length > 1 && row[1].isNotEmpty ? row[1] : '-',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        color: Color(0xFF0D47A1),
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
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
        horizontalInside: BorderSide(color: Color(0xFFE5E7EB)),
      ),
      children: [
        TableRow(
          decoration: const BoxDecoration(
            border: Border(
              bottom: BorderSide(color: Color(0xFF0D47A1), width: 1.5),
            ),
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
        style: const TextStyle(
          color: Color(0xFF64748B),
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }

  static Widget _tableCell(String text, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text.isEmpty ? '-' : text,
        style: TextStyle(
          color: bold ? const Color(0xFF0D47A1) : const Color(0xFF334155),
          fontSize: 12,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          height: 1.25,
        ),
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
      border: TableBorder.all(color: const Color(0xFFC5D5F0)),
      columnWidths: const {0: FlexColumnWidth(1), 1: FlexColumnWidth(2.2)},
      children: [
        TableRow(
          decoration: const BoxDecoration(color: Color(0xFF1565C0)),
          children: ['Field', 'Details'].map((text) {
            return Padding(
              padding: const EdgeInsets.all(9),
              child: Text(
                text.toUpperCase(),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
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
        style: TextStyle(
          color: bold ? const Color(0xFF0D47A1) : const Color(0xFF1A1A2E),
          fontSize: 12.5,
          fontWeight: bold ? FontWeight.w800 : FontWeight.w500,
          height: 1.35,
        ),
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
  const _DoctorCertificateBox({required this.record});

  final MedicalCertificateRecord record;

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
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFE8F0FE)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          Container(
            color: const Color(0xFFE8F0FE),
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 17,
                  backgroundColor: const Color(0xFF0D47A1),
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
                        style: const TextStyle(
                          color: Color(0xFF0D47A1),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (subtitle.isNotEmpty)
                        Text(
                          subtitle,
                          style: const TextStyle(
                            color: Color(0xFF475569),
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (enrollment.medicalRegistrationNumber.isNotEmpty)
                  Text(
                    'Reg. No: ${enrollment.medicalRegistrationNumber}',
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: const Color(0xFFF8FAFF),
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
                    style: const TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 12,
                      height: 1.5,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const SizedBox(
                  width: 210,
                  child: Text(
                    'This is a system-generated certificate and does not require a signature or stamp.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF64748B),
                      fontSize: 11,
                      fontStyle: FontStyle.italic,
                      height: 1.45,
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
        color: const Color(0xFFE8F0FE),
        child: const Row(
          children: [
            Icon(Icons.qr_code_2_rounded, color: Color(0xFF0D47A1), size: 46),
            SizedBox(width: 14),
            Expanded(
              child: Text(
                '+1 (302) 303-9993\nsupport@humancareconnect.co\n4 Peddlers Row #1091 Newark, DE 19702, United States',
                style: TextStyle(
                  color: Color(0xFF1E3A5F),
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.only(top: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      color: const Color(0xFF0D47A1),
      child: const Text(
        'This document is generated electronically and is valid without a physical signature.',
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white, fontSize: 11.5),
      ),
    );
  }
}

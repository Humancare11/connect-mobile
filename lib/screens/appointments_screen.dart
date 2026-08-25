import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_design_system.dart';
import '../services/token_storage_service.dart';
import '../services/api_client.dart';
import '../services/socket_service.dart';
import 'book_appointment_screen.dart';
import 'video_call_screen.dart';

class DoctorInfo {
  const DoctorInfo({this.id, this.name, this.email});

  factory DoctorInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DoctorInfo();
    return DoctorInfo(
      id: (json['_id'] ?? json['id'])?.toString(),
      name: json['name']?.toString(),
      email: json['email']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    if ((id ?? '').isNotEmpty) '_id': id,
    if ((name ?? '').isNotEmpty) 'name': name,
    if ((email ?? '').isNotEmpty) 'email': email,
  };

  final String? id;
  final String? name;
  final String? email;
}

class MedicalReport {
  const MedicalReport({this.name, this.url, this.type});

  factory MedicalReport.fromJson(Map<String, dynamic> json) {
    return MedicalReport(
      name: json['name']?.toString(),
      url: json['url']?.toString(),
      type: json['type']?.toString(),
    );
  }

  final String? name;
  final String? url;
  final String? type;
}

class Appointment {
  const Appointment({
    required this.id,
    required this.status,
    this.doctor,
    this.specialty,
    this.date,
    this.time,
    this.problem,
    this.medicalReports = const [],
    this.raw = const <String, dynamic>{},
  });

  factory Appointment.fromJson(Map<String, dynamic> json) {
    final doctorValue = json['doctorId'] ?? json['doctor'];
    return Appointment(
      id: (json['_id'] ?? json['id'] ?? '').toString(),
      doctor: doctorValue is Map
          ? DoctorInfo.fromJson(
              doctorValue.map((key, value) => MapEntry(key.toString(), value)),
            )
          : null,
      specialty: json['specialty']?.toString(),
      status: (json['status'] ?? '').toString().trim().toLowerCase(),
      date: json['date']?.toString(),
      time: json['time']?.toString(),
      problem: json['problem']?.toString(),
      medicalReports: (json['medicalReports'] as List<dynamic>? ?? [])
          .whereType<Map>()
          .map(
            (report) => MedicalReport.fromJson(
              report.map((key, value) => MapEntry(key.toString(), value)),
            ),
          )
          .toList(),
      raw: json,
    );
  }

  final String id;
  final DoctorInfo? doctor;
  final String? specialty;
  final String status;
  final String? date;
  final String? time;
  final String? problem;
  final List<MedicalReport> medicalReports;
  final Map<String, dynamic> raw;

  bool get hasAssignedDoctor {
    final value = doctor?.toJson() ?? const <String, dynamic>{};
    if (value.isNotEmpty) return true;
    final rawDoctor = raw['doctorId'] ?? raw['doctor'];
    if (rawDoctor is Map) return rawDoctor.isNotEmpty;
    return (rawDoctor?.toString().trim() ?? '').isNotEmpty;
  }

  String get displayStatus {
    if (status == 'assigned' && hasAssignedDoctor) return 'confirmed';
    return status;
  }

  Map<String, dynamic> toVideoCallPayload(Map<String, String> patientProfile) {
    final patientId = patientProfile['userId'] ?? '';
    final patient = {
      if (patientId.isNotEmpty) '_id': patientId,
      if ((patientProfile['name'] ?? '').isNotEmpty)
        'name': patientProfile['name'],
      if ((patientProfile['email'] ?? '').isNotEmpty)
        'email': patientProfile['email'],
    };

    return {
      ...raw,
      '_id': id,
      'id': id,
      'status': displayStatus,
      if ((date ?? '').isNotEmpty) 'date': date,
      if ((time ?? '').isNotEmpty) 'time': time,
      if ((problem ?? '').isNotEmpty) 'problem': problem,
      if (doctor != null && doctor!.toJson().isNotEmpty)
        'doctorId': doctor!.toJson(),
      if (patient.isNotEmpty) 'patientId': patient,
    };
  }
}

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, this.activityId});

  final String? activityId;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen>
    with WidgetsBindingObserver {
  final _apiClient = ApiClient();
  final _tokenStorage = const TokenStorageService();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};
  Timer? _refreshTimer;
  DateTime? _lastFetchAt;

  // Resume and socket-reconnect can both fire in quick succession (the OS
  // drops the socket while suspended, so foregrounding the app triggers a
  // reconnect right after the lifecycle resume) — without this, one app
  // switch could queue two near-simultaneous background refreshes.
  static const _minBackgroundRefreshInterval = Duration(seconds: 5);

  List<Appointment> _appointments = [];
  bool _loading = true;
  String _activeTab = 'confirmed';
  String _focusedAppointmentId = '';
  String _error = '';

  // ── Palette ────────────────────────────────────────────────────────────────
  // Everything visual pulls from the shared design system (AppColors / AppType /
  // AppRadius / AppShadows). The two values the system may not expose directly
  // are kept local so you can repoint them at your own tokens if you have them.

  // Scaffold tint. Swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);

  // Semantic status colours — reused from the medical-services accent palette
  // so they stay on-brand across the app.
  static const Color _statusPending   = Color(0xFFF5B74E); // amber
  static const Color _statusConfirmed = Color(0xFF63C06B); // green
  static const Color _statusCompleted = Color(0xFF8A94A6); // muted slate

  @override
  void initState() {
    super.initState();
    _loadAppointments();
    _connectAppointmentUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    SocketService.instance.off('connect', _handleSocketConnected);
    SocketService.instance.off('appointment-updated', _handleRealtimeUpdate);
    SocketService.instance.off('new-prescription', _handleRealtimeUpdate);
    SocketService.instance.off('new-certificate', _handleRealtimeUpdate);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments({bool withLoader = true}) async {
    // Only block the screen with a spinner when there's nothing on it yet —
    // a pull-to-refresh or retry with appointments already showing has its
    // own feedback (the pull gesture itself) and shouldn't blank the list
    // out from under the user just to show a duplicate loading state.
    final showLoader = withLoader && _appointments.isEmpty;
    if (withLoader) {
      setState(() {
        _loading = showLoader;
        _error = '';
      });
    }

    // Always silent: this screen already renders its own loading state
    // below (see _buildContent), so the app-wide overlay would just be a
    // second, redundant spinner stacked on top of it.
    _lastFetchAt = DateTime.now();
    final result = await _apiClient.get('/appointments/mine', null, true);
    if (!mounted) return;

    if (!result.success) {
      if (withLoader) {
        setState(() {
          _loading = false;
          _error = result.message;
        });
      }
      return;
    }

    final items = _extractAppointments(result.data ?? result.raw);
    setState(() {
      _appointments = items;
      _loading = false;
    });
    _handleDeepLink();
  }

  Future<void> _connectAppointmentUpdates() async {
    WidgetsBinding.instance.addObserver(this);
    SocketService.instance.on('connect', _handleSocketConnected);
    SocketService.instance.on('appointment-updated', _handleRealtimeUpdate);
    SocketService.instance.on('new-prescription', _handleRealtimeUpdate);
    SocketService.instance.on('new-certificate', _handleRealtimeUpdate);

    if (SocketService.instance.connected) {
      await _joinPatientSocketRoom();
    } else {
      SocketService.instance.connect();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _queueBackgroundRefresh();
      _joinPatientSocketRoom();
    }
  }

  void _handleSocketConnected(dynamic _) {
    _joinPatientSocketRoom();
    _queueBackgroundRefresh();
  }

  void _handleRealtimeUpdate(dynamic _) {
    _queueRefresh();
  }

  // Resume/reconnect refreshes are just "make sure nothing changed while we
  // were away" — safe to skip if a fetch (from either trigger, or a manual
  // action) already landed moments ago. Genuine push events always go
  // through the unthrottled _queueRefresh above so real updates never wait.
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
    _refreshTimer = Timer(const Duration(milliseconds: 200), () {
      _refreshTimer = null;
      if (mounted) {
        _loadAppointments(withLoader: false);
      }
    });
  }

  Future<void> _joinPatientSocketRoom() async {
    final profile = await _tokenStorage.getUserProfile();
    if (!mounted) return;

    final userId = (profile['userId'] ?? '').trim();
    if (userId.isEmpty || !SocketService.instance.connected) return;

    SocketService.instance.emit('user-online', {
      'userId': userId,
      'role': 'user',
    });
  }

  List<Appointment> _extractAppointments(Map<String, dynamic> response) {
    final candidates = <dynamic>[
      response['data'],
      response['appointments'],
      response['items'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) {
        return _appointmentsFromList(candidate);
      }

      if (candidate is Map) {
        for (final value in candidate.values) {
          if (value is List) return _appointmentsFromList(value);
        }
      }
    }

    return const <Appointment>[];
  }

  List<Appointment> _appointmentsFromList(List<dynamic> list) {
    return list
        .whereType<Map>()
        .map(
          (item) => Appointment.fromJson(
            item.map((key, value) => MapEntry(key.toString(), value)),
          ),
        )
        .toList();
  }

  void _handleDeepLink() {
    final activityId = widget.activityId;
    if (activityId == null || activityId.isEmpty || _appointments.isEmpty) {
      return;
    }

    final matches = _appointments.where((item) => item.id == activityId);
    if (matches.isEmpty) return;

    final appointment = matches.first;
    setState(() {
      _focusedAppointmentId = activityId;
      _activeTab = _tabForStatus(appointment.displayStatus);
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final context = _cardKeys[activityId]?.currentContext;
      if (context == null) return;
      Scrollable.ensureVisible(
        context,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
        alignment: 0.5,
      );
    });
  }

  List<Appointment> get _pending => _appointments
      .where(
        (item) => const {
          'requested',
          'upcoming',
          'assigned',
          'pending',
        }.contains(item.displayStatus),
      )
      .toList();

  List<Appointment> get _confirmed =>
      _appointments.where((item) => item.displayStatus == 'confirmed').toList();

  List<Appointment> get _completed => _appointments
      .where((item) => const {'complete', 'completed'}.contains(item.displayStatus))
      .toList();

  List<Appointment> get _currentList {
    switch (_activeTab) {
      case 'pending':
        return _pending;
      case 'completed':
        return _completed;
      case 'confirmed':
      default:
        return _confirmed;
    }
  }

  String _tabForStatus(String status) {
    if (const {'complete', 'completed'}.contains(status)) return 'completed';
    if (status == 'confirmed') return 'confirmed';
    return 'pending';
  }

  String _formatDate(String? value) {
    if (value == null || value.trim().isEmpty) return '-';
    final date = DateTime.tryParse(value);
    if (date == null) return value;
    return DateFormat('d MMM y').format(date);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgCanvas,
      body: SafeArea(
        child: RefreshIndicator(
          color: AppColors.primary,
          onRefresh: () => _loadAppointments(),
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              _buildHeader(context),
              const SizedBox(height: AppSpacing.lg),
              _buildStatsStrip(),
              const SizedBox(height: AppSpacing.lg),
              _buildTabs(),
              const SizedBox(height: AppSpacing.md),
              _buildContent(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'HUMANCARE CONNECT',
                style: TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.1,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'My Appointments',
                style: AppType.display(size: 23, height: 1.1),
              ),
              const SizedBox(height: 4),
              Text(
                'Track and manage your consultations',
                style: AppType.body(size: 13)
                    .copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        ElevatedButton.icon(
          onPressed: _openBooking,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Book'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsStrip() {
    Widget statCard(String label, int count, Color color) {
      return Expanded(
        child: Column(
          children: [
            Text('$count', style: AppType.display(size: 20)),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                Text(
                  label,
                  style: AppType.body(size: 12)
                      .copyWith(color: AppColors.textSecondary),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          statCard('Pending', _pending.length, _statusPending),
          Container(width: 1, height: 32, color: AppColors.border),
          statCard('Confirmed', _confirmed.length, _statusConfirmed),
          Container(width: 1, height: 32, color: AppColors.border),
          statCard('Completed', _completed.length, _statusCompleted),
        ],
      ),
    );
  }

  Widget _buildTabs() {
    return Row(
      children: ['pending', 'confirmed', 'completed'].map((tab) {
        final active = _activeTab == tab;
        final count = switch (tab) {
          'pending' => _pending.length,
          'completed' => _completed.length,
          _ => _confirmed.length,
        };

        return Expanded(
          child: GestureDetector(
            onTap: () => setState(() => _activeTab = tab),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: active ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                  color: active ? AppColors.primary : AppColors.border,
                  width: 1.2,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    tab[0].toUpperCase() + tab.substring(1),
                    style: AppType.body(size: 13, weight: FontWeight.w600)
                        .copyWith(
                      color: active ? Colors.white : AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    '$count',
                    style: AppType.body(size: 12).copyWith(
                      color: active
                          ? Colors.white.withValues(alpha: 0.75)
                          : AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildContent() {
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 12),
            Text(
              'Fetching your appointments...',
              style: AppType.body(size: 13)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ],
        ),
      );
    }

    if (_error.isNotEmpty) {
      return _messageState(
        icon: Icons.error_outline,
        title: 'Could not load appointments',
        message: _error,
        action: OutlinedButton(
          onPressed: () => _loadAppointments(),
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
          ),
          child: const Text('Try Again'),
        ),
      );
    }

    if (_currentList.isEmpty) {
      return _messageState(
        icon: Icons.event_note_outlined,
        title: 'No $_activeTab appointments',
        message: _emptyMessage,
        action: _activeTab == 'completed'
            ? null
            : OutlinedButton(
                onPressed: _openBooking,
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                ),
                child: const Text('Book Appointment'),
              ),
      );
    }

    return Column(
      children: _currentList.map(_buildAppointmentCard).toList(),
    );
  }

  String get _emptyMessage {
    switch (_activeTab) {
      case 'pending':
        return 'You have no appointments awaiting confirmation.';
      case 'completed':
        return 'Your completed consultations will appear here.';
      case 'confirmed':
      default:
        return 'No confirmed appointments right now.';
    }
  }

  Widget _messageState({
    required IconData icon,
    required String title,
    required String message,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          Icon(icon, size: 42, color: AppColors.textSecondary),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: AppType.display(size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: AppType.body(size: 13)
                .copyWith(color: AppColors.textSecondary),
          ),
          if (action != null) ...[
            const SizedBox(height: 16),
            action,
          ],
        ],
      ),
    );
  }

  Widget _buildAppointmentCard(Appointment appointment) {
    final key = _cardKeys.putIfAbsent(appointment.id, () => GlobalKey());
    final focused = _focusedAppointmentId == appointment.id;
    final color = _statusColor(_activeTab);
    final doctorName = appointment.doctor?.name?.trim();
    final problem = (appointment.problem ?? '').trim();

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: _cardDecoration().copyWith(
        border: Border.all(
          color: focused ? AppColors.primary : AppColors.border,
          width: focused ? 1.6 : 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Doctor row ──────────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: AppColors.primary.withValues(alpha: 0.12),
                child: Text(
                  doctorName?.isNotEmpty == true
                      ? doctorName!.substring(0, 1).toUpperCase()
                      : 'D',
                  style:
                      AppType.display(size: 16, color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            doctorName?.isNotEmpty == true
                                ? 'Dr. $doctorName'
                                : 'Doctor assignment pending',
                            style: AppType.body(
                                size: 15, weight: FontWeight.w700),
                          ),
                        ),
                        _statusChip(color),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appointment.doctor?.email ??
                          appointment.specialty ??
                          '-',
                      style: AppType.body(size: 12)
                          .copyWith(color: AppColors.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── Date / time meta ────────────────────────────────────────────
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _meta(Icons.calendar_today_outlined,
                  _formatDate(appointment.date)),
              _meta(Icons.access_time, appointment.time ?? '-'),
            ],
          ),

          // ── Reason (handles long, multi-line text gracefully) ───────────
          if (problem.isNotEmpty) _buildReasonBlock(problem),

          // ── Attachments ─────────────────────────────────────────────────
          if (appointment.medicalReports.isNotEmpty)
            _buildAttachments(appointment.medicalReports),

          const SizedBox(height: 12),
          _buildCardActions(appointment),
        ],
      ),
    );
  }

  Widget _buildReasonBlock(String problem) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(color: AppColors.border, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.notes_outlined,
                    size: 14, color: AppColors.textSecondary),
                const SizedBox(width: 6),
                Text(
                  'Reason for visit',
                  style: AppType.body(size: 11, weight: FontWeight.w600)
                      .copyWith(
                    color: AppColors.textSecondary,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              problem,
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: AppType.body(size: 13, height: 1.35)
                  .copyWith(color: AppColors.textPrimary),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachments(List<MedicalReport> reports) {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachments (${reports.length})',
            style: AppType.body(size: 11, weight: FontWeight.w600).copyWith(
              color: AppColors.textSecondary,
              letterSpacing: 0.2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: reports.map(_attachmentChip).toList(),
          ),
        ],
      ),
    );
  }

  Widget _attachmentChip(MedicalReport report) {
    final name = (report.name ?? '').trim().isEmpty
        ? 'Attachment'
        : report.name!.trim();
    final image = _isImage(report);

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: () => _openReport(report),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 210),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            border: Border.all(color: AppColors.border, width: 1.2),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                ),
                child: Icon(
                  image ? Icons.image_outlined : Icons.description_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppType.body(size: 12.5, weight: FontWeight.w600)
                      .copyWith(color: AppColors.textPrimary),
                ),
              ),
              const SizedBox(width: 6),
              Icon(Icons.open_in_new_rounded,
                  size: 14, color: AppColors.textSecondary),
            ],
          ),
        ),
      ),
    );
  }

  bool _isImage(MedicalReport report) {
    final type = (report.type ?? '').toLowerCase();
    if (type.contains('image')) return true;
    final url = (report.url ?? '').toLowerCase();
    return url.endsWith('.png') ||
        url.endsWith('.jpg') ||
        url.endsWith('.jpeg') ||
        url.endsWith('.webp') ||
        url.endsWith('.gif');
  }

  Future<void> _openReport(MedicalReport report) async {
    final url = (report.url ?? '').trim();
    if (url.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No file link available.')),
      );
      return;
    }

    final uri = Uri.tryParse(url);
    var launched = false;
    if (uri != null) {
      try {
        launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      } catch (_) {
        launched = false;
      }
    }

    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to open ${report.name ?? 'attachment'}. Please try again.',
          ),
        ),
      );
    }
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: AppColors.textSecondary),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            style: AppType.body(size: 12.5)
                .copyWith(color: AppColors.textPrimary),
          ),
        ),
      ],
    );
  }

  Widget _statusChip(Color color) {
    final label = switch (_activeTab) {
      'pending' => 'Pending',
      'completed' => 'Completed',
      _ => 'Confirmed',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: AppType.body(size: 12, weight: FontWeight.w600)
            .copyWith(color: color),
      ),
    );
  }

  Widget _buildCardActions(Appointment appointment) {
    final canJoinVideoCall = appointment.displayStatus == 'confirmed';

    if (_activeTab == 'pending') {
      final text = appointment.status == 'assigned'
          ? 'Doctor assigned. Awaiting confirmation.'
          : 'Awaiting confirmation.';
      return Text(
        text,
        style: AppType.body(size: 13).copyWith(
          color: AppColors.textSecondary,
          fontStyle: FontStyle.italic,
        ),
      );
    }

    if (_activeTab == 'completed') {
      return Text(
        'Consultation completed',
        style: AppType.body(size: 13)
            .copyWith(color: AppColors.textSecondary),
      );
    }

    if (!canJoinVideoCall) {
      return const SizedBox.shrink();
    }

    return _joinButton(appointment);
  }

  // Redesigned primary CTA — brand gradient, video glyph and a soft lift.
  // Change the two gradient colours below to recolour the button.
  Widget _joinButton(Appointment appointment) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        onTap: () => _openVideoConsultation(appointment),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            gradient: const LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [AppColors.primary, AppColors.primaryDeep],
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.primary.withValues(alpha: 0.30),
                blurRadius: 14,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.videocam_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Text(
                  'Join Consultation',
                  style: AppType.body(size: 14, weight: FontWeight.w700)
                      .copyWith(color: Colors.white),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _statusColor(String tab) {
    switch (tab) {
      case 'pending':
        return _statusPending;
      case 'completed':
        return _statusCompleted;
      case 'confirmed':
      default:
        return _statusConfirmed;
    }
  }

  Future<void> _openBooking() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppointmentBookingPage()),
    );
    if (mounted) _loadAppointments(withLoader: false);
  }

  Future<void> _openVideoConsultation(Appointment appointment) async {
    final patientProfile = await _loadPatientProfile();
    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          appointmentId: appointment.id,
          initialAppointment: appointment.toVideoCallPayload(patientProfile),
          initialDoctor: appointment.doctor?.toJson(),
          initialPatient: {
            if ((patientProfile['userId'] ?? '').isNotEmpty)
              '_id': patientProfile['userId'],
            if ((patientProfile['name'] ?? '').isNotEmpty)
              'name': patientProfile['name'],
            if ((patientProfile['email'] ?? '').isNotEmpty)
              'email': patientProfile['email'],
          },
          initialRole: 'user',
        ),
      ),
    );
  }

  Future<Map<String, String>> _loadPatientProfile() async {
    final tokenData = await _tokenStorage.getUserProfile();

    return {
      'userId': tokenData['userId']?.toString() ?? '',
      'name': tokenData['name']?.toString() ?? '',
      'email': tokenData['email']?.toString() ?? '',
    };
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
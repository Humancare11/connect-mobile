import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_client.dart';
import 'book_appointment_screen.dart';

class DoctorInfo {
  const DoctorInfo({this.name, this.email});

  factory DoctorInfo.fromJson(Map<String, dynamic>? json) {
    if (json == null) return const DoctorInfo();
    return DoctorInfo(
      name: json['name']?.toString(),
      email: json['email']?.toString(),
    );
  }

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
      status: (json['status'] ?? '').toString().toLowerCase(),
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
}

class AppointmentsScreen extends StatefulWidget {
  const AppointmentsScreen({super.key, this.activityId});

  final String? activityId;

  @override
  State<AppointmentsScreen> createState() => _AppointmentsScreenState();
}

class _AppointmentsScreenState extends State<AppointmentsScreen> {
  final _apiClient = ApiClient();
  final _scrollController = ScrollController();
  final Map<String, GlobalKey> _cardKeys = {};

  List<Appointment> _appointments = [];
  bool _loading = true;
  String _activeTab = 'confirmed';
  String _focusedAppointmentId = '';
  String _error = '';

  @override
  void initState() {
    super.initState();
    _loadAppointments();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadAppointments() async {
    setState(() {
      _loading = true;
      _error = '';
    });

    final result = await _apiClient.get('/appointments/mine');
    if (!mounted) return;

    if (!result.success) {
      setState(() {
        _loading = false;
        _error = result.message;
      });
      return;
    }

    final items = _extractAppointments(result.data ?? result.raw);
    setState(() {
      _appointments = items;
      _loading = false;
    });
    _handleDeepLink();
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
      _activeTab = _tabForStatus(appointment.status);
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
        }.contains(item.status),
      )
      .toList();

  List<Appointment> get _confirmed =>
      _appointments.where((item) => item.status == 'confirmed').toList();

  List<Appointment> get _completed => _appointments
      .where((item) => const {'complete', 'completed'}.contains(item.status))
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
      backgroundColor: const Color(0xFFF6F8FB),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadAppointments,
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              _buildHeader(context),
              const SizedBox(height: 20),
              _buildStatsStrip(),
              const SizedBox(height: 20),
              _buildTabs(),
              const SizedBox(height: 16),
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
              Text(
                'HUMANCARE CONNECT',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.1,
                  color: Colors.teal.shade600,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'My Appointments',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              Text(
                'Track and manage your consultations',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
        ElevatedButton.icon(
          onPressed: _openBooking,
          icon: const Icon(Icons.add, size: 18),
          label: const Text('Book'),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal.shade600,
            foregroundColor: Colors.white,
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
            Text(
              '$count',
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                ),
                Text(label, style: TextStyle(color: Colors.grey.shade600)),
              ],
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: _cardDecoration(),
      child: Row(
        children: [
          statCard('Pending', _pending.length, Colors.orange),
          Container(width: 1, height: 32, color: Colors.grey.shade200),
          statCard('Confirmed', _confirmed.length, Colors.green),
          Container(width: 1, height: 32, color: Colors.grey.shade200),
          statCard('Completed', _completed.length, Colors.blueGrey),
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
                color: active ? Colors.teal.shade600 : Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: active ? Colors.teal.shade600 : Colors.grey.shade300,
                ),
              ),
              child: Column(
                children: [
                  Text(
                    tab[0].toUpperCase() + tab.substring(1),
                    style: TextStyle(
                      color: active ? Colors.white : Colors.black87,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    '$count',
                    style: TextStyle(
                      color: active ? Colors.white70 : Colors.grey.shade600,
                      fontSize: 12,
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
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 60),
        child: Column(
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('Fetching your appointments...'),
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
          onPressed: _loadAppointments,
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
          Icon(icon, size: 42, color: Colors.grey.shade500),
          const SizedBox(height: 12),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
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

    return Container(
      key: key,
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration().copyWith(
        border: Border.all(
          color: focused ? Colors.teal.shade400 : Colors.grey.shade200,
          width: focused ? 2 : 1,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: Colors.teal.shade100,
            child: Text(
              doctorName?.isNotEmpty == true
                  ? doctorName!.substring(0, 1).toUpperCase()
                  : 'D',
              style: TextStyle(
                color: Colors.teal.shade700,
                fontWeight: FontWeight.bold,
              ),
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
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    _statusChip(color),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  appointment.doctor?.email ?? appointment.specialty ?? '-',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 16,
                  runSpacing: 8,
                  children: [
                    _meta(Icons.calendar_today_outlined, _formatDate(appointment.date)),
                    _meta(Icons.access_time, appointment.time ?? '-'),
                    if ((appointment.problem ?? '').trim().isNotEmpty)
                      _meta(Icons.notes_outlined, appointment.problem!),
                  ],
                ),
                if (appointment.medicalReports.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    '${appointment.medicalReports.length} medical report(s)',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  ),
                ],
                const SizedBox(height: 12),
                _buildCardActions(appointment),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _meta(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Flexible(child: Text(text)),
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
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildCardActions(Appointment appointment) {
    if (_activeTab == 'pending') {
      final text = appointment.status == 'assigned'
          ? 'Doctor assigned. Awaiting confirmation.'
          : 'Awaiting confirmation.';
      return Text(
        text,
        style: TextStyle(
          color: Colors.grey.shade600,
          fontStyle: FontStyle.italic,
          fontSize: 13,
        ),
      );
    }

    if (_activeTab == 'completed') {
      return Text(
        'Consultation completed',
        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
      );
    }

    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: [
        OutlinedButton.icon(
          onPressed: _showVideoUnavailable,
          icon: const Icon(Icons.videocam_outlined, size: 16),
          label: const Text('Join Video Call'),
        ),
      ],
    );
  }

  Color _statusColor(String tab) {
    switch (tab) {
      case 'pending':
        return Colors.orange;
      case 'completed':
        return Colors.blueGrey;
      case 'confirmed':
      default:
        return Colors.green;
    }
  }

  void _openBooking() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const AppointmentBookingPage()),
    );
  }

  void _showVideoUnavailable() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Video consultation is not configured in this build.'),
      ),
    );
  }

  BoxDecoration _cardDecoration() {
    return BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.04),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }
}

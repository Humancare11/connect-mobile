// Section 4 — UpcomingVisitCard
//
// Surfaces the single soonest upcoming appointment directly on the home screen
// so the most time-sensitive thing a patient has is visible without opening the
// Appointments tab.
//
// Reuses `Appointment` and the `/appointments/mine` response shape from
// appointments_screen.dart rather than introducing a parallel model — the two
// must agree on status handling (notably `assigned` + a doctor reading as
// "confirmed"), and duplicating that logic is how they drift apart.
//
// Renders nothing at all when there is no upcoming visit, so the home screen
// closes up cleanly instead of showing an empty placeholder.

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../config/app_design_system.dart';
import '../../screens/appointments_screen.dart';
import '../../screens/video_call_screen.dart';
import '../../services/api_client.dart';
import '../../services/token_storage_service.dart';

class UpcomingVisitCard extends StatefulWidget {
  const UpcomingVisitCard({super.key, this.onManage});

  /// Switches the shell to the Appointments tab. Passed down from MainScreen
  /// rather than pushing a second AppointmentsScreen onto the stack, which
  /// would leave the user with a back button over a tab they already have.
  final VoidCallback? onManage;

  @override
  State<UpcomingVisitCard> createState() => _UpcomingVisitCardState();
}

class _UpcomingVisitCardState extends State<UpcomingVisitCard> {
  final _apiClient = ApiClient();
  final _tokenStorage = const TokenStorageService();

  bool _loading = true;
  bool _joining = false;
  Appointment? _next;

  @override
  void initState() {
    super.initState();
    _loadNextVisit();
  }

  Future<void> _loadNextVisit() async {
    final result = await _apiClient.get('/appointments/mine');
    if (!mounted) return;

    if (!result.success) {
      // A failed load is not worth an error card here — the Appointments tab
      // reports the failure properly. Home just stays quiet.
      setState(() {
        _loading = false;
        _next = null;
      });
      return;
    }

    setState(() {
      _loading = false;
      _next = _pickNextVisit(_extractAppointments(result.data ?? result.raw));
    });
  }

  List<Appointment> _extractAppointments(Map<String, dynamic> response) {
    final candidates = <dynamic>[
      response['data'],
      response['appointments'],
      response['items'],
    ];

    for (final candidate in candidates) {
      if (candidate is List) return _appointmentsFromList(candidate);
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

  /// Soonest appointment that is still ahead of us and not cancelled/completed.
  /// Anything whose date cannot be parsed is skipped rather than guessed at.
  Appointment? _pickNextVisit(List<Appointment> appointments) {
    const excluded = {'cancelled', 'canceled', 'completed', 'rejected'};
    final now = DateTime.now();

    final upcoming = <MapEntry<DateTime, Appointment>>[];
    for (final appointment in appointments) {
      if (excluded.contains(appointment.displayStatus)) continue;

      final when = _parseWhen(appointment);
      // Keep a visit visible for the rest of the day it falls on, so a slot
      // that started a few minutes ago does not vanish mid-consultation.
      if (when == null || when.isBefore(_startOfDay(now))) continue;

      upcoming.add(MapEntry(when, appointment));
    }

    if (upcoming.isEmpty) return null;
    upcoming.sort((a, b) => a.key.compareTo(b.key));
    return upcoming.first.value;
  }

  DateTime _startOfDay(DateTime value) =>
      DateTime(value.year, value.month, value.day);

  DateTime? _parseWhen(Appointment appointment) {
    final raw = (appointment.date ?? '').trim();
    if (raw.isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  String _dayLabel(DateTime when) {
    final today = _startOfDay(DateTime.now());
    final day = _startOfDay(when);
    final difference = day.difference(today).inDays;

    if (difference == 0) return 'Today';
    if (difference == 1) return 'Tomorrow';
    if (difference < 7) return DateFormat('EEEE').format(when);
    return DateFormat('d MMM').format(when);
  }

  /// Prefers the explicit `time` string the booking flow stores; falls back to
  /// the clock component of `date` when the appointment has none.
  String _timeLabel(Appointment appointment, DateTime when) {
    final time = (appointment.time ?? '').trim();
    if (time.isNotEmpty) return time;
    return DateFormat('h:mm a').format(when);
  }

  Future<void> _joinConsultation(Appointment appointment) async {
    if (_joining) return;
    setState(() => _joining = true);

    final profile = await _tokenStorage.getUserProfile();
    if (!mounted) return;
    setState(() => _joining = false);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoCallScreen(
          appointmentId: appointment.id,
          initialAppointment: appointment.toVideoCallPayload(profile),
          initialDoctor: appointment.doctor?.toJson(),
          initialPatient: {
            if ((profile['userId'] ?? '').isNotEmpty) '_id': profile['userId'],
            if ((profile['name'] ?? '').isNotEmpty) 'name': profile['name'],
            if ((profile['email'] ?? '').isNotEmpty) 'email': profile['email'],
          },
          initialRole: 'user',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const _UpcomingVisitPlaceholder();

    final appointment = _next;
    if (appointment == null) return const SizedBox.shrink();

    final when = _parseWhen(appointment)!;
    final specialty = (appointment.specialty ?? '').trim();
    final doctorName = (appointment.doctor?.name ?? '').trim();
    final canJoin = appointment.displayStatus == 'confirmed';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppSectionHeader(
          title: 'Upcoming visit',
          seeAllLabel: 'Manage',
          onSeeAll: widget.onManage,
        ),

        const SizedBox(height: AppSpacing.md),

        AppCard(
          onTap: widget.onManage,
          radius: AppRadius.xl,
          shadow: AppShadows.card,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canJoin) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _joining
                        ? null
                        : () => _joinConsultation(appointment),
                    icon: _joining
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.video_call),
                    label: Text(_joining ? 'Joining…' : 'Join'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Row(
                children: [
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: AppColors.violetTint,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                    alignment: Alignment.center,
                    child: const Icon(
                      Icons.favorite_border_rounded,
                      color: AppColors.violetInk,
                      size: 22,
                    ),
                  ),

                  const SizedBox(width: 13),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (specialty.isNotEmpty) ...[
                          Text(
                            specialty.toUpperCase(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.mono(
                              size: 11,
                              weight: FontWeight.w600,
                              color: AppColors.tealInk,
                              letterSpacing: 0.4,
                            ),
                          ),
                          const SizedBox(height: 3),
                        ],
                        Text(
                          doctorName.isEmpty
                              ? 'Doctor being assigned'
                              : 'Dr. $doctorName',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.display(size: 14.5),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Video consultation',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppType.body(size: 12),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(width: AppSpacing.sm),

                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _timeLabel(appointment, when),
                        style: AppType.mono(
                          size: 13.5,
                          weight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _dayLabel(when),
                        style: AppType.body(
                          size: 11,
                          color: AppColors.textTertiary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Neutral block held during the fetch so the sections below do not jump once
/// the card resolves. Collapses to nothing if there turns out to be no visit.
class _UpcomingVisitPlaceholder extends StatelessWidget {
  const _UpcomingVisitPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 82,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
        border: Border.all(color: AppColors.border),
      ),
    );
  }
}

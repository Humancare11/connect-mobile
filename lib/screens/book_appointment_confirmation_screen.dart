import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import 'payment_history_screen.dart';

class AppointmentConfirmationPage extends StatelessWidget {
  const AppointmentConfirmationPage({super.key});

  // Scaffold tint — swap for AppColors.background if your system defines one.
  static const Color _bgCanvas = Color(0xFFF3F6F5);

  // Success accent (kept on-brand with the app's green status colour).
  static const Color _success = Color(0xFF138A43);

  @override
  Widget build(BuildContext context) {
    final args =
        ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>? ??
        <String, dynamic>{};

    return Scaffold(
      backgroundColor: _bgCanvas,
      appBar: AppBar(
        title: const Text('Appointment Confirmed'),
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.md),
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: AppColors.border, width: 1.2),
                boxShadow: AppShadows.subtle,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 28,
                    backgroundColor: _success.withValues(alpha: 0.12),
                    child: const Icon(
                      Icons.check_rounded,
                      color: _success,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Payment successful',
                    style: AppType.display(size: 23, height: 1.1),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your appointment has been booked and marked as paid.',
                    style: AppType.body(size: 14, height: 1.4)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                  const Divider(height: 30, color: AppColors.border),
                  _line('Specialty', args['specName']),
                  _line('Condition', args['condName']),
                  _line('Date', _formatDate(_parseDate(args['date']))),
                  _line('Time', args['time']),
                  _line('Payment ID', args['paymentIntentId']),
                  const SizedBox(height: 6),
                  Text(
                    'An invoice has been emailed to you and is available under '
                    'Payment History.',
                    style: AppType.body(size: 12.5, height: 1.4)
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 22),
            SizedBox(
              height: 52,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onPressed: () => Navigator.popUntil(
                  context,
                  (route) => route.isFirst,
                ),
                child: const Text(
                  'Done',
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: BorderSide(
                    color: AppColors.primary.withValues(alpha: 0.4),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                  ),
                ),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const PaymentHistoryScreen(expectRecentPayment: true),
                  ),
                ),
                icon: const Icon(Icons.receipt_long_outlined, size: 18),
                label: const Text(
                  'View invoice',
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Previously this screen displayed args['date'] as-is: a raw
  // DateTime.toString() (e.g. "2026-07-20 00:00:00.000") forwarded straight
  // from the booking form, while the payment screen one step earlier showed
  // the same date formatted as "20-07-2026" — an inconsistent, unpolished
  // date the user hadn't seen in that form before. Mirrors the payment
  // screen's own _parseDate/_formatDate exactly.
  DateTime? _parseDate(Object? value) {
    if (value is DateTime) return value;
    return DateTime.tryParse(value?.toString() ?? '');
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '-';
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '$day-$month-${date.year}';
  }

  Widget _line(String label, Object? value) {
    final text = value?.toString().trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 92,
            child: Text(
              label,
              style: AppType.body(size: 13)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              text.isEmpty ? '-' : text,
              style: AppType.body(size: 13.5, weight: FontWeight.w700)
                  .copyWith(color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
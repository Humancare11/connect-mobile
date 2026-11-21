import 'package:flutter/material.dart';

import '../config/app_design_system.dart';

/// Small pieces shared by the My Visit Notes list and detail screens. They are
/// the same card, empty state and warning banner the My Records screen uses
/// (same design-system tokens and values), kept here because the originals are
/// private to that screen.

/// Scaffold tint used by the other account screens.
const Color kVisitNoteCanvas = Color(0xFFF3F6F5);

BoxDecoration visitNoteCardDecoration() {
  return BoxDecoration(
    color: AppColors.surface,
    borderRadius: BorderRadius.circular(AppRadius.md),
    border: Border.all(color: AppColors.border, width: 1.2),
    boxShadow: AppShadows.subtle,
  );
}

class VisitNoteEmptyState extends StatelessWidget {
  const VisitNoteEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: visitNoteCardDecoration(),
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
            style: AppType.body(
              size: 13,
            ).copyWith(color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class VisitNoteErrorBanner extends StatelessWidget {
  const VisitNoteErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  static const Color _warnBg = Color(0xFFFFF7ED);
  static const Color _warnBorder = Color(0xFFFED7AA);
  static const Color _warnIcon = Color(0xFFC2410C);
  static const Color _warnText = Color(0xFF9A3412);

  @override
  Widget build(BuildContext context) {
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
              message,
              style: AppType.body(
                size: 13,
                weight: FontWeight.w600,
              ).copyWith(color: _warnText),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(foregroundColor: AppColors.primary),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

/// Small rounded tag (same look as the appointment status chip).
class VisitNoteTag extends StatelessWidget {
  const VisitNoteTag({super.key, required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        label,
        style: AppType.body(
          size: 12,
          weight: FontWeight.w600,
        ).copyWith(color: color),
      ),
    );
  }
}

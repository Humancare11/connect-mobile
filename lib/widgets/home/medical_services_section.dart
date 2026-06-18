// Section 6 — MedicalServicesSection
// Premium redesign: 2-col grid, rounded square icon containers with
// per-service soft bg, subtitle row, consistent shadows + border.
// Visually distinct from BookByService (circle icons, no subtitle)
// and ExploreSpecialties (horizontal scroll).

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _MedService {
  final IconData icon;
  final String   title;
  final String   subtitle;
  final Color    accent;
  final Color    bgColor;

  const _MedService({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.bgColor,
  });
}

// ── Main widget ───────────────────────────────────────────────────────────────

class MedicalServicesSection extends StatelessWidget {
  const MedicalServicesSection({super.key});

  static const List<_MedService> _services = [
    _MedService(
      icon:     Icons.receipt_long_outlined,
      title:    'Prescription Refills',
      subtitle: 'Same-day · no wait',
      accent:   Color(0xFF4CC3B3),
      bgColor:  Color(0xFFEFF9F7),
    ),
    _MedService(
      icon:     Icons.monitor_weight_outlined,
      title:    'Weight Loss',
      subtitle: 'GLP-1 · coaching',
      accent:   Color(0xFFF5B74E),
      bgColor:  Color(0xFFFFF9EE),
    ),
    _MedService(
      icon:     Icons.psychology_outlined,
      title:    'Mental Health',
      subtitle: 'Therapy & psychiatry',
      accent:   AppColors.catBrain,
      bgColor:  Color(0xFFF5EFFF),
    ),
    _MedService(
      icon:     Icons.health_and_safety_outlined,
      title:    'General Consult',
      subtitle: 'Talk to a doctor',
      accent:   Color(0xFF5B9EFF),
      bgColor:  Color(0xFFEFF5FF),
    ),
    _MedService(
      icon:     Icons.favorite_border_rounded,
      title:    'Sexual Health',
      subtitle: 'Private & confidential',
      accent:   Color(0xFFFF7FA3),
      bgColor:  Color(0xFFFFF0F4),
    ),
    _MedService(
      icon:     Icons.medication_outlined,
      title:    'Chronic Care',
      subtitle: 'Long-term management',
      accent:   Color(0xFF63C06B),
      bgColor:  Color(0xFFEFF8EF),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────────
        AppSectionHeader(
          title:       'Our Medical Services',
          seeAllLabel: 'View all',
          onSeeAll:    () {},
        ),

        const SizedBox(height: AppSpacing.md),

        // ── 2-col service grid ─────────────────────────────────────────────
        GridView.builder(
          shrinkWrap: true,
          physics:    const NeverScrollableScrollPhysics(),
          itemCount:  _services.length,
          gridDelegate:
              const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount:   2,
            crossAxisSpacing: 10,
            mainAxisSpacing:  10,
            childAspectRatio: 2.05,
          ),
          itemBuilder: (context, index) {
            return _ServiceTile(item: _services[index]);
          },
        ),
      ],
    );
  }
}

// ── Service tile ──────────────────────────────────────────────────────────────

class _ServiceTile extends StatelessWidget {
  final _MedService item;

  const _ServiceTile({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color:        Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.md),
        splashColor:  item.accent.withOpacity(0.10),
        onTap:        () {},
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.md),
            border:       Border.all(color: AppColors.border, width: 1.2),
            boxShadow:    AppShadows.subtle,
          ),
          child: Row(
            children: [
              // Rounded-square icon container (distinct from circle in Sec 4)
              Container(
                width:  44,
                height: 44,
                decoration: BoxDecoration(
                  color:        item.bgColor,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: Icon(item.icon, size: 22, color: item.accent),
              ),

              const SizedBox(width: AppSpacing.sm + 2),

              // Text column
              Expanded(
                child: Column(
                  mainAxisAlignment:  MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.title,
                      maxLines:  1,
                      overflow:  TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily:    AppFonts.family,
                        fontSize:      12.5,
                        fontWeight:    FontWeight.w700,
                        color:         AppColors.textPrimary,
                        letterSpacing: -0.1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.subtitle,
                      maxLines:  1,
                      overflow:  TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontFamily: AppFonts.family,
                        fontSize:   10.5,
                        fontWeight: FontWeight.w400,
                        color:      AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
// Section 5 — ExploreSpecialtiesSection
// Premium redesign: horizontal scroll, soft tinted icon backgrounds,
// consistent card shadow, pill "See all" button

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _SpecialtyItem {
  final IconData icon;
  final String   title;
  final Color    accent;
  final Color    bgColor;

  const _SpecialtyItem({
    required this.icon,
    required this.title,
    required this.accent,
    required this.bgColor,
  });
}

// ── Main widget ───────────────────────────────────────────────────────────────

class ExploreSpecialtiesSection extends StatelessWidget {
  const ExploreSpecialtiesSection({super.key});

  static const List<_SpecialtyItem> _specialties = [
    _SpecialtyItem(
      icon:    Icons.favorite_border_rounded,
      title:   'Heart &\nVascular',
      accent:  AppColors.catHeart,
      bgColor: Color(0xFFFFF0F3),
    ),
    _SpecialtyItem(
      icon:    Icons.psychology_outlined,
      title:   'Brain &\nNerves',
      accent:  AppColors.catBrain,
      bgColor: Color(0xFFF5EFFF),
    ),
    _SpecialtyItem(
      icon:    Icons.self_improvement_outlined,
      title:   'Mental\nWellness',
      accent:  AppColors.catMental,
      bgColor: Color(0xFFEFF6FF),
    ),
    _SpecialtyItem(
      icon:    Icons.child_care_outlined,
      title:   'Child\nHealth',
      accent:  AppColors.catChild,
      bgColor: Color(0xFFFFFBEB),
    ),
    _SpecialtyItem(
      icon:    Icons.accessibility_new_outlined,
      title:   'Bones &\nJoints',
      accent:  AppColors.catBones,
      bgColor: Color(0xFFEFF9FF),
    ),
    _SpecialtyItem(
      icon:    Icons.air_rounded,
      title:   'Respiratory',
      accent:  AppColors.catRespire,
      bgColor: Color(0xFFEFFAF6),
    ),
    _SpecialtyItem(
      icon:    Icons.female_rounded,
      title:   "Women's\nHealth",
      accent:  AppColors.catWomen,
      bgColor: Color(0xFFFFF0F6),
    ),
    _SpecialtyItem(
      icon:    Icons.science_outlined,
      title:   'Genetics\n& Labs',
      accent:  AppColors.catGenetics,
      bgColor: Color(0xFFF0FFF3),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────────
        AppSectionHeader(
          title:       'Explore Specialties',
          seeAllLabel: 'See all',
          onSeeAll:    () {},
        ),

        const SizedBox(height: AppSpacing.md),

        // ── Horizontal scroll list ─────────────────────────────────────────
        SizedBox(
          height: 140,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding:         const EdgeInsets.symmetric(vertical: 2),
            itemCount:       _specialties.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              return _SpecialtyCard(item: _specialties[index]);
            },
          ),
        ),
      ],
    );
  }
}

// ── Specialty card ────────────────────────────────────────────────────────────

class _SpecialtyCard extends StatelessWidget {
  final _SpecialtyItem item;

  const _SpecialtyCard({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Material(
      color:        Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        splashColor:  item.accent.withOpacity(0.12),
        onTap:        () {},
        child: Container(
          width:   108,
          padding: const EdgeInsets.all(AppSpacing.md),
          decoration: BoxDecoration(
            color:        AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border:       Border.all(color: AppColors.border, width: 1.2),
            boxShadow:    AppShadows.card,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Soft tinted icon circle
              Container(
                width:  52,
                height: 52,
                decoration: BoxDecoration(
                  color: item.bgColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(item.icon, color: item.accent, size: 24),
              ),

              const SizedBox(height: AppSpacing.sm + 2),

              // Specialty label
              Text(
                item.title,
                textAlign: TextAlign.center,
                maxLines:  2,
                overflow:  TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: AppFonts.family,
                  fontSize:   11.5,
                  fontWeight: FontWeight.w600,
                  color:      AppColors.textPrimary,
                  height:     1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
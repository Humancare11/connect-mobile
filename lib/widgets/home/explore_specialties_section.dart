// Section 5 — ExploreSpecialtiesSection
// Premium redesign: horizontal scroll, soft tinted icon backgrounds,
// consistent card shadow, pill "See all" button

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';
import '../../screens/book_appointment_screen.dart';

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

  String get appointmentName => title.replaceAll(RegExp(r'\s+'), ' ').trim();
}

// ── Main widget ───────────────────────────────────────────────────────────────

class ExploreSpecialtiesSection extends StatelessWidget {
  const ExploreSpecialtiesSection({super.key});

  static const List<_SpecialtyItem> _specialties = [
  _SpecialtyItem(
    icon: Icons.medical_services_outlined,
    title: 'General\nPhysician',
    accent: AppColors.catHeart,
    bgColor: Color(0xFFEFF6FF),
  ),
  _SpecialtyItem(
    icon: Icons.local_hospital_outlined,
    title: 'Internal\nMedicine',
    accent: AppColors.catBrain,
    bgColor: Color(0xFFF5EFFF),
  ),
  _SpecialtyItem(
    icon: Icons.family_restroom_outlined,
    title: 'Family\nMedicine',
    accent: AppColors.catMental,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.psychology_outlined,
    title: 'Psychiatry',
    accent: AppColors.catMental,
    bgColor: Color(0xFFF5EFFF),
  ),
  _SpecialtyItem(
    icon: Icons.self_improvement_outlined,
    title: 'Psychology /\nCounselling',
    accent: AppColors.catMental,
    bgColor: Color(0xFFEFF6FF),
  ),
  _SpecialtyItem(
    icon: Icons.favorite_outline,
    title: 'Behavioral\nHealth',
    accent: AppColors.catMental,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.face_retouching_natural_outlined,
    title: 'Dermatology',
    accent: AppColors.catWomen,
    bgColor: Color(0xFFFFF0F6),
  ),
  _SpecialtyItem(
    icon: Icons.pregnant_woman_outlined,
    title: 'OB-GYN',
    accent: AppColors.catWomen,
    bgColor: Color(0xFFFFF0F6),
  ),
  _SpecialtyItem(
    icon: Icons.female_outlined,
    title: 'Menopause\nCare',
    accent: AppColors.catWomen,
    bgColor: Color(0xFFFFF0F6),
  ),
  _SpecialtyItem(
    icon: Icons.psychology_alt_outlined,
    title: "Women's Mental\nHealth",
    accent: AppColors.catWomen,
    bgColor: Color(0xFFFFF0F6),
  ),
  _SpecialtyItem(
    icon: Icons.child_friendly_outlined,
    title: 'Lactation\nConsulting',
    accent: AppColors.catWomen,
    bgColor: Color(0xFFFFF0F6),
  ),
  _SpecialtyItem(
    icon: Icons.man_outlined,
    title: "Men's\nHealth",
    accent: AppColors.catHeart,
    bgColor: Color(0xFFEFF6FF),
  ),
  _SpecialtyItem(
    icon: Icons.water_drop_outlined,
    title: 'Urology',
    accent: AppColors.catHeart,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.child_care_outlined,
    title: 'Pediatrics',
    accent: AppColors.catChild,
    bgColor: Color(0xFFFFFBEB),
  ),
  _SpecialtyItem(
    icon: Icons.school_outlined,
    title: 'Adolescent\nCare',
    accent: AppColors.catChild,
    bgColor: Color(0xFFFFFBEB),
  ),
  _SpecialtyItem(
    icon: Icons.monitor_weight_outlined,
    title: 'Weight\nManagement',
    accent: AppColors.catRespire,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.restaurant_menu_outlined,
    title: 'Nutrition &\nDietetics',
    accent: AppColors.catRespire,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.spa_outlined,
    title: 'Lifestyle\nMedicine',
    accent: AppColors.catRespire,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.favorite_border_rounded,
    title: 'Cardiology',
    accent: AppColors.catHeart,
    bgColor: Color(0xFFFFF0F3),
  ),
  _SpecialtyItem(
    icon: Icons.psychology_alt_outlined,
    title: 'Neurology',
    accent: AppColors.catBrain,
    bgColor: Color(0xFFF5EFFF),
  ),
  _SpecialtyItem(
    icon: Icons.science_outlined,
    title: 'Endocrinology',
    accent: AppColors.catGenetics,
    bgColor: Color(0xFFF0FFF3),
  ),
  _SpecialtyItem(
    icon: Icons.medication_outlined,
    title: 'Gastroenterology',
    accent: AppColors.catRespire,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.air_rounded,
    title: 'Pulmonology',
    accent: AppColors.catRespire,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.record_voice_over_outlined,
    title: 'Expert Medical\nOpinion',
    accent: AppColors.catBrain,
    bgColor: Color(0xFFEFF6FF),
  ),
  _SpecialtyItem(
    icon: Icons.visibility_outlined,
    title: 'Ophthalmology',
    accent: AppColors.catHeart,
    bgColor: Color(0xFFEFF6FF),
  ),
  _SpecialtyItem(
    icon: Icons.hearing_outlined,
    title: 'ENT',
    accent: AppColors.catHeart,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.accessibility_new_outlined,
    title: 'Orthopedics',
    accent: AppColors.catBones,
    bgColor: Color(0xFFEFF9FF),
  ),
  _SpecialtyItem(
    icon: Icons.favorite_outline,
    title: 'Sexual\nHealth',
    accent: AppColors.catWomen,
    bgColor: Color(0xFFFFF0F6),
  ),
  _SpecialtyItem(
    icon: Icons.flight_takeoff_outlined,
    title: 'Travel\nMedicine',
    accent: AppColors.catRespire,
    bgColor: Color(0xFFEFFAF6),
  ),
  _SpecialtyItem(
    icon: Icons.public_outlined,
    title: 'Global /\nCross-Border Care',
    accent: AppColors.catGenetics,
    bgColor: Color(0xFFF0FFF3),
  ),
  ];

  void _openAppointmentPage(
    BuildContext context, {
    String? specialtyName,
    bool showAllSpecialties = false,
  }) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentBookingPage(
          initialSpecialtyName: specialtyName,
          initialTab: showAllSpecialties ? "spec" : "cat",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ─────────────────────────────────────────────────
        AppSectionHeader(
          title:       'Explore Specialties',
          seeAllLabel: 'See all',
          onSeeAll:    () => _openAppointmentPage(
            context,
            showAllSpecialties: true,
          ),
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
              return _SpecialtyCard(
                item: _specialties[index],
                onTap: () => _openAppointmentPage(
                  context,
                  specialtyName: _specialties[index].appointmentName,
                ),
              );
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
  final VoidCallback onTap;

  const _SpecialtyCard({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color:        Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        splashColor:  item.accent.withOpacity(0.12),
        onTap:        onTap,
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

// ─────────────────────────────────────────────────────────────────────────────
// HumanCare Connect — Shared Design System
// ─────────────────────────────────────────────────────────────────────────────
//
// FONT SETUP — Add Satoshi to pubspec.yaml:
//
//   flutter:
//     fonts:
//       - family: Satoshi
//         fonts:
//           - asset: assets/fonts/Satoshi-Regular.ttf
//             weight: 400
//           - asset: assets/fonts/Satoshi-Medium.ttf
//             weight: 500
//           - asset: assets/fonts/Satoshi-Bold.ttf
//             weight: 700
//
//   Download: https://www.fontshare.com/fonts/satoshi
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// ── Colors ────────────────────────────────────────────────────────────────────

abstract class AppColors {
  // Brand
  static const Color primary       = Color(0xFF052269);
  static const Color primaryDark   = Color(0xFF031547);
  static const Color primaryMid    = Color(0xFF1A3D8F);
  static const Color primaryLight  = Color(0xFFEEF2FF);
  static const Color accent        = Color(0xFF2563EB);

  // Semantic
  static const Color success       = Color(0xFF10B981);
  static const Color warning       = Color(0xFFF59E0B);
  static const Color error         = Color(0xFFEF4444);

  // Surface & Background
  static const Color surface       = Color(0xFFFFFFFF);
  static const Color background    = Color(0xFFF7F9FC);
  static const Color border        = Color(0xFFE5E9F2);

  // Text
  static const Color textPrimary   = Color(0xFF0A0F1E);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textTertiary  = Color(0xFFB0BAC9);

  // Category / Specialty accent palette (consistent across sections)
  static const Color catHeart      = Color(0xFFFF6B81);
  static const Color catBrain      = Color(0xFFB985FF);
  static const Color catMental     = Color(0xFF4AA8FF);
  static const Color catChild      = Color(0xFFFFC857);
  static const Color catBones      = Color(0xFF7EE4FF);
  static const Color catRespire    = Color(0xFF77F0C8);
  static const Color catWomen      = Color(0xFFFF9BC2);
  static const Color catGenetics   = Color(0xFFA7F08F);
}

// ── Typography ────────────────────────────────────────────────────────────────

abstract class AppFonts {
  static const String family = 'Satoshi';
}

abstract class AppTextStyles {
  static const TextStyle h1 = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   24,
    fontWeight: FontWeight.w700,
    color:      AppColors.textPrimary,
    letterSpacing: -0.5,
  );

  static const TextStyle h2 = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   20,
    fontWeight: FontWeight.w700,
    color:      AppColors.textPrimary,
    letterSpacing: -0.3,
  );

  static const TextStyle h3 = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   16,
    fontWeight: FontWeight.w700,
    color:      AppColors.textPrimary,
    letterSpacing: -0.2,
  );

  static const TextStyle body = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   14,
    fontWeight: FontWeight.w400,
    color:      AppColors.textPrimary,
  );

  static const TextStyle bodyMedium = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   14,
    fontWeight: FontWeight.w500,
    color:      AppColors.textPrimary,
  );

  static const TextStyle caption = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   12,
    fontWeight: FontWeight.w400,
    color:      AppColors.textSecondary,
  );

  static const TextStyle captionBold = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   12,
    fontWeight: FontWeight.w600,
    color:      AppColors.textPrimary,
  );

  static const TextStyle label = TextStyle(
    fontFamily: AppFonts.family,
    fontSize:   10.5,
    fontWeight: FontWeight.w500,
    color:      AppColors.textTertiary,
    letterSpacing: 0.2,
  );
}

// ── Border Radius ─────────────────────────────────────────────────────────────

abstract class AppRadius {
  static const double xs   =  8.0;
  static const double sm   = 12.0;
  static const double md   = 16.0;
  static const double lg   = 20.0;
  static const double xl   = 24.0;
  static const double pill = 999.0;
}

// ── Shadows ───────────────────────────────────────────────────────────────────

abstract class AppShadows {
  /// Subtle card lift — white cards on #F7F9FC background.
  static List<BoxShadow> get card => [
    BoxShadow(
      color:      AppColors.primary.withOpacity(0.07),
      blurRadius: 16,
      offset:     const Offset(0, 6),
    ),
  ];

  /// Elevated CTA card — hero sections, gradient cards.
  static List<BoxShadow> get elevated => [
    BoxShadow(
      color:      AppColors.primary.withOpacity(0.28),
      blurRadius: 28,
      offset:     const Offset(0, 12),
    ),
  ];

  /// Micro-lift — grid items, small tiles.
  static List<BoxShadow> get subtle => [
    BoxShadow(
      color:      AppColors.primary.withOpacity(0.05),
      blurRadius: 8,
      offset:     const Offset(0, 3),
    ),
  ];
}

// ── Spacing ───────────────────────────────────────────────────────────────────

abstract class AppSpacing {
  static const double xs  =  4.0;
  static const double sm  =  8.0;
  static const double md  = 12.0;
  static const double lg  = 16.0;
  static const double xl  = 20.0;
  static const double xxl = 24.0;
  static const double s3x = 32.0;
}

// ── Reusable pill "See all" button ────────────────────────────────────────────

class AppSeeAllPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const AppSeeAllPill({
    super.key,
    this.label = 'See all',
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color:        AppColors.primaryLight,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontFamily: AppFonts.family,
            color:       AppColors.primary,
            fontWeight:  FontWeight.w600,
            fontSize:    12,
          ),
        ),
      ),
    );
  }
}

// ── Reusable section header row ───────────────────────────────────────────────

class AppSectionHeader extends StatelessWidget {
  final String title;
  final String seeAllLabel;
  final VoidCallback? onSeeAll;

  const AppSectionHeader({
    super.key,
    required this.title,
    this.seeAllLabel = 'See all',
    this.onSeeAll,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(title, style: AppTextStyles.h2),
        AppSeeAllPill(label: seeAllLabel, onTap: onSeeAll),
      ],
    );
  }
}
// ─────────────────────────────────────────────────────────────────────────────
// HumanCare Connect — Shared Design System
// ─────────────────────────────────────────────────────────────────────────────
//
// TYPOGRAPHY — three families, bundled as .ttf assets (see pubspec.yaml):
//
//   • Plus Jakarta Sans — headings, card titles, nav labels   → AppType.display
//   • Inter             — body copy, descriptions, inputs     → AppType.body
//   • IBM Plex Mono     — status pills, times, small labels   → AppType.mono
//
// Only the weights the design actually uses are shipped. Asking for a weight
// that is not bundled makes Flutter synthesise it from the nearest one, which
// is why headings look subtly wrong if a weight is added here without also
// adding the matching .ttf: display covers 500–800, body 400–600, mono 500–600.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

// ── Colors ────────────────────────────────────────────────────────────────────

abstract class AppColors {
  // Brand — indigo family. `primary` is the interactive/brand blue, `primaryDeep`
  // anchors the dark end of hero gradients, `primaryMid` is the light end.
  static const Color primary      = Color(0xFF2B3FA3);
  static const Color primaryDeep  = Color(0xFF141F63);
  static const Color primaryMid   = Color(0xFF33449E);
  static const Color primaryLight = Color(0xFFEAEDF9);
  static const Color accent       = Color(0xFF4356BE);

  /// Kept as an alias so pre-existing screens referencing `primaryDark`
  /// keep compiling; new code should prefer [primaryDeep].
  static const Color primaryDark  = primaryDeep;

  // Hero panel gradient. Deliberately brighter and more azure than the indigo
  // used for buttons and the nav bar: the booking card is a full-bleed surface
  // that needs to read as vivid, where the same navy that works for a 56px
  // button turns a whole panel muddy.
  static const Color heroFrom = Color(0xFF2F6BE5);
  static const Color heroMid  = Color(0xFF2450C4);
  static const Color heroTo   = Color(0xFF152C86);

  // Accent hues — each pairs a saturated ink with a soft tint used as the
  // background of icon tiles, so an icon and its container always agree.
  static const Color teal       = Color(0xFF00B6A0);
  static const Color tealInk    = Color(0xFF00998A);
  static const Color tealTint   = Color(0xFFE4F7F3);

  static const Color coral      = Color(0xFFFF6F59);
  static const Color coralInk   = Color(0xFFE85443);
  static const Color coralTint  = Color(0xFFFFEDE9);

  static const Color violetInk  = Color(0xFF5B4FCE);
  static const Color violetTint = Color(0xFFEFEBFC);

  static const Color amberInk   = Color(0xFFC9861B);
  static const Color amberTint  = Color(0xFFFFF3DE);

  // Semantic
  static const Color success = teal;
  static const Color warning = Color(0xFFF59E0B);
  static const Color error   = coral;

  // Surface & Background
  static const Color surface    = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFF5F7FC);
  static const Color border     = Color(0xFFE8EAF3);

  // Text
  static const Color textPrimary   = Color(0xFF151B33);
  static const Color textSecondary = Color(0xFF626C87);
  static const Color textTertiary  = Color(0xFF98A1B8);

  // Category / Specialty accent palette. Cycled positionally by the home
  // sections, so these are ordered to alternate hue rather than to match any
  // particular specialty — the backend does not send colors.
  static const Color catHeart    = coralInk;
  static const Color catBrain    = violetInk;
  static const Color catMental   = tealInk;
  static const Color catChild    = amberInk;
  static const Color catBones    = Color(0xFF3E7FD6);
  static const Color catRespire  = tealInk;
  static const Color catWomen    = Color(0xFFD9538C);
  static const Color catGenetics = Color(0xFF6B8F2E);

  /// Soft tints matching [catHeart]…[catGenetics], same order.
  static const List<Color> accentInks = [
    coralInk,
    violetInk,
    tealInk,
    amberInk,
    catBones,
    catWomen,
  ];

  static const List<Color> accentTints = [
    coralTint,
    violetTint,
    tealTint,
    amberTint,
    Color(0xFFE8F0FC),
    Color(0xFFFCEAF2),
  ];
}

// ── Typography ────────────────────────────────────────────────────────────────

abstract class AppFonts {
  static const String display = 'Plus Jakarta Sans';
  static const String body    = 'Inter';
  static const String mono    = 'IBM Plex Mono';

  /// Legacy token. It named 'Satoshi', which was never bundled, so every
  /// `fontFamily: AppFonts.family` call site silently rendered as the platform
  /// default. Pointing it at the body family fixes those screens in place;
  /// new code should use [AppType].
  static const String family = body;
}

abstract class AppType {
  /// Plus Jakarta Sans — headings, titles, buttons, nav labels.
  static TextStyle display({
    double size = 16,
    FontWeight weight = FontWeight.w700,
    Color color = AppColors.textPrimary,
    double? letterSpacing,
    double? height,
  }) => TextStyle(
    fontFamily: AppFonts.display,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing ?? -0.2,
    height: height,
  );

  /// Inter — body copy, descriptions, form inputs.
  static TextStyle body({
    double size = 13.5,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textSecondary,
    double? letterSpacing,
    double? height,
  }) => TextStyle(
    fontFamily: AppFonts.body,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
    height: height,
  );

  /// IBM Plex Mono — status pills, clock times, uppercase micro-labels.
  static TextStyle mono({
    double size = 11.5,
    FontWeight weight = FontWeight.w500,
    Color color = AppColors.textSecondary,
    double? letterSpacing,
  }) => TextStyle(
    fontFamily: AppFonts.mono,
    fontSize: size,
    fontWeight: weight,
    color: color,
    letterSpacing: letterSpacing,
  );
}

abstract class AppTextStyles {
  static TextStyle get h1 => AppType.display(size: 26, weight: FontWeight.w800, letterSpacing: -0.4);
  static TextStyle get h2 => AppType.display(size: 17, weight: FontWeight.w700);
  static TextStyle get h3 => AppType.display(size: 14.5, weight: FontWeight.w700);

  static TextStyle get body       => AppType.body(size: 13.5, weight: FontWeight.w400);
  static TextStyle get bodyMedium => AppType.body(size: 13.5, weight: FontWeight.w500);

  static TextStyle get caption     => AppType.body(size: 12, weight: FontWeight.w500);
  static TextStyle get captionBold => AppType.body(
    size: 12,
    weight: FontWeight.w600,
    color: AppColors.textPrimary,
  );

  static TextStyle get label => AppType.mono(
    size: 11,
    weight: FontWeight.w600,
    color: AppColors.textTertiary,
    letterSpacing: 0.4,
  );
}

// ── Border Radius ─────────────────────────────────────────────────────────────

// Values map 1:1 onto the mockup's border-radius set rather than a generic
// scale, so a card can be matched by name instead of by eyeballing a number.

abstract class AppRadius {
  static const double xs    =  8.0;
  static const double sm    = 11.0; // brand mark, small icon tiles
  static const double chip  = 13.0; // header icon buttons, avatar
  static const double md    = 14.0; // specialty icon tile, hero CTA
  static const double field = 16.0; // search bar
  static const double lg    = 18.0; // specialty + service cards, centre FAB
  static const double xl    = 20.0;
  static const double hero  = 26.0; // hero panel
  static const double pill  = 999.0;
}

// ── Shadows ───────────────────────────────────────────────────────────────────
//
// Negative spreadRadius reproduces the CSS `0 Ypx Bpx -Spx` form the mockup
// uses: the blur stays wide and soft while the shadow body is pulled back in,
// so cards read as lifted rather than outlined in grey.

abstract class AppShadows {
  static const Color _tint = Color(0xFF141F63);

  /// Subtle card lift — white cards on the #F5F7FC background.
  static List<BoxShadow> get card => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.12),
      blurRadius: 14,
      spreadRadius: -6,
      offset: const Offset(0, 2),
    ),
  ];

  /// Elevated CTA card — hero sections, gradient cards.
  static List<BoxShadow> get elevated => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.16),
      blurRadius: 28,
      spreadRadius: -12,
      offset: const Offset(0, 12),
    ),
  ];

  /// Micro-lift — grid items, small tiles.
  static List<BoxShadow> get subtle => [
    BoxShadow(
      color: _tint.withValues(alpha: 0.08),
      blurRadius: 10,
      spreadRadius: -6,
      offset: const Offset(0, 2),
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

  /// Horizontal page gutter — every home section aligns to this.
  static const double gutter = 22.0;
}

// ── Reusable white card ───────────────────────────────────────────────────────

/// The standard white surface used by every home card.
///
/// The ordering here matters and is easy to get wrong: BoxDecoration paints
/// shadows *first* and its `color` second, so a decoration that carries a
/// boxShadow but no color paints the shadow straight onto whatever is behind
/// it. Putting the white on a wrapping Material instead of in the decoration
/// therefore washes the whole card grey rather than lifting it. Background,
/// border and shadow all belong to the same decoration; the Material above it
/// exists only to host the ink splash and stays transparent.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.radius = AppRadius.lg,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.shadow,
    this.splashColor,
    this.bordered = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final EdgeInsetsGeometry padding;
  final List<BoxShadow>? shadow;
  final Color? splashColor;

  /// Hairline outline. Cards that sit on their own with a soft shadow read
  /// cleaner without it; cards packed next to each other need it to separate.
  final bool bordered;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(radius);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: borderRadius,
        border: bordered ? Border.all(color: AppColors.border) : null,
        boxShadow: shadow ?? AppShadows.subtle,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: borderRadius,
          splashColor: splashColor,
          onTap: onTap,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

// ── Reusable pill "See all" button ────────────────────────────────────────────

class AppSeeAllPill extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const AppSeeAllPill({super.key, this.label = 'See all', this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.primaryLight,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          child: Text(
            label,
            style: AppType.body(
              size: 12.5,
              weight: FontWeight.w600,
              color: AppColors.primary,
            ),
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
        Expanded(
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h2,
          ),
        ),
        const SizedBox(width: AppSpacing.sm),
        AppSeeAllPill(label: seeAllLabel, onTap: onSeeAll),
      ],
    );
  }
}

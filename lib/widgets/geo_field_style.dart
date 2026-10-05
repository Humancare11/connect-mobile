import 'package:flutter/material.dart';

import '../config/app_design_system.dart';

/// Look of the shared Country / State / City / Phone fields. Two variants so
/// the same widgets sit naturally on both kinds of screen:
///
///  * [auth] — the sign-up / social-completion screens: filled navy-outlined
///    boxes with a floating label.
///  * [profile] — the Edit Profile screen: small uppercase label above the
///    box, emoji prefix, design-system colours.
class GeoFieldStyle {
  const GeoFieldStyle._(this.isProfile);

  static const GeoFieldStyle auth = GeoFieldStyle._(false);
  static const GeoFieldStyle profile = GeoFieldStyle._(true);

  final bool isProfile;

  static const Color _navy = Color(0xff1a3a5c);

  /// Height of a single-line field, so the dial-code box lines up with the
  /// number input beside it.
  double get fieldHeight => 52;

  TextStyle get valueStyle => isProfile
      ? AppType.body(
          size: 14,
          weight: FontWeight.w600,
        ).copyWith(color: AppColors.textPrimary)
      : const TextStyle(fontSize: 14, color: Colors.black87);

  TextStyle get placeholderStyle => isProfile
      ? AppType.body(
          size: 14,
          weight: FontWeight.w600,
        ).copyWith(color: AppColors.textSecondary)
      : TextStyle(fontSize: 14, color: Colors.grey[500]);

  TextStyle get outsideLabelStyle => AppType.body(
    size: 11,
    weight: FontWeight.w900,
  ).copyWith(color: AppColors.textSecondary);

  Color get accent => isProfile ? AppColors.primary : _navy;

  /// Small leading icon: an emoji on the profile screen, an outlined icon on
  /// the auth screens.
  Widget prefix({required IconData icon, required String emoji}) {
    if (isProfile) {
      return Padding(
        padding: const EdgeInsets.only(left: 12, right: 8),
        child: Center(
          widthFactor: 1,
          child: Text(emoji, style: const TextStyle(fontSize: 16)),
        ),
      );
    }
    return Icon(icon, color: _navy, size: 20);
  }

  InputDecoration decoration({
    String? label,
    String? hint,
    String? errorText,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? counterText,
  }) {
    if (isProfile) {
      return InputDecoration(
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        hintText: hint,
        hintStyle: AppType.body(
          size: 14,
        ).copyWith(color: AppColors.textSecondary),
        errorText: errorText,
        counterText: counterText,
        filled: true,
        fillColor: AppColors.surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: Colors.redAccent),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.6),
        ),
      );
    }
    return InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.grey[600], fontSize: 14),
      hintText: hint,
      hintStyle: TextStyle(fontSize: 14, color: Colors.grey[400]),
      errorText: errorText,
      counterText: counterText,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      filled: true,
      fillColor: const Color(0xfff9fafb),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: Colors.black.withValues(alpha: 0.09)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _navy, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
      ),
    );
  }

  /// The corner radius used by tappable boxes, so the ink ripple matches.
  BorderRadius get radius =>
      BorderRadius.circular(isProfile ? AppRadius.sm : 14);

  /// On the profile screen the label sits above the box; on the auth screens
  /// it floats inside, so this just returns [child].
  Widget withOutsideLabel(String label, Widget child) {
    if (!isProfile) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label.toUpperCase(), style: outsideLabelStyle),
        const SizedBox(height: 8),
        child,
      ],
    );
  }
}

// Section 2 — SearchBarWidget
// Premium redesign: primary-tinted shadow, filter button, consistent font

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 54,
      decoration: BoxDecoration(
        color:        AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border:       Border.all(color: AppColors.border, width: 1.2),
        boxShadow:    AppShadows.card,
      ),
      child: Row(
        children: [
          // ── Search icon ────────────────────────────────────────────────
          const SizedBox(width: 16),
          const Icon(
            Icons.search_rounded,
            color: AppColors.primary,
            size:  22,
          ),

          const SizedBox(width: 10),

          // ── Input field ────────────────────────────────────────────────
          const Expanded(
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search doctors, services, specialties...',
                hintStyle: TextStyle(
                  fontFamily: AppFonts.family,
                  color:       AppColors.textTertiary,
                  fontSize:    14,
                  fontWeight:  FontWeight.w400,
                ),
                border:         InputBorder.none,
                isDense:        true,
                contentPadding: EdgeInsets.zero,
              ),
              style: TextStyle(
                fontFamily: AppFonts.family,
                fontSize:   14,
                fontWeight: FontWeight.w500,
                color:      AppColors.textPrimary,
              ),
            ),
          ),

          // ── Filter pill button ─────────────────────────────────────────
          Container(
            margin: const EdgeInsets.only(right: 8),
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color:        AppColors.primary,
              borderRadius: BorderRadius.circular(AppRadius.xs + 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.tune_rounded, color: Colors.white, size: 15),
                SizedBox(width: 5),
                Text(
                  'Filter',
                  style: TextStyle(
                    fontFamily: AppFonts.family,
                    color:       Colors.white,
                    fontSize:    12.5,
                    fontWeight:  FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
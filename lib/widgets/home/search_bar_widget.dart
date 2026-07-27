// Section 2 — SearchBarWidget
// Flat white field on the tinted page background: hairline border, soft lift,
// muted icon so the placeholder rather than the chrome reads first.

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';

class SearchBarWidget extends StatelessWidget {
  const SearchBarWidget({super.key, this.onChanged});

  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: AppColors.border),
        boxShadow: AppShadows.subtle,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.search_rounded,
            color: AppColors.textSecondary,
            size: 20,
          ),

          const SizedBox(width: 10),

          Expanded(
            child: TextField(
              onChanged: onChanged,
              cursorColor: AppColors.primary,
              decoration: InputDecoration(
                hintText: 'Search doctors, services, specialties',
                hintStyle: AppType.body(
                  size: 14.5,
                  weight: FontWeight.w400,
                  color: AppColors.textTertiary,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: AppType.body(
                size: 14.5,
                weight: FontWeight.w500,
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

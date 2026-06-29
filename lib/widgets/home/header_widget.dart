// Section 1 — HomeHeader
// Premium redesign: gradient avatar, pill location row, rounded notification

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';
import '../../screens/account_screen.dart';
import '../../services/token_storage_service.dart';

class HomeHeader extends StatelessWidget {
  const HomeHeader({super.key});

  static const TokenStorageService _tokenStorage = TokenStorageService();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, String>>(
      future: _tokenStorage.getUserProfile(),
      builder: (context, snapshot) {
        final profile = snapshot.data ?? const <String, String>{};
        final displayName = _resolveName(profile);
        final displayLocation = _resolveLocation(profile);
        final avatarInitial = displayName.isNotEmpty
            ? displayName[0].toUpperCase()
            : 'U';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Logo container ────────────────────────────────────────────────
            Container(
              width: 110,
              // height: 100,
              // padding: const EdgeInsets.all(7),
              // decoration: BoxDecoration(
              //   color: AppColors.surface,
              //   borderRadius: BorderRadius.circular(AppRadius.md),
              //   boxShadow: AppShadows.card,
              // ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: Image.asset('assets/Logo.png', fit: BoxFit.contain),
              ),
            ),

            const SizedBox(width: 12),

            // ── Greeting & Location ───────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Greeting
                  RichText(
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Hello, $displayName ',
                          style: const TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: 0,
                          ),
                        ),
                        const TextSpan(
                          text: '👋',
                          style: TextStyle(fontSize: 18),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 5),

                  // Location row
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: AppColors.primaryLight,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.location_on_rounded,
                          size: 11,
                          color: AppColors.primary,
                        ),
                      ),
                      const SizedBox(width: 5),
                      Flexible(
                        child: Text(
                          displayLocation,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 2),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 16,
                        color: AppColors.primary,
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── Notification bell ─────────────────────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    boxShadow: AppShadows.card,
                  ),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                // Unread dot
                Positioned(
                  top: 9,
                  right: 9,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.surface, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(width: 10),

            // ── Avatar ────────────────────────────────────────────────────────
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AccountScreen()),
              ),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: const LinearGradient(
                    colors: [AppColors.primary, AppColors.accent],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withOpacity(0.35),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: CircleAvatar(
                  radius: 22,
                  backgroundColor: Colors.transparent,
                  child: Text(
                    avatarInitial,
                    style: const TextStyle(
                      fontFamily: AppFonts.family,
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  String _resolveName(Map<String, String> profile) {
    final name = (profile['name'] ?? '').trim();
    if (name.isNotEmpty) return name;

    final email = (profile['email'] ?? '').trim();
    if (email.isNotEmpty && email.contains('@')) {
      return email.split('@').first;
    }

    return 'User';
  }

  String _resolveLocation(Map<String, String> profile) {
    final location = (profile['location'] ?? '').trim();
    if (location.isNotEmpty) return location;

    final city = (profile['city'] ?? '').trim();
    final state = (profile['state'] ?? '').trim();
    final country = (profile['country'] ?? '').trim();

    final parts = [
      city,
      state,
      country,
    ].where((value) => value.isNotEmpty).toList();

    if (parts.isEmpty) return 'Location not set';
    return parts.join(', ');
  }
}

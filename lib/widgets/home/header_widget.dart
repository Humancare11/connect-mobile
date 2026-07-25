// Section 1 — HomeHeader
// Premium redesign v2: refined typography, tappable location chip,
// cohesive icon buttons. All original logic (FutureBuilder / resolvers) kept intact.

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
        final avatarInitial =
            displayName.isNotEmpty ? displayName[0].toUpperCase() : 'U';

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Logo ──────────────────────────────────────────────────────────
            SizedBox(
              width: 104,
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
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Greeting
                  RichText(
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: 'Hello, $displayName ',
                          style: const TextStyle(
                            fontFamily: AppFonts.family,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                            letterSpacing: -0.3,
                            height: 1.15,
                          ),
                        ),
                        const TextSpan(
                          text: '👋',
                          style: TextStyle(fontSize: 16),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 7),

                  // Location chip (tappable)
                  Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(AppRadius.pill),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      splashColor: AppColors.primary.withValues(alpha: 0.12),
                      onTap: () {
                        // TODO: open location picker
                      },
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(8, 5, 7, 5),
                        decoration: BoxDecoration(
                          color: AppColors.primaryLight,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.location_on_rounded,
                              size: 13,
                              color: AppColors.primary,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                displayLocation,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontFamily: AppFonts.family,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: AppColors.textSecondary,
                                  height: 1,
                                ),
                              ),
                            ),
                            const SizedBox(width: 1),
                            const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 15,
                              color: AppColors.primary,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── Notification bell ─────────────────────────────────────────────
            _IconButtonBox(
              icon: Icons.notifications_none_rounded,
              hasBadge: true,
              onTap: () {
                // TODO: open notifications
              },
            ),

            const SizedBox(width: 10),

            // ── Avatar ────────────────────────────────────────────────────────
            Material(
              color: Colors.transparent,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: const LinearGradient(
                      colors: [AppColors.primary, AppColors.accent],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    border: Border.all(color: AppColors.surface, width: 2),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.primary.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  alignment: Alignment.center,
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

// ── Reusable rounded icon button with optional unread badge ──────────────────
class _IconButtonBox extends StatelessWidget {
  const _IconButtonBox({
    required this.icon,
    this.hasBadge = false,
    this.onTap,
  });

  final IconData icon;
  final bool hasBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(color: AppColors.border, width: 1),
                boxShadow: AppShadows.card,
              ),
              alignment: Alignment.center,
              child: Icon(icon, color: AppColors.primary, size: 22),
            ),
          ),
        ),
        if (hasBadge)
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
    );
  }
}
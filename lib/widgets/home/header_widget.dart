// Section 1 — HomeHeader
//
// Layout follows the home mockup: a compact gradient brand mark, the greeting
// stacked over a tappable location line, then a notification button and the
// account avatar as two equally-sized rounded squares on the right.
//
// All original logic (FutureBuilder over the stored profile, name/location
// resolvers, avatar → AccountScreen) is unchanged — this is presentation only.

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
            // ── Brand mark ────────────────────────────────────────────────
            // The heart-with-pulse glyph mirrors the mockup's mark. Swap the
            // Icon for `Image.asset('assets/Logo.png')` if the wordmark should
            // stay on the home screen.
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [AppColors.primary, AppColors.primaryDeep],
                ),
              ),
              alignment: Alignment.center,
              child: const Icon(
                Icons.monitor_heart_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),

            const SizedBox(width: 10),

            // ── Greeting & location ───────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Hi, $displayName 👋',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppType.display(size: 17, height: 1.15),
                  ),

                  const SizedBox(height: 3),

                  InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                    onTap: () {
                      // TODO: open location picker
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 13,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: 3),
                        Flexible(
                          child: Text(
                            displayLocation,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppType.body(
                              size: 12.5,
                              weight: FontWeight.w500,
                              height: 1,
                            ),
                          ),
                        ),
                        const Icon(
                          Icons.keyboard_arrow_down_rounded,
                          size: 15,
                          color: AppColors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(width: 10),

            // ── Notification bell ─────────────────────────────────────────
            _IconButtonBox(
              icon: Icons.notifications_none_rounded,
              hasBadge: true,
              onTap: () {
                // TODO: open notifications
              },
            ),

            const SizedBox(width: 10),

            // ── Avatar ────────────────────────────────────────────────────
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.chip),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const AccountScreen()),
                ),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [AppColors.accent, AppColors.primaryDeep],
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    avatarInitial,
                    style: AppType.display(size: 15, color: Colors.white),
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

// ── Rounded icon button with optional unread badge ───────────────────────────

class _IconButtonBox extends StatelessWidget {
  const _IconButtonBox({required this.icon, this.hasBadge = false, this.onTap});

  final IconData icon;
  final bool hasBadge;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        // Background, border and shadow live in one decoration — see AppCard
        // for why splitting them washes the surface grey.
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(AppRadius.chip),
            boxShadow: AppShadows.subtle,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(AppRadius.chip),
              child: Center(
                child: Icon(icon, color: AppColors.textPrimary, size: 20),
              ),
            ),
          ),
        ),
        if (hasBadge)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.coral,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface, width: 1.5),
              ),
            ),
          ),
      ],
    );
  }
}

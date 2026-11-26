// Section 4 — MostPopularSection
//
// Two full-width gradient shortcuts into the most booked specialties. The list
// is fixed in the app, so nothing is fetched here: the booking page matches
// `specialtyName` against its own tree and falls back to the full specialty
// list when there is no match.

import 'package:flutter/material.dart';

import '../../config/app_design_system.dart';
import '../../screens/book_appointment_screen.dart';

class _PopularItem {
  const _PopularItem({
    required this.title,
    required this.specialtyName,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.shadowColor,
  });

  /// Label shown on the card.
  final String title;

  /// Name the backend uses for this specialty. Can differ from [title].
  final String specialtyName;

  final String subtitle;
  final IconData icon;

  /// Painted from bottom left to top right.
  final List<Color> gradient;

  final Color shadowColor;
}

const List<_PopularItem> _popularItems = [
  _PopularItem(
    title: 'General Practitioner',
    specialtyName: 'General Physician',
    subtitle: 'Fever, cold, checkups & everyday care',
    icon: Icons.medical_services_rounded,
    gradient: [Color(0xFF141E5B), Color(0xFF1E2F8F), Color(0xFF3A5BEA)],
    shadowColor: Color(0xFF1E2F8F),
  ),
  _PopularItem(
    title: 'Pediatrics',
    specialtyName: 'Pediatrics',
    subtitle: 'Expert care for your child, newborn to teen',
    icon: Icons.child_care_rounded,
    gradient: [Color(0xFF4A1410), Color(0xFFA33A22), Color(0xFFF2845C)],
    shadowColor: Color(0xFFA33A22),
  ),
];

const double _cardRadius = 22;

class MostPopularSection extends StatelessWidget {
  const MostPopularSection({super.key, this.searchQuery = ''});

  final String searchQuery;

  List<_PopularItem> get _filteredItems {
    final query = _normalizeSearchText(searchQuery);
    if (query.isEmpty) return _popularItems;

    return _popularItems.where((item) {
      return _normalizeSearchText(item.title).contains(query) ||
          _normalizeSearchText(item.specialtyName).contains(query);
    }).toList();
  }

  void _openAppointmentPage(BuildContext context, String specialtyName) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AppointmentBookingPage(
          initialSpecialtyName: specialtyName,
          // Only takes effect when the name is not found: the user then lands
          // on the specialty list.
          initialTab: 'spec',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final items = _filteredItems;
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      // Owned by the section so a hidden section leaves no gap behind.
      padding: const EdgeInsets.only(bottom: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Most Popular',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.h2,
          ),
          const SizedBox(height: AppSpacing.md),
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(height: AppSpacing.md),
            _PopularCard(
              item: items[i],
              onTap: () =>
                  _openAppointmentPage(context, items[i].specialtyName),
            ),
          ],
        ],
      ),
    );
  }
}

class _PopularCard extends StatelessWidget {
  const _PopularCard({required this.item, required this.onTap});

  final _PopularItem item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(_cardRadius);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        gradient: LinearGradient(
          begin: Alignment.bottomLeft,
          end: Alignment.topRight,
          colors: item.gradient,
        ),
        boxShadow: [
          BoxShadow(
            color: item.shadowColor.withValues(alpha: 0.25),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Stack(
          children: [
            const _CornerCircle(diameter: 180),
            const _CornerCircle(diameter: 128),
            const _CornerCircle(diameter: 76),
            Material(
              type: MaterialType.transparency,
              child: InkWell(
                borderRadius: borderRadius,
                splashColor: Colors.white.withValues(alpha: 0.14),
                onTap: onTap,
                child: ConstrainedBox(
                  // Minimum only, so large text can make the card taller.
                  constraints: const BoxConstraints(minHeight: 108),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        _IconTile(icon: item.icon),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.display(
                                  size: 17,
                                  color: Colors.white,
                                  height: 1.2,
                                ),
                              ),
                              const SizedBox(height: AppSpacing.xs),
                              Text(
                                item.subtitle,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppType.body(
                                  size: 13,
                                  color: Colors.white.withValues(alpha: 0.8),
                                  height: 1.3,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        const _ArrowCircle(),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Faint disc centred near the card's top right corner. Several diameters share
/// the same centre; the card clips whatever falls outside it.
class _CornerCircle extends StatelessWidget {
  const _CornerCircle({required this.diameter});

  final double diameter;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 12 - diameter / 2,
      right: 36 - diameter / 2,
      child: Container(
        width: diameter,
        height: diameter,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.06),
        ),
      ),
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(AppRadius.field),
        border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 30, color: Colors.white),
    );
  }
}

class _ArrowCircle extends StatelessWidget {
  const _ArrowCircle();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
      ),
      alignment: Alignment.center,
      child: const Icon(
        Icons.chevron_right_rounded,
        size: 26,
        color: AppColors.textPrimary,
      ),
    );
  }
}

String _normalizeSearchText(String value) {
  return value.toLowerCase().replaceAll(RegExp(r'\s+'), ' ').trim();
}

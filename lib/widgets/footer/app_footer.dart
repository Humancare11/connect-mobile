// AppFooter — edge-to-edge translucent bar with a raised active indicator.
//
// The raised gradient tile marks the *selected* destination and slides between
// slots as tabs change, rather than being permanently parked over Book. Book
// keeps its "+" glyph, so when it is the selected tab the bar looks exactly
// like a conventional centre action; when it is not, the lift follows wherever
// the user actually is.
//
// Indices are MainScreen's page indices directly (0 Home, 1 Appointments,
// 2 Book, 3 Records, 4 Account), so no translation happens in either direction.

import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../config/app_design_system.dart';

class _Destination {
  const _Destination({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int index;
}

class AppFooter extends StatelessWidget {
  final int selectedIndex;
  final Function(int)? onTap;

  const AppFooter({super.key, this.selectedIndex = 0, this.onTap});

  static const List<_Destination> _destinations = [
    _Destination(
      icon: Icons.home_outlined,
      activeIcon: Icons.home_rounded,
      label: 'Home',
      index: 0,
    ),
    _Destination(
      icon: Icons.calendar_today_outlined,
      activeIcon: Icons.calendar_today_rounded,
      label: 'Appointments',
      index: 1,
    ),
    _Destination(
      icon: Icons.add_rounded,
      activeIcon: Icons.add_rounded,
      label: 'Book',
      index: 2,
    ),
    _Destination(
      icon: Icons.folder_open_rounded,
      activeIcon: Icons.folder_rounded,
      label: 'Records',
      index: 3,
    ),
    _Destination(
      icon: Icons.person_outline_rounded,
      activeIcon: Icons.person_rounded,
      label: 'Profile',
      index: 4,
    ),
  ];

  /// How far the raised tile rises above the bar's top edge.
  static const double _overhang = 22;
  static const double _tileSize = 56;

  /// Row height before the bottom inset — the mockup's 92px bar less its 18px
  /// bottom padding.
  static const double _rowHeight = 74;

  /// Floor for the bottom padding, so a device that reports no gesture inset
  /// still gets the mockup's 18px breathing room instead of a 74px stub.
  static const double _minBottomPadding = 18;

  int get _activeSlot {
    final slot = _destinations.indexWhere((d) => d.index == selectedIndex);
    // Fall back to Home rather than -1 if a caller ever selects an index the
    // bar does not represent, so the indicator always has somewhere to sit.
    return slot < 0 ? 0 : slot;
  }

  @override
  Widget build(BuildContext context) {
    // The bar is not inside a SafeArea, so it absorbs the gesture inset itself
    // and keeps its icons clear of the home indicator.
    final bottomInset = math.max(
      MediaQuery.of(context).padding.bottom,
      _minBottomPadding,
    );
    final barHeight = _rowHeight + bottomInset;

    return SizedBox(
      height: barHeight + _overhang,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final slotWidth = constraints.maxWidth / _destinations.length;
          final indicatorLeft =
              slotWidth * _activeSlot + (slotWidth - _tileSize) / 2;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: ClipRect(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: Container(
                      height: barHeight,
                      padding: EdgeInsets.only(bottom: bottomInset),
                      decoration: BoxDecoration(
                        color: AppColors.surface.withValues(alpha: 0.92),
                        border: const Border(
                          top: BorderSide(color: AppColors.border),
                        ),
                      ),
                      child: Row(
                        children: [
                          for (final destination in _destinations)
                            _NavItem(
                              destination: destination,
                              isSelected: destination.index == selectedIndex,
                              onTap: onTap,
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // ── Center floating "Book" button ──────────────────────────────
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Gradient circle — blue brand colors
                      GestureDetector(
                        onTap: () => onTap?.call(2),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          width: 62,
                          height: 62,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [AppColors.primary, AppColors.accent],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.primary.withValues(
                                  alpha: 0.38,
                                ),
                                blurRadius: 18,
                                spreadRadius: 0,
                                offset: const Offset(0, 7),
                              ),
                            ],
                          ),
                          child: const Icon(
                            Icons.add,
                            color: Colors.white,
                            size: 32,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Nav Item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final _Destination destination;
  final bool isSelected;
  final Function(int)? onTap;

  const _NavItem({
    required this.destination,
    required this.isSelected,
    required this.onTap,
  });

  /// not the raised tile is covering this slot's icon.
  static const double _iconSlot = 21;

  @override
  Widget build(BuildContext context) {
    final Color color = isSelected
        ? AppColors.primary
        : AppColors.textTertiary;

    return Expanded(
      child: GestureDetector(
        onTap: () => onTap?.call(destination.index),
        behavior: HitTestBehavior.opaque,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            // The raised tile already draws the selected destination's icon,
            // so this slot only reserves its space.
            isSelected
                ? const SizedBox(height: _iconSlot)
                : Icon(destination.icon, size: _iconSlot, color: color),
            const SizedBox(height: 5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Text(
                destination.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: AppType.display(
                  size: 10.5,
                  weight: FontWeight.w600,
                  color: color,
                  letterSpacing: 0,
                  height: 1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

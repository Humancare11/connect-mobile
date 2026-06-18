// AppFooter — Blue color + floating card with all-rounded corners + bottom margin
//
// Changes from previous version:
//   • Color: teal #00A884 → primary blue #052269 / accent #2563EB
//   • Shape: top-only rounded → all 4 corners rounded (BorderRadius.circular(26))
//   • Margin: 16px left/right + 12px bottom → floating card look
//   • FAB: solid teal → blue gradient (#052269 → #2563EB)
//   • Shadow: top-only → soft all-around card shadow
//
// File: lib/widgets/footer/app_footer.dart

import 'package:flutter/material.dart';

class AppFooter extends StatelessWidget {
  final int selectedIndex;
  final Function(int)? onTap;

  const AppFooter({
    super.key,
    this.selectedIndex = 0,
    this.onTap,
  });

  // ── Color tokens ───────────────────────────────────────────────────────────
  static const Color _primary      = Color(0xFF052269);
  static const Color _accent       = Color(0xFF2563EB);
  static const Color _primaryLight = Color(0xFFEEF2FF);
  static const Color _inactive     = Color(0xFF9AA4B2);

  @override
  Widget build(BuildContext context) {
    return Container(
      // Floating card margins — left/right + bottom
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: SizedBox(
        height: 86,                         // bar(68) + button overflow(18)
        child: Stack(
          clipBehavior: Clip.none,
          children: [

            // ── Bar card (all 4 corners rounded) ──────────────────────────────
            Positioned(
              bottom: 0,
              left:   0,
              right:  0,
              child: Container(
                height: 68,
                decoration: BoxDecoration(
                  color: Colors.white,
                  // All 4 corners — same radius top & bottom
                  borderRadius: BorderRadius.circular(26),
                  boxShadow: [
                    BoxShadow(
                      color:      _primary.withOpacity(0.10),
                      blurRadius: 24,
                      spreadRadius: 0,
                      offset:     const Offset(0, 4),
                    ),
                    BoxShadow(
                      color:      _primary.withOpacity(0.06),
                      blurRadius: 8,
                      offset:     const Offset(0, -2),
                    ),
                  ],
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _NavItem(
                        icon:          Icons.home_outlined,
                        activeIcon:    Icons.home_rounded,
                        label:         'Home',
                        index:         0,
                        selectedIndex: selectedIndex,
                        onTap:         onTap,
                      ),
                      _NavItem(
                        icon:          Icons.medical_services_outlined,
                        activeIcon:    Icons.medical_services_rounded,
                        label:         'Services',
                        index:         1,
                        selectedIndex: selectedIndex,
                        onTap:         onTap,
                      ),

                      // Gap beneath floating center button
                      const SizedBox(width: 68),

                      _NavItem(
                        icon:          Icons.calendar_today_outlined,
                        activeIcon:    Icons.calendar_today_rounded,
                        label:         'Appointments',
                        index:         3,
                        selectedIndex: selectedIndex,
                        onTap:         onTap,
                      ),
                      _NavItem(
                        icon:          Icons.person_outline_rounded,
                        activeIcon:    Icons.person_rounded,
                        label:         'Account',
                        index:         4,
                        selectedIndex: selectedIndex,
                        onTap:         onTap,
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // ── Center floating "Book" button ──────────────────────────────────
            Positioned(
              top:   0,
              left:  0,
              right: 0,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [

                    // Gradient circle — blue brand colors
                    GestureDetector(
                      onTap:    () => onTap?.call(2),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width:  62,
                        height: 62,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [_primary, _accent],
                            begin:  Alignment.topLeft,
                            end:    Alignment.bottomRight,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color:        _primary.withOpacity(0.38),
                              blurRadius:   18,
                              spreadRadius: 0,
                              offset:       const Offset(0, 7),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.add,
                          color: Colors.white,
                          size:  32,
                        ),
                      ),
                    ),

                    const SizedBox(height: 3),

                    // "Book" label
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 200),
                      style: TextStyle(
                        fontSize:   10,
                        fontWeight: FontWeight.w600,
                        color: selectedIndex == 2 ? _primary : _inactive,
                        height: 1,
                      ),
                      child: const Text('Book'),
                    ),
                  ],
                ),
              ),
            ),

          ],
        ),
      ),
    );
  }
}

// ── Nav Item ──────────────────────────────────────────────────────────────────

class _NavItem extends StatelessWidget {
  final IconData       icon;
  final IconData       activeIcon;
  final String         label;
  final int            index;
  final int            selectedIndex;
  final Function(int)? onTap;

  static const Color _primary      = Color(0xFF052269);
  static const Color _primaryLight = Color(0xFFEEF2FF);
  static const Color _inactive     = Color(0xFF9AA4B2);

  const _NavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    required this.index,
    required this.selectedIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final bool isSelected = selectedIndex == index;

    return GestureDetector(
      onTap:    () => onTap?.call(index),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [

            // ── Pill indicator ───────────────────────────────────────────────
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve:    Curves.easeInOut,
              padding: EdgeInsets.symmetric(
                horizontal: isSelected ? 14 : 8,
                vertical:   5,
              ),
              decoration: BoxDecoration(
                color: isSelected ? _primaryLight : Colors.transparent,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Icon(
                isSelected ? activeIcon : icon,
                size:  22,
                color: isSelected ? _primary : _inactive,
              ),
            ),

            const SizedBox(height: 3),

            // ── Label ────────────────────────────────────────────────────────
            AnimatedDefaultTextStyle(
              duration: const Duration(milliseconds: 200),
              style: TextStyle(
                fontSize:   10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color:      isSelected ? _primary : _inactive,
                height:     1,
              ),
              child: Text(label, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),

          ],
        ),
      ),
    );
  }
}
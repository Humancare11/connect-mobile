// Section 3 — BookAppointmentCard (Fixed)
// Fixes: removed static const list (caused null type error with abstract class
// constants across files), replaced AnimatedSwitcher+SizeTransition with
// AnimatedSize (avoids null layout constraints inside Stack), inlined
// sub-widgets to remove private-type resolution issues.

import 'package:flutter/material.dart';
import '../../config/app_design_system.dart';

class BookAppointmentCard extends StatefulWidget {
  const BookAppointmentCard({super.key});

  @override
  State<BookAppointmentCard> createState() => _BookAppointmentCardState();
}

class _BookAppointmentCardState extends State<BookAppointmentCard> {
  bool _expanded = false;

  // FIX 1: Use final (non-const) Map list — avoids null type error caused by
  // static const referencing abstract class constants from another file.
  final List<Map<String, dynamic>> _categories = [
    {'icon': Icons.favorite_border_rounded,   'title': 'Heart & Vascular',  'color': const Color(0xFFFF6B81)},
    {'icon': Icons.psychology_outlined,        'title': 'Brain & Nerves',    'color': const Color(0xFFB18CFF)},
    {'icon': Icons.self_improvement_outlined,  'title': 'Mental Wellness',   'color': const Color(0xFF7AD7F0)},
    {'icon': Icons.child_care_outlined,        'title': 'Child Health',      'color': const Color(0xFFFFC371)},
    {'icon': Icons.accessibility_new_outlined, 'title': 'Bones & Joints',   'color': const Color(0xFFB0C4FF)},
    {'icon': Icons.air_rounded,                'title': 'Respiratory',       'color': const Color(0xFF6FE3C5)},
    {'icon': Icons.female_rounded,             'title': "Women's Health",    'color': const Color(0xFFFF9ECF)},
    {'icon': Icons.science_outlined,           'title': 'Genetics & Labs',   'color': const Color(0xFFA0F0A8)},
  ];

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          gradient: const LinearGradient(
            begin:  Alignment.topLeft,
            end:    Alignment.bottomRight,
            colors: [
              AppColors.primary,
              AppColors.primaryMid,
              AppColors.accent,
            ],
            stops: [0.0, 0.45, 1.0],
          ),
          boxShadow: AppShadows.elevated,
        ),
        // FIX 2: ClipRRect wraps the Stack so orbs are clipped, and the Stack
        // sizes itself to the Padding (only non-Positioned child) — this gives
        // AnimatedSize a valid finite height constraint to animate against.
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: Stack(
            children: [
              // ── Decorative orbs (visual only, clipped by ClipRRect) ──────
              Positioned(
                top: -35, right: -25,
                child: Container(
                  width: 120, height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.07),
                  ),
                ),
              ),
              Positioned(
                top: 60, right: 40,
                child: Container(
                  width: 50, height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.04),
                  ),
                ),
              ),
              Positioned(
                bottom: -30, left: 10,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withOpacity(0.05),
                  ),
                ),
              ),

              // ── Main content (non-Positioned → defines Stack height) ─────
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    // ── Badge + Toggle row ───────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Live availability badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(
                            color:        Colors.white.withOpacity(0.12),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            border: Border.all(
                                color: Colors.white.withOpacity(0.16)),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 7, height: 7,
                                decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 7),
                              const Text(
                                'Available 24/7 · HIPAA Compliant',
                                style: TextStyle(
                                  fontFamily: AppFonts.family,
                                  color:       Colors.white,
                                  fontSize:    10.5,
                                  fontWeight:  FontWeight.w500,
                                  letterSpacing: 0.1,
                                ),
                              ),
                            ],
                          ),
                        ),

                        // Expand / collapse toggle
                        GestureDetector(
                          onTap: () =>
                              setState(() => _expanded = !_expanded),
                          child: Container(
                            padding: const EdgeInsets.all(7),
                            decoration: BoxDecoration(
                              color:  Colors.white.withOpacity(0.12),
                              shape:  BoxShape.circle,
                              border: Border.all(
                                  color: Colors.white.withOpacity(0.18)),
                            ),
                            child: AnimatedRotation(
                              turns:    _expanded ? 0.5 : 0.0,
                              duration: const Duration(milliseconds: 280),
                              child: const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size:  20,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Title ────────────────────────────────────────────────
                    const Text(
                      'Book an Appointment',
                      style: TextStyle(
                        fontFamily:    AppFonts.family,
                        color:         Colors.white,
                        fontSize:      22,
                        fontWeight:    FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),

                    const SizedBox(height: 4),

                    const Text(
                      'Choose a specialty to get started',
                      style: TextStyle(
                        fontFamily: AppFonts.family,
                        color:       Colors.white60,
                        fontSize:    13,
                        fontWeight:  FontWeight.w400,
                      ),
                    ),

                    AnimatedCrossFade(
                      duration: const Duration(milliseconds: 300),
                      sizeCurve: Curves.easeInOut,
                      crossFadeState: _expanded
                          ? CrossFadeState.showSecond
                          : CrossFadeState.showFirst,
                      firstChild: const SizedBox.shrink(),
                      secondChild: _buildExpandedContent(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Expanded content (inlined — avoids private type passing between classes)

  Widget _buildExpandedContent() {
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: Column(
        children: [

          // Category chips grid
          GridView.builder(
            shrinkWrap: true,
            physics:    const NeverScrollableScrollPhysics(),
            itemCount:  _categories.length,
            gridDelegate:
                const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount:   2,
              mainAxisSpacing:  8,
              crossAxisSpacing: 8,
              childAspectRatio: 4.0,
            ),
            itemBuilder: (context, index) {
              // FIX: Explicit typed locals from Map — eliminates
              // "type 'Null' is not a subtype" cast errors.
              final Map<String, dynamic> item = _categories[index];
              final Color    accent = item['color'] as Color;
              final IconData icon   = item['icon']  as IconData;
              final String   title  = item['title'] as String;

              return Material(
                color:        Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  splashColor:  accent.withOpacity(0.18),
                  onTap:        () {},
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 11),
                    decoration: BoxDecoration(
                      color:        Colors.white.withOpacity(0.08),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(
                          color: Colors.white.withOpacity(0.12)),
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(
                            color: accent.withOpacity(0.22),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: accent, size: 13),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            title,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontFamily:    AppFonts.family,
                              color:         Colors.white,
                              fontSize:      11,
                              fontWeight:    FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          // View all categories button
          GestureDetector(
            onTap: () {},
            child: Container(
              height: 46,
              width:  double.infinity,
              decoration: BoxDecoration(
                color:        Colors.white.withOpacity(0.10),
                borderRadius: BorderRadius.circular(AppRadius.sm),
                border: Border.all(
                    color: Colors.white.withOpacity(0.22)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'View all categories',
                    style: TextStyle(
                      fontFamily: AppFonts.family,
                      color:       Colors.white,
                      fontWeight:  FontWeight.w600,
                      fontSize:    13.5,
                    ),
                  ),
                  SizedBox(width: 6),
                  Icon(
                    Icons.arrow_forward_rounded,
                    color: Colors.white,
                    size:  16,
                  ),
                ],
              ),
            ),
          ),

        ],
      ),
    );
  }
}
// // Section 4 — BookByService
// // Premium redesign: white collapsible header, clean white service cards with
// // accent icon circles and chevron affordance. Visually distinct from
// // BookAppointmentCard (dark) and MedicalServicesSection (icon+subtitle grid).

// import 'package:flutter/material.dart';
// import '../../config/app_design_system.dart';

// // ── Data model ────────────────────────────────────────────────────────────────

// class _ServiceItem {
//   final IconData icon;
//   final String   title;
//   final Color    accent;

//   const _ServiceItem({
//     required this.icon,
//     required this.title,
//     required this.accent,
//   });
// }

// // ── Main widget ───────────────────────────────────────────────────────────────

// class BookByService extends StatefulWidget {
//   const BookByService({super.key});

//   @override
//   State<BookByService> createState() => _BookByServiceState();
// }

// class _BookByServiceState extends State<BookByService> {
//   bool _expanded = false;

//   static const List<_ServiceItem> _services = [
//     _ServiceItem(icon: Icons.favorite_border_rounded,   title: 'Heart & Vascular',  accent: AppColors.catHeart),
//     _ServiceItem(icon: Icons.psychology_outlined,        title: 'Brain & Nerves',    accent: AppColors.catBrain),
//     _ServiceItem(icon: Icons.self_improvement_outlined,  title: 'Mental Wellness',   accent: AppColors.catMental),
//     _ServiceItem(icon: Icons.child_care_outlined,        title: 'Child Health',      accent: AppColors.catChild),
//     _ServiceItem(icon: Icons.accessibility_new_outlined, title: 'Bones & Joints',   accent: AppColors.catBones),
//     _ServiceItem(icon: Icons.air_rounded,                title: 'Respiratory',       accent: AppColors.catRespire),
//     _ServiceItem(icon: Icons.female_rounded,             title: "Women's Health",    accent: AppColors.catWomen),
//     _ServiceItem(icon: Icons.science_outlined,           title: 'Genetics & Labs',   accent: AppColors.catGenetics),
//   ];

//   // @override
//   // Widget build(BuildContext context) {
//   //   return Column(
//   //     crossAxisAlignment: CrossAxisAlignment.start,
//   //     children: [

// @override
// Widget build(BuildContext context) {
//   return Padding(
//     padding: const EdgeInsets.symmetric(
//       vertical: 25,
//     ),
//     child: Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         // ── Collapsible header card ────────────────────────────────────────
//         GestureDetector(
//           onTap: () => setState(() => _expanded = !_expanded),
//           child: Container(
//             padding: const EdgeInsets.symmetric(
//               horizontal: AppSpacing.xl,
//               vertical:   AppSpacing.lg,
//             ),
//             decoration: BoxDecoration(
//               color:        AppColors.surface,
//               borderRadius: BorderRadius.circular(AppRadius.lg),
//               border:       Border.all(color: AppColors.border, width: 1.2),
//               boxShadow:    AppShadows.card,
//             ),
//             child: Row(
//               children: [
//                 // Icon container
//                 Container(
//                   width:  52,
//                   height: 52,
//                   decoration: BoxDecoration(
//                     color:        AppColors.primaryLight,
//                     borderRadius: BorderRadius.circular(AppRadius.sm + 3),
//                   ),
//                   child: const Icon(
//                     Icons.health_and_safety_outlined,
//                     color: AppColors.primary,
//                     size:  26,
//                   ),
//                 ),

//                 const SizedBox(width: 14),

//                 // Title + subtitle
//                 const Expanded(
//                   child: Column(
//                     crossAxisAlignment: CrossAxisAlignment.start,
//                     children: [
//                       Text(
//                         'Book by Service',
//                         style: TextStyle(
//                           fontFamily:    AppFonts.family,
//                           fontSize:      18,
//                           fontWeight:    FontWeight.w700,
//                           color:         AppColors.textPrimary,
//                           letterSpacing: -0.2,
//                         ),
//                       ),
//                       SizedBox(height: 3),
//                       Text(
//                         'Prescriptions · Therapy · Chronic Care',
//                         style: TextStyle(
//                           fontFamily: AppFonts.family,
//                           fontSize:   12.5,
//                           fontWeight: FontWeight.w400,
//                           color:      AppColors.textSecondary,
//                         ),
//                       ),
//                     ],
                        
//                   ),
                      
//                 ),

//                 // Chevron toggle
//                 AnimatedRotation(
//                   turns:    _expanded ? 0.5 : 0.0,
//                   duration: const Duration(milliseconds: 280),
//                   child: Container(
//                     padding: const EdgeInsets.all(6),
//                     decoration: BoxDecoration(
//                       color:        AppColors.primaryLight,
//                       borderRadius: BorderRadius.circular(AppRadius.xs),
//                     ),
//                     child: const Icon(
//                       Icons.keyboard_arrow_down_rounded,
//                       size:  20,
//                       color: AppColors.primary,
//                     ),
//                   ),
//                 ),
//               ],
//             ),
              
//           ),
//         ),

//         // ── Animated service grid ──────────────────────────────────────────
//         AnimatedSize(
//           duration: const Duration(milliseconds: 300),
//           curve:    Curves.easeInOut,
//           child: _expanded
//               ? Padding(
//                   padding: const EdgeInsets.only(top: AppSpacing.md),
//                   child: GridView.builder(
//                     shrinkWrap: true,
//                     physics:    const NeverScrollableScrollPhysics(),
//                     itemCount:  _services.length,
//                     gridDelegate:
//                         const SliverGridDelegateWithFixedCrossAxisCount(
//                       crossAxisCount:   2,
//                       crossAxisSpacing: 10,
//                       mainAxisSpacing:  10,
//                       childAspectRatio: 2.85,
//                     ),
//                     itemBuilder: (context, index) {
//                       return _ServiceCard(item: _services[index]);
//                     },
//                   ),
//                 )
//               : const SizedBox.shrink(),
//         ),
//       ],
//     ),
//   );
//   }
// }

// // ── Service card tile ─────────────────────────────────────────────────────────

// class _ServiceCard extends StatelessWidget {
//   final _ServiceItem item;

//   const _ServiceCard({super.key, required this.item});

//   @override
//   Widget build(BuildContext context) {
//     return Material(
//       color:        Colors.transparent,
//       borderRadius: BorderRadius.circular(AppRadius.md),
//       child: InkWell(
//         borderRadius: BorderRadius.circular(AppRadius.md),
//         splashColor:  item.accent.withOpacity(0.12),
//         highlightColor: item.accent.withOpacity(0.06),
//         onTap: () {},
//         child: Container(
//           padding: const EdgeInsets.symmetric(
//             horizontal: AppSpacing.md,
//             vertical:   AppSpacing.sm + 2,
//           ),
//           decoration: BoxDecoration(
//             color:        AppColors.surface,
//             borderRadius: BorderRadius.circular(AppRadius.md),
//             border:       Border.all(color: AppColors.border, width: 1.2),
//             boxShadow:    AppShadows.subtle,
//           ),
//           child: Row(
//             children: [
//               // Accent icon circle
//               Container(
//                 width:  38,
//                 height: 38,
//                 decoration: BoxDecoration(
//                   color: item.accent.withOpacity(0.12),
//                   shape: BoxShape.circle,
//                 ),
//                 child: Icon(item.icon, size: 18, color: item.accent),
//               ),

//               const SizedBox(width: 10),

//               // Service name
//               Expanded(
//                 child: Text(
//                   item.title,
//                   maxLines:  1,
//                   overflow:  TextOverflow.ellipsis,
//                   style: const TextStyle(
//                     fontFamily: AppFonts.family,
//                     color:       AppColors.textPrimary,
//                     fontSize:    12.5,
//                     fontWeight:  FontWeight.w600,
//                   ),
//                 ),
//               ),

//               // Chevron affordance
//               const Icon(
//                 Icons.chevron_right_rounded,
//                 size:  18,
//                 color: AppColors.textTertiary,
//               ),
//             ],
//           ),
//         ),
//       ),
    
//     );
//   }
// }
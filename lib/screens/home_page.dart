import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../widgets/home/header_widget.dart';
import '../widgets/home/search_bar_widget.dart';
import '../widgets/home/book_appointment_card.dart';
import '../widgets/home/explore_specialties_section.dart';
import '../widgets/home/medical_services_section.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  String _searchQuery = '';

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.background,
      child: SafeArea(
        bottom: false,
        child: ListView(
          // No horizontal padding here: sections apply the gutter themselves so
          // the specialty strip can bleed past it and scroll to the screen edge.
          padding: const EdgeInsets.only(top: 6, bottom: 24),
          children: [
            const _Gutter(child: HomeHeader()),

            const SizedBox(height: 18),

            _Gutter(
              child: SearchBarWidget(
                onChanged: (value) => setState(() => _searchQuery = value),
              ),
            ),

            const SizedBox(height: 20),

            _Gutter(child: BookAppointmentCard(searchQuery: _searchQuery)),

            const SizedBox(height: 22),

            ExploreSpecialtiesSection(searchQuery: _searchQuery),

            const SizedBox(height: 22),

            _Gutter(child: MedicalServicesSection(searchQuery: _searchQuery)),
          ],
        ),
      ),
    );
  }
}

/// Applies the shared home page gutter. Sections that need to bleed to the
/// screen edge simply opt out by not being wrapped in one.
class _Gutter extends StatelessWidget {
  const _Gutter({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.gutter),
      child: child,
    );
  }
}

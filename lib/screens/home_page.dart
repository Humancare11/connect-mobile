import 'package:flutter/material.dart';

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
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const HomeHeader(),

            const SizedBox(height: 18),

            SearchBarWidget(
              onChanged: (value) => setState(() => _searchQuery = value),
            ),

            const SizedBox(height: 18),

            BookAppointmentCard(searchQuery: _searchQuery),

            const SizedBox(height: 18),

            ExploreSpecialtiesSection(searchQuery: _searchQuery),

            const SizedBox(height: 18),

            MedicalServicesSection(searchQuery: _searchQuery),

            const SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}

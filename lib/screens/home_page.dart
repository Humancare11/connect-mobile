import 'package:flutter/material.dart';

import '../widgets/home/header_widget.dart';
import '../widgets/home/search_bar_widget.dart';
import '../widgets/home/book_appointment_card.dart';
// import '../widgets/home/bookbyservice.dart'; // Remove this import
import '../widgets/home/explore_specialties_section.dart';
import '../widgets/home/medical_services_section.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            HomeHeader(),

            SizedBox(height: 18),

            SearchBarWidget(),

            SizedBox(height: 18),

            BookAppointmentCard(),
            
const SizedBox(height: 18),

            ExploreSpecialtiesSection(),

            SizedBox(height: 18),

            MedicalServicesSection(),

            SizedBox(height: 18),
          ],
        ),
      ),
    );
  }
}
import 'package:flutter/material.dart';

import '../widgets/home/header_widget.dart';
import '../widgets/home/search_bar_widget.dart';
import '../widgets/home/book_appointment_card.dart';

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
          ],
        ),
      ),
    );
  }
}
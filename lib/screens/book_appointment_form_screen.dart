import 'package:flutter/material.dart';

class BookAppointmentFormScreen extends StatelessWidget {
  const BookAppointmentFormScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Appointment Form"),
      ),
      body: const Center(
        child: Text("Appointment Form"),
      ),
    );
  }
}
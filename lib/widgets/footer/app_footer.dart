import 'package:flutter/material.dart';

import '../../screens/appointments_screen.dart';
import '../../screens/profile_settings_screen.dart';
import '../../screens/questions_screen.dart';

class AppFooter extends StatelessWidget {
  const AppFooter({super.key, this.currentIndex = 0, this.onTap});

  final int currentIndex;
  final ValueChanged<int>? onTap;

  void _handleTap(BuildContext context, int index) {
    onTap?.call(index);
    switch (index) {
      case 1:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AppointmentsScreen()),
        );
        break;
      case 2:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const QuestionsScreen()),
        );
        break;
      case 3:
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const ProfileSettingsScreen()),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: (index) => _handleTap(context, index),
      selectedItemColor: Colors.teal,
      unselectedItemColor: Colors.grey,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.home),
          label: "Home",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_month),
          label: "Appointments",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.question_answer),
          label: "Questions",
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.person),
          label: "Profile",
        ),
      ],
    );
  }
}

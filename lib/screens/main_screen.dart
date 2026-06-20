import 'package:flutter/material.dart';

import 'home_page.dart';
import 'appointments_screen.dart';
import 'book_appointment_screen.dart';
import 'account_screen.dart';
import '../widgets/footer/app_footer.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int selectedIndex = 0;

  final List<Widget> pages = const [
    HomeScreen(),             // 0
    AppointmentsScreen(),     // 1
    AppointmentBookingPage(),   // 2 (Book Button)
    AccountScreen(),  // 3
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[selectedIndex],
      bottomNavigationBar: AppFooter(
        selectedIndex: selectedIndex,
        onTap: (index) {
          int pageIndex = 0;

          switch (index) {
            case 0: // Home
              pageIndex = 0;
              break;

            case 1: // Services
              pageIndex = 1;
              break;

            case 2: // Center Book Button
              pageIndex = 2;
              break;

            case 3: // Appointments
              pageIndex = 1;
              break;

            case 4: // Account
              pageIndex = 3;
              break;
          }

          setState(() {
            selectedIndex = pageIndex;
          });
        },
      ),
    );
  }
}

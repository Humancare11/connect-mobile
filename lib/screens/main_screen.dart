import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import 'home_page.dart';
import 'appointments_screen.dart';
import 'book_appointment_screen.dart';
import 'my_records_screen.dart';
import 'account_screen.dart';
import '../widgets/footer/app_footer.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({super.key, this.initialIndex = 0, this.appointmentId});

  final int initialIndex;
  final String? appointmentId;

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int selectedIndex;

  // Built once and kept alive via IndexedStack (below) instead of a getter
  // that would hand Flutter a brand-new widget instance on every rebuild.
  // With `body: pages[selectedIndex]` swapping the widget in that slot, the
  // outgoing tab's State was disposed and the incoming tab got a fresh
  // State every time — losing scroll position, search text, and loaded data
  // on every tab switch.
  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialIndex.clamp(0, 4);
    _pages = [
      // Built once here (not in build) so the tab keeps its State; the
      // callback lets Home move the shell to the Appointments tab.
      HomeScreen(
        onOpenAppointments: () => setState(() => selectedIndex = 1),
      ), // 0
      AppointmentsScreen(activityId: widget.appointmentId), // 1
      const AppointmentBookingPage(), // 2 (Book Button)
      // Records was previously an orphan screen with no route into it; the
      // footer now exposes it as a tab. Account moved 3 → 4 as a result, which
      // is safe because no caller passes initialIndex above 2.
      const MyRecordsPage(), // 3
      const AccountScreen(), // 4
    ];
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: IndexedStack(index: selectedIndex, children: _pages),
      // AppFooter's nav items now report indices directly in this same
      // page-index space (see app_footer.dart), so no translation is
      // needed here anymore — the previous switch mapped footer index 3
      // ("Appointments") to page index 1, but AppFooter itself still
      // compared its own selectedIndex against index 3 for highlighting,
      // so the Appointments tab never showed as selected.
      bottomNavigationBar: AppFooter(
        selectedIndex: selectedIndex,
        onTap: (index) => setState(() => selectedIndex = index),
      ),
    );
  }
}

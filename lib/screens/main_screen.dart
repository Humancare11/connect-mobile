import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // Lets code outside the widget tree (currently just NotificationService)
  // switch the tab on an already-mounted MainScreen instead of tearing it
  // down and pushing a brand-new one — the old path discarded every other
  // tab's scroll/search state just to land on Home or Book. Only safe for
  // tab switches with no deep-link payload of their own; appointment-
  // specific navigation still pushes a fresh MainScreen so the target tab
  // reliably picks up its appointmentId (see NotificationService).
  static _MainScreenState? _activeState;

  static bool switchToTab(int index) {
    final state = _activeState;
    if (state == null || !state.mounted) return false;
    state._selectTab(index);
    return true;
  }

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  late int selectedIndex;

  // Slots are filled lazily (null until a tab is first selected) and kept
  // alive afterwards via IndexedStack instead of a getter that would hand
  // Flutter a brand-new widget instance on every rebuild. With
  // `body: pages[selectedIndex]` swapping the widget in that slot, the
  // outgoing tab's State was disposed and the incoming tab got a fresh
  // State every time — losing scroll position, search text, and loaded data
  // on every tab switch.
  //
  // Building all 5 eagerly in initState used to mean every tab's initState
  // (and its data fetch) fired the moment MainScreen mounted, even for the
  // 4 tabs the user wasn't looking at — flooding app startup/login with
  // concurrent requests and slowing down the one tab actually on screen.
  // Now a tab is only built the first time it's selected.
  late final List<Widget?> _pages;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialIndex.clamp(0, 4);
    _pages = List<Widget?>.filled(5, null);
    _pages[selectedIndex] = _buildPage(selectedIndex);
    MainScreen._activeState = this;
  }

  @override
  void dispose() {
    if (identical(MainScreen._activeState, this)) {
      MainScreen._activeState = null;
    }
    super.dispose();
  }

  Widget _buildPage(int index) {
    switch (index) {
      case 0:
        return const HomeScreen();
      case 1:
        return AppointmentsScreen(activityId: widget.appointmentId);
      case 2:
        return const AppointmentBookingPage(); // Book Button
      // Records has no footer tab (app_footer.dart's Records/Account
      // _NavItems are commented out) — reachable via AccountScreen's "My
      // Records" tile or a notification deep link instead. Kept at index 3
      // here regardless of that; safe because no caller passes
      // initialIndex above 2.
      case 3:
        return const MyRecordsPage();
      case 4:
      default:
        return const AccountScreen();
    }
  }

  void _selectTab(int index) {
    setState(() {
      selectedIndex = index;
      _pages[index] ??= _buildPage(index);
    });
  }

  // MainScreen is always the bottom-most route (reached via
  // pushReplacement/pushAndRemoveUntil, see auth_gate_screen.dart and
  // login_screen.dart), so there is nothing left on the Navigator stack for
  // the system back button to pop to — without this it just exits the app.
  // Tab switches don't push routes either (see _selectTab), so "back" from
  // any non-Home tab instead means "return to Home", matching the rest of
  // the app's back-navigation behaviour.
  Future<void> _handleBackPress() async {
    if (selectedIndex != 0) {
      _selectTab(0);
      return;
    }
    await _confirmExit(context);
  }

  Future<void> _confirmExit(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        title: Text(
          'Exit app',
          style: AppType.body(size: 17, weight: FontWeight.w800)
              .copyWith(color: AppColors.textPrimary),
        ),
        content: Text(
          'Are you sure you want to exit the app?',
          style: AppType.body(size: 14).copyWith(color: AppColors.textSecondary),
        ),
        actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppType.body(size: 14)
                  .copyWith(color: AppColors.textSecondary),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Exit'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      SystemNavigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: IndexedStack(
          index: selectedIndex,
          children: [
            for (var i = 0; i < _pages.length; i++)
              _pages[i] ?? const SizedBox.shrink(),
          ],
        ),
        // AppFooter's nav items now report indices directly in this same
        // page-index space (see app_footer.dart), so no translation is
        // needed here anymore — the previous switch mapped footer index 3
        // ("Appointments") to page index 1, but AppFooter itself still
        // compared its own selectedIndex against index 3 for highlighting,
        // so the Appointments tab never showed as selected.
        bottomNavigationBar: AppFooter(
          selectedIndex: selectedIndex,
          onTap: _selectTab,
        ),
      ),
    );
  }
}

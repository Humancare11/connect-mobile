import 'package:flutter/material.dart';

import '../services/idle_session_timer.dart';
import '../services/token_storage_service.dart';
import 'login_screen.dart';
import 'main_screen.dart';

/// Decides where a cold app launch lands.
///
/// Previously `MyApp.home` pointed straight at LoginScreen, so every launch
/// forced a fresh login even for a user with a valid, securely-stored
/// session — despite that same stored token already being reused
/// automatically for every API call (see ApiClient). TokenStorageService's
/// own `isAuthenticated()` was only ever consulted by NotificationService's
/// deep-link routing, never at startup. This screen closes that gap: it's a
/// brief, stateless check (no network call, just secure-storage reads) that
/// routes to MainScreen if a session is already stored, LoginScreen if not.
class AuthGateScreen extends StatefulWidget {
  const AuthGateScreen({super.key});

  @override
  State<AuthGateScreen> createState() => _AuthGateScreenState();
}

class _AuthGateScreenState extends State<AuthGateScreen> {
  static const _tokenStorage = TokenStorageService();

  @override
  void initState() {
    super.initState();
    _routeFromStoredSession();
  }

  Future<void> _routeFromStoredSession() async {
    // This is the very first screen every user sees, so a failure here must
    // never leave them stuck on the spinner — fall back to LoginScreen (the
    // safe default: worst case they log in again) rather than letting an
    // unhandled exception from a secure-storage read (rare, but possible —
    // e.g. a corrupted Android keystore) hang the app on launch forever.
    var authenticated = false;
    try {
      authenticated = await _tokenStorage.isAuthenticated();
    } catch (_) {
      authenticated = false;
    }
    if (!mounted) return;

    // A stored session found at cold start means the 30-minute inactivity
    // countdown needs to (re)start here too — AuthService.saveSession only
    // covers a *fresh* login, not resuming an existing one.
    if (authenticated) IdleSessionTimer.instance.start();

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) =>
            authenticated ? const MainScreen() : const LoginScreen(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Shown only for the brief moment it takes to read secure storage.
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

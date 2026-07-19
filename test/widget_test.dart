import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:humancare_connect/screens/account_screen.dart';
import 'package:humancare_connect/screens/forgot_password_screen.dart';
import 'package:humancare_connect/screens/login_screen.dart';
import 'package:humancare_connect/screens/register_screen.dart';
import 'package:humancare_connect/services/auth_repository.dart';

class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository() : super();

  bool clearSessionCalled = false;

  @override
  Future<void> clearSession() async {
    clearSessionCalled = true;
  }
}

void main() {
  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Pumping the full MyApp tree would route through AuthGateScreen and
    // MyApp.build's NotificationService.instance, which touches
    // FirebaseMessaging.instance — that requires Firebase.initializeApp(),
    // which only ever runs in the real main(). Testing LoginScreen directly
    // (same pattern this file already uses for AccountScreen/RegisterScreen)
    // avoids that app-bootstrap dependency entirely.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('Welcome Back'), findsOneWidget);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('logout clears auth session and navigates to login', (
    WidgetTester tester,
  ) async {
    final authRepository = _FakeAuthRepository();

    await tester.pumpWidget(
      MaterialApp(home: AccountScreen(authRepository: authRepository)),
    );

    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Log out'));
    await tester.pumpAndSettle();

    expect(authRepository.clearSessionCalled, isTrue);
    expect(find.text('Welcome Back'), findsOneWidget);
  });

  testWidgets('forgot password opens reset flow', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    await tester.tap(find.text('Forgot Password?'));
    await tester.pumpAndSettle();

    expect(find.byType(ForgotPasswordScreen), findsOneWidget);
  });

  testWidgets('register screen shows Google sign-up option', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

    expect(find.text('Continue with Google'), findsOneWidget);
  });
}

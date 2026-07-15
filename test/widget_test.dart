import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hello_app/main.dart';
import 'package:hello_app/screens/account_screen.dart';
import 'package:hello_app/screens/forgot_password_screen.dart';
import 'package:hello_app/screens/register_screen.dart';
import 'package:hello_app/services/auth_repository.dart';

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
    await tester.pumpWidget(const MyApp());

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
    await tester.pumpWidget(const MyApp());

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

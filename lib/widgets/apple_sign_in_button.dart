import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Apple's HIG-compliant "Continue with Apple" button. Callers only build it
/// when [AuthService.isAppleSignInSupported] (iOS) — it is never shown on
/// Android or web.
class AppleSignInButton extends StatelessWidget {
  const AppleSignInButton({
    super.key,
    required this.onPressed,
    this.loading = false,
    this.disabled = false,
  });

  final VoidCallback onPressed;
  final bool loading;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return Container(
        width: double.infinity,
        height: 54,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.black,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
        ),
      );
    }

    return Opacity(
      opacity: disabled ? 0.5 : 1,
      child: IgnorePointer(
        ignoring: disabled,
        child: SignInWithAppleButton(
          text: 'Continue with Apple',
          height: 54,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          style: SignInWithAppleButtonStyle.black,
          onPressed: onPressed,
        ),
      ),
    );
  }
}

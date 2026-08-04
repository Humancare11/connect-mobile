import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../screens/login_screen.dart';
import '../services/notification_service.dart';
import '../services/session_expired_service.dart';

/// Full-screen "Session Expired" page shown globally by
/// [SessionExpiredGate] whenever [SessionExpiredService] reports the current
/// session as dead. Purely presentational, mirroring `NoInternetScreen` —
/// the only action available is signing back in.
///
/// Deliberately has no "dismiss"/back affordance: the stored tokens are
/// already cleared by the time this shows (see `ApiClient._handleSessionExpired`),
/// so letting the user dismiss it back to a screen that still expects an
/// authenticated session would just surface confusing follow-up errors.
class SessionExpiredScreen extends StatelessWidget {
  const SessionExpiredScreen({super.key});

  void _goToLogin(BuildContext context) {
    // Reset before navigating: the navigator push below unmounts this
    // screen (and the gate stops showing it) regardless, but resetting
    // first guarantees a stray rebuild in between can't briefly re-show the
    // gate over the login screen.
    SessionExpiredService.instance.reset();

    // Navigator.of(context) doesn't work from here: SessionExpiredGate
    // renders this screen as a Stack *sibling* of its `child` (see
    // session_expired_gate.dart's build()), not as a descendant of it — the
    // app's actual Navigator lives inside that sibling branch, so walking
    // up from this context can never reach it. Use the same global key
    // SessionExpiredGate's own automatic-redirect path already relies on
    // for exactly this reason (see its _maybeAutoRedirect).
    final navigator = NotificationService.navigatorKey.currentState;
    navigator?.pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.background,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const _SessionExpiredIllustration(),
              const SizedBox(height: 32),
              Text(
                'Session Expired',
                textAlign: TextAlign.center,
                style: AppTextStyles.h1,
              ),
              const SizedBox(height: 12),
              Text(
                "For your security, you've been signed out. Please log in "
                'again to continue.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(height: 1.4),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () => _goToLogin(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: Text(
                    'Log In Again',
                    style: AppType.display(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SessionExpiredIllustration extends StatelessWidget {
  const _SessionExpiredIllustration();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      height: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 160,
            height: 160,
            decoration: BoxDecoration(
              color: AppColors.primaryLight,
              shape: BoxShape.circle,
            ),
          ),
          Container(
            width: 108,
            height: 108,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.10),
              shape: BoxShape.circle,
            ),
          ),
          Icon(
            Icons.lock_clock_rounded,
            size: 56,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

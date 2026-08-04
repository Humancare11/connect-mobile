import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../services/connectivity_service.dart';

/// Full-screen "No Internet Connection" page shown globally by
/// `ConnectivityGate` whenever the device has no network interface up.
/// Purely presentational — all connectivity detection lives in
/// [ConnectivityService].
class NoInternetScreen extends StatefulWidget {
  const NoInternetScreen({super.key});

  @override
  State<NoInternetScreen> createState() => _NoInternetScreenState();
}

class _NoInternetScreenState extends State<NoInternetScreen> {
  bool _checking = false;

  Future<void> _onRetry() async {
    if (_checking) return;
    setState(() => _checking = true);

    // A fixed minimum spinner time so the tap always visibly does
    // something, even when checkConnectivity() resolves near-instantly and
    // the device turns out to still be offline (no state change to react
    // to otherwise).
    await Future.wait([
      ConnectivityService.instance.retryNow(),
      Future.delayed(const Duration(milliseconds: 400)),
    ]);

    if (mounted) setState(() => _checking = false);
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
              const _NoInternetIllustration(),
              const SizedBox(height: 32),
              Text(
                'No Internet Connection',
                textAlign: TextAlign.center,
                style: AppTextStyles.h1,
              ),
              const SizedBox(height: 12),
              Text(
                "You're offline right now. Check your Wi-Fi or mobile "
                'data connection and try again.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(height: 1.4),
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: _checking ? null : _onRetry,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                    ),
                  ),
                  child: _checking
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text('Retry', style: AppType.display(color: Colors.white)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NoInternetIllustration extends StatelessWidget {
  const _NoInternetIllustration();

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
            Icons.wifi_off_rounded,
            size: 56,
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

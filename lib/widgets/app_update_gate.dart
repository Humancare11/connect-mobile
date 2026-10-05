import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_design_system.dart';
import '../services/app_update_service.dart';

/// Wraps the whole app (see `main.dart`'s `MaterialApp.builder`) so the
/// "Please update" screen can sit above every screen, driven by
/// [AppUpdateService]. Screens never need to know it exists.
class AppUpdateGate extends StatelessWidget {
  const AppUpdateGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppUpdateService.instance,
      builder: (context, _) {
        final service = AppUpdateService.instance;
        return Stack(
          children: [
            child,
            if (service.optional)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  child: _OptionalUpdateCard(storeUrl: service.storeUrl),
                ),
              ),
            if (service.forced)
              Positioned.fill(
                child: UpdateRequiredScreen(storeUrl: service.storeUrl),
              ),
          ],
        );
      },
    );
  }
}

Future<bool> _openStore(String url) async {
  if (url.isEmpty) return false;
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// Blocking "Please update" screen. Not dismissible: the user either updates
/// or leaves the app.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, required this.storeUrl});

  final String storeUrl;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      color: AppColors.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.system_update_alt,
                      size: 40,
                      color: AppColors.primary,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Please update the app',
                    textAlign: TextAlign.center,
                    style: AppType.display(size: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'This version of Humancare Connect is no longer supported. '
                    'Update to the latest version to continue.',
                    textAlign: TextAlign.center,
                    style: AppType.body(size: 14, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  if (storeUrl.isNotEmpty)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          final ok = await _openStore(storeUrl);
                          if (!ok && context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  "Couldn't open the store. Please update from the store directly.",
                                ),
                              ),
                            );
                          }
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Update now',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      'Open the App Store and update Humancare Connect.',
                      textAlign: TextAlign.center,
                      style: AppType.body(size: 14, weight: FontWeight.w700),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OptionalUpdateCard extends StatelessWidget {
  const _OptionalUpdateCard({required this.storeUrl});

  final String storeUrl;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 6,
      borderRadius: BorderRadius.circular(14),
      color: AppColors.primaryDeep,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 6, 6, 6),
        child: Row(
          children: [
            const Expanded(
              child: Text(
                'A new version of Humancare Connect is available.',
                style: TextStyle(color: Colors.white, fontSize: 13),
              ),
            ),
            if (storeUrl.isNotEmpty)
              TextButton(
                onPressed: () => _openStore(storeUrl),
                child: const Text(
                  'Update',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            IconButton(
              tooltip: 'Dismiss',
              onPressed: AppUpdateService.instance.dismissOptional,
              icon: const Icon(Icons.close, color: Colors.white70, size: 20),
            ),
          ],
        ),
      ),
    );
  }
}

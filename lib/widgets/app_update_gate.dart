import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_design_system.dart';
import '../services/app_update_service.dart';
import '../services/store_update_service.dart';

/// Wraps the whole app (see `main.dart`'s `MaterialApp.builder`) so the
/// "Please update" screen can sit above every screen, driven by
/// [AppUpdateService]. Screens never need to know it exists.
///
/// It also drives the store force-update ([StoreUpdateService]): it asks the
/// store once the first frame is up and again whenever the app returns from
/// background, and shows the Update / Cancel popup (or, on iOS after Cancel,
/// the full-screen "Update required" screen).
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({super.key, required this.child, this.storeUpdate});

  final Widget child;

  /// Overridable for tests; defaults to [StoreUpdateService.instance].
  final StoreUpdateService? storeUpdate;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  StoreUpdateService get _store =>
      widget.storeUpdate ?? StoreUpdateService.instance;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_store.check());
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_store.check());
  }

  @override
  Widget build(BuildContext context) {
    final store = _store;
    return ListenableBuilder(
      listenable: Listenable.merge([AppUpdateService.instance, store]),
      builder: (context, _) {
        final service = AppUpdateService.instance;
        return Stack(
          children: [
            widget.child,
            if (service.optional)
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: SafeArea(
                  child: _OptionalUpdateCard(storeUrl: service.storeUrl),
                ),
              ),
            // The backend-driven blocking screen wins over the store popup.
            if (!service.forced && store.prompt)
              Positioned.fill(child: _StoreUpdatePrompt(store: store)),
            if (!service.forced && store.blocked)
              Positioned.fill(
                child: UpdateRequiredScreen(
                  storeUrl: store.storeUrl,
                  title: 'Update required',
                  message:
                      'A new version is available. Please update to continue.',
                  onUpdate: store.update,
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

/// "A new version is available. Please update to continue." — modal, with
/// Update and Cancel. Drawn in the gate's own Stack (the gate sits above the
/// Navigator, so `showDialog` isn't available here).
class _StoreUpdatePrompt extends StatelessWidget {
  const _StoreUpdatePrompt({required this.store});

  final StoreUpdateService store;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Stack(
        children: [
          const ModalBarrier(dismissible: false, color: Colors.black54),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Material(
                borderRadius: BorderRadius.circular(18),
                color: Colors.white,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Update available',
                        style: AppType.display(size: 18),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'A new version is available. Please update to continue.',
                        style: AppType.body(size: 14, height: 1.5),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: store.cancel,
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: store.update,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                              elevation: 0,
                            ),
                            child: const Text('Update'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
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
  const UpdateRequiredScreen({
    super.key,
    required this.storeUrl,
    this.title = 'Please update the app',
    this.message =
        'This version of Humancare Connect is no longer supported. '
        'Update to the latest version to continue.',
    this.onUpdate,
  });

  final String storeUrl;
  final String title;
  final String message;

  /// Custom Update action (the store force-update runs the Play / App Store
  /// flow); when null the button just opens [storeUrl].
  final Future<void> Function()? onUpdate;

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
                    title,
                    textAlign: TextAlign.center,
                    style: AppType.display(size: 22),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: AppType.body(size: 14, height: 1.5),
                  ),
                  const SizedBox(height: 28),
                  if (storeUrl.isNotEmpty || onUpdate != null)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: () async {
                          if (onUpdate != null) return onUpdate!();
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

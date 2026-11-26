import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_design_system.dart';
import '../services/active_call_tracker.dart';
import '../services/app_update_service.dart';
import '../services/notification_service.dart';
import '../services/payment_in_progress_tracker.dart';

/// Swallows the Android back button while the update dialog is up.
///
/// Must be registered with `WidgetsBinding.instance.addObserver` before
/// `runApp`: observers are asked in the order they were added, and the
/// Navigator's would otherwise pop a screen (or close the app) first.
class UpdateBackBlocker with WidgetsBindingObserver {
  @override
  Future<bool> didPopRoute() async => AppUpdateService.instance.isBlocking;
}

/// Wraps the whole app (see `main.dart`'s `MaterialApp.builder`) so the
/// forced-update dialog can sit above every screen, driven by
/// [AppUpdateService]. Screens never need to know it exists.
///
/// The dialog is drawn in the gate's own Stack rather than pushed as a route,
/// so no navigation (notification taps, session expiry) can remove or cover
/// it. It stays hidden during a video consultation and an unfinished payment.
class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate({
    super.key,
    required this.child,
    this.navigatorKey,
    this.versionService,
    this.openStore,
  });

  final Widget child;

  /// The app's Navigator; defaults to [NotificationService.navigatorKey].
  final GlobalKey<NavigatorState>? navigatorKey;

  /// Replaced in tests; defaults to [AppVersionService.shared].
  final AppVersionService? versionService;

  /// Replaced in tests.
  final Future<bool> Function(String url)? openStore;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  late final Listenable _inputs = Listenable.merge([
    AppUpdateService.instance,
    ActiveCallTracker.instance.activeCount,
    PaymentInProgressTracker.instance.activeCount,
  ]);

  final _RouteLock _routeLock = _RouteLock();
  bool _visible = false;
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _inputs.addListener(_scheduleSync);
    _scheduleSync();
  }

  @override
  void dispose() {
    _inputs.removeListener(_scheduleSync);
    WidgetsBinding.instance.removeObserver(this);
    _routeLock.release();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final service = widget.versionService ?? AppVersionService.shared;
    unawaited(service.checkIfDue());
  }

  /// The trackers change while screens are being built and torn down, so the
  /// gate only ever updates after the current frame.
  void _scheduleSync() {
    if (_syncScheduled) return;
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (mounted) _sync();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _sync() {
    final blocking = AppUpdateService.instance.isBlocking;
    if (blocking) {
      _routeLock.lock(
        (widget.navigatorKey ?? NotificationService.navigatorKey).currentState,
      );
      if (!_visible) FocusManager.instance.primaryFocus?.unfocus();
    } else {
      _routeLock.release();
    }
    if (blocking != _visible) setState(() => _visible = blocking);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Always wrapped the same way, so showing the dialog never rebuilds
        // the app underneath from scratch.
        ExcludeSemantics(
          excluding: _visible,
          child: ExcludeFocus(
            excluding: _visible,
            child: AbsorbPointer(
              absorbing: _visible,
              // A screen replaced underneath the dialog (session expiry, for
              // instance) has to be locked too.
              child: NotificationListener<NavigationNotification>(
                onNotification: (_) {
                  if (_visible) _scheduleSync();
                  return false;
                },
                child: widget.child,
              ),
            ),
          ),
        ),
        if (_visible) ...[
          Positioned.fill(
            child: ModalBarrier(
              dismissible: false,
              color: AppColors.primaryDeep.withValues(alpha: 0.6),
            ),
          ),
          Positioned.fill(
            child: UpdateRequiredDialog(
              storeUrl: AppUpdateService.instance.storeUrl,
              openStore: widget.openStore ?? _openStore,
            ),
          ),
        ],
      ],
    );
  }
}

/// Marks the Navigator's top route as "cannot pop" while the dialog is up.
///
/// [UpdateBackBlocker] is not enough on its own: Android's predictive back
/// gesture is handled by the route's page transition, which only stands down
/// for a route that refuses to pop. This also tells Android that the app
/// handles back, including on the first screen.
class _RouteLock implements PopEntry<Object?> {
  ModalRoute<Object?>? _route;

  @override
  final ValueNotifier<bool> canPopNotifier = ValueNotifier<bool>(false);

  @override
  void onPopInvoked(bool didPop) {}

  @override
  void onPopInvokedWithResult(bool didPop, Object? result) {}

  void lock(NavigatorState? navigator) {
    if (navigator == null) return;
    Route<dynamic>? top;
    // Looks at the top route; returning true at once pops nothing.
    navigator.popUntil((route) {
      top = route;
      return true;
    });
    if (identical(top, _route)) return;
    release();
    final route = top;
    if (route is! ModalRoute<Object?>) return;
    _route = route;
    route.registerPopEntry(this);
  }

  void release() {
    final route = _route;
    _route = null;
    route?.unregisterPopEntry(this);
  }
}

Future<bool> _openStore(String url) async {
  try {
    return await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
  } catch (_) {
    return false;
  }
}

/// "New version available". Not dismissible: one button, to the store.
class UpdateRequiredDialog extends StatefulWidget {
  const UpdateRequiredDialog({
    super.key,
    required this.storeUrl,
    required this.openStore,
  });

  final String storeUrl;
  final Future<bool> Function(String url) openStore;

  @override
  State<UpdateRequiredDialog> createState() => _UpdateRequiredDialogState();
}

class _UpdateRequiredDialogState extends State<UpdateRequiredDialog> {
  bool _openFailed = false;

  Future<void> _update() async {
    final opened = await widget.openStore(widget.storeUrl);
    if (mounted) setState(() => _openFailed = !opened);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.s3x),
          child: Semantics(
            scopesRoute: true,
            explicitChildNodes: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(AppRadius.xl),
                  boxShadow: AppShadows.elevated,
                ),
                child: Material(
                  type: MaterialType.transparency,
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.xxl),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: AppColors.primaryLight,
                            borderRadius: BorderRadius.circular(AppRadius.lg),
                          ),
                          child: const Icon(
                            Icons.system_update_alt,
                            size: 32,
                            color: AppColors.primary,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        Text(
                          'New version available',
                          textAlign: TextAlign.center,
                          style: AppType.display(size: 19),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                        Text(
                          'Please update Humancare Connect to continue using the app.',
                          textAlign: TextAlign.center,
                          style: AppType.body(size: 14, height: 1.5),
                        ),
                        if (_openFailed) ...[
                          const SizedBox(height: AppSpacing.md),
                          Text(
                            "Couldn't open the store. Please update from the store directly.",
                            textAlign: TextAlign.center,
                            style: AppType.body(
                              size: 12.5,
                              color: AppColors.coralInk,
                              height: 1.4,
                            ),
                          ),
                        ],
                        const SizedBox(height: AppSpacing.xxl),
                        SizedBox(
                          width: double.infinity,
                          height: 52,
                          child: ElevatedButton(
                            onPressed: _update,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: AppColors.surface,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(
                                  AppRadius.md,
                                ),
                              ),
                            ),
                            child: Text(
                              'Update Now',
                              style: AppType.display(
                                size: 15,
                                color: AppColors.surface,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

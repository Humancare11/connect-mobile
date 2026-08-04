import 'package:flutter/material.dart';

import '../config/app_design_system.dart';
import '../services/loading_service.dart';

/// Wraps the whole app so a single global loading indicator can be shown
/// above every screen, driven by [LoadingService]. Mount once at the app
/// root (see `main.dart`'s `MaterialApp.builder`) — screens never need to
/// know this exists.
class LoadingOverlay extends StatelessWidget {
  const LoadingOverlay({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned.fill(
          child: ListenableBuilder(
            listenable: LoadingService.instance,
            builder: (context, _) {
              final isLoading = LoadingService.instance.isLoading;
              return IgnorePointer(
                // Only block touches while actually loading — never eats
                // input once loading ends, even mid fade-out.
                ignoring: !isLoading,
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOut,
                  switchOutCurve: Curves.easeIn,
                  // AnimatedSwitcher removes the old child from the tree
                  // once the fade completes, so the spinner's
                  // AnimationController isn't ticking in the background
                  // while hidden.
                  child: isLoading
                      ? const _LoadingScrim(key: ValueKey('loading-scrim'))
                      : const SizedBox.shrink(
                          key: ValueKey('loading-hidden'),
                        ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _LoadingScrim extends StatelessWidget {
  const _LoadingScrim({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.35),
      child: const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      ),
    );
  }
}

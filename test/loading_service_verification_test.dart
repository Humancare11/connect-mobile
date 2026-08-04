import 'package:flutter_test/flutter_test.dart';
import 'package:humancare_connect/services/loading_service.dart';

void main() {
  // Fresh singleton state between cases: LoadingService has no public
  // reset, so each test uses balanced show/hide pairs and asserts back to
  // a known baseline instead of resetting internal state directly.
  final loading = LoadingService.instance;

  test('two concurrent requests: overlay stays visible until BOTH finish', () async {
    final visibilityLog = <bool>[];
    loading.addListener(() => visibilityLog.add(loading.isLoading));

    loading.show(); // request A starts
    expect(loading.isLoading, isTrue);
    loading.show(); // request B starts while A still in flight
    expect(loading.isLoading, isTrue);

    loading.hide(); // request A finishes first
    // Must NOT flicker off: B is still in flight.
    expect(loading.isLoading, isTrue,
        reason: 'overlay must stay up while a second request is in flight');

    loading.hide(); // request B finishes
    // Counter now at 0, but min-visible-duration may defer the actual hide.
    await Future.delayed(const Duration(milliseconds: 400));
    expect(loading.isLoading, isFalse,
        reason: 'overlay must hide once both requests are done');

    // No spurious extra notifications beyond the true visibility edges.
    expect(visibilityLog.first, isTrue);
    expect(visibilityLog.last, isFalse);
  });

  test('counter never goes negative on unmatched hide() calls', () async {
    // Baseline: nothing in flight.
    expect(loading.isLoading, isFalse);

    loading.hide(); // stray/unmatched call
    loading.hide();
    expect(loading.isLoading, isFalse);

    // A subsequent real request must still show correctly afterwards --
    // proves the stray hide()s didn't corrupt internal counter state.
    loading.show();
    expect(loading.isLoading, isTrue);
    loading.hide();
    await Future.delayed(const Duration(milliseconds: 400));
    expect(loading.isLoading, isFalse);
  });

  test('rapid show/hide/show avoids flicker: new request cancels stale hide timer', () async {
    loading.show();
    expect(loading.isLoading, isTrue);

    loading.hide(); // counter -> 0, schedules a deferred hide (< min duration elapsed)
    // Immediately start a new request before the deferred hide timer fires.
    loading.show();
    expect(loading.isLoading, isTrue,
        reason: 'must still be visible: a new request started during the debounce window');

    // Wait past where the stale timer would have fired.
    await Future.delayed(const Duration(milliseconds: 300));
    expect(loading.isLoading, isTrue,
        reason: 'the stale timer from the first hide() must not have hidden the overlay '
            'out from under the second, still-running request');

    loading.hide();
    await Future.delayed(const Duration(milliseconds: 400));
    expect(loading.isLoading, isFalse);
  });

  test('fast request (well under min duration) still eventually hides exactly once', () async {
    var hideNotifications = 0;
    void listener() {
      if (!loading.isLoading) hideNotifications++;
    }

    loading.addListener(listener);
    loading.show();
    loading.hide(); // immediately -- simulates a very fast API response

    expect(loading.isLoading, isTrue,
        reason: 'must not flicker off instantly for a sub-debounce-duration request');

    await Future.delayed(const Duration(milliseconds: 400));
    expect(loading.isLoading, isFalse);
    expect(hideNotifications, 1, reason: 'exactly one hide transition, no duplicate timers firing');

    loading.removeListener(listener);
  });
}

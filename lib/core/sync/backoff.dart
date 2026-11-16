/// Exponential backoff for failed uploads (SPEC.md §6).
final class Backoff {
  const Backoff({
    this.initial = const Duration(seconds: 5),
    this.maxDelay = const Duration(minutes: 2),
  });

  final Duration initial;

  /// Kept short so queued items go out soon after the device reconnects.
  final Duration maxDelay;

  /// Delay before the next attempt after [failedAttempts] failures (>= 1).
  Duration delayAfter(int failedAttempts) {
    var delay = initial;
    for (var i = 1; i < failedAttempts && delay < maxDelay; i++) {
      delay *= 2;
    }
    return delay < maxDelay ? delay : maxDelay;
  }
}

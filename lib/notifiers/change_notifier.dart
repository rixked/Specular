/// Tells the app that remote data may have changed and it should sync
/// (SPEC.md §7, extension point 3).
///
/// v0.1 polls ([PollingNotifier] in `polling_notifier.dart`); a
/// `notify_push` implementation can be added later without touching the
/// sync engine.
///
/// Note: Flutter's `foundation.dart` also exports a `ChangeNotifier`. Files
/// that need both should import one of them with a prefix or `hide`.
abstract interface class ChangeNotifier {
  /// Emits whenever a sync should run.
  Stream<void> get changes;

  /// Starts emitting. Calling it again while running has no effect.
  void start();

  /// Stops emitting until [start] is called again.
  void stop();

  /// Requests a sync right away, for example on window focus or app resume.
  void nudge();

  /// Stops and releases resources. The notifier can't be restarted.
  Future<void> dispose();
}

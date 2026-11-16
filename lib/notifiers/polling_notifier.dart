import 'dart:async';

import 'change_notifier.dart';

/// Emits a change signal at a fixed interval (SPEC.md §6).
///
/// Desktop uses ~15 s while running. On Android the app nudges on
/// open/resume and relies on a `workmanager` task while closed.
final class PollingNotifier implements ChangeNotifier {
  PollingNotifier({this.interval = const Duration(seconds: 15)});

  final Duration interval;
  final _controller = StreamController<void>.broadcast();
  Timer? _timer;

  bool get isRunning => _timer != null;

  @override
  Stream<void> get changes => _controller.stream;

  @override
  void start() {
    if (_timer != null || _controller.isClosed) return;
    _timer = Timer.periodic(interval, (_) => _emit());
  }

  @override
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  /// Emits immediately and restarts the interval, so a focus-triggered sync
  /// isn't followed by a redundant timer tick right after.
  @override
  void nudge() {
    _emit();
    if (_timer != null) {
      stop();
      start();
    }
  }

  @override
  Future<void> dispose() async {
    stop();
    await _controller.close();
  }

  void _emit() {
    if (!_controller.isClosed) _controller.add(null);
  }
}

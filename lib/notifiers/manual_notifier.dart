import 'dart:async';

import 'change_notifier.dart';

/// A [ChangeNotifier] without a timer: it only emits on [nudge].
///
/// Used on Android, where the app syncs when it opens or resumes and a
/// `workmanager` task covers the time it is closed (SPEC.md §6).
final class ManualNotifier implements ChangeNotifier {
  final _controller = StreamController<void>.broadcast();
  bool _running = false;

  @override
  Stream<void> get changes => _controller.stream;

  @override
  void start() => _running = true;

  @override
  void stop() => _running = false;

  /// Emits only while started.
  @override
  void nudge() {
    if (_running && !_controller.isClosed) _controller.add(null);
  }

  @override
  Future<void> dispose() async {
    _running = false;
    await _controller.close();
  }
}

import 'dart:async';

import '../backends/storage_backend.dart';
import '../core/sync/sync_engine.dart';
import '../notifiers/change_notifier.dart';

/// What the UI shows about syncing.
enum SyncPhase {
  /// Not started yet.
  stopped,

  /// A sync is running.
  syncing,

  /// The last sync succeeded.
  idle,

  /// The server couldn't be reached. Polling continues; queued items wait.
  offline,

  /// The app password was rejected. Polling stops until the user logs in
  /// again.
  unauthorized,

  /// The last sync failed for another reason. Polling continues.
  error,
}

final class SyncState {
  const SyncState({required this.phase, this.lastSuccess, this.message});

  static const initial = SyncState(phase: SyncPhase.stopped);

  final SyncPhase phase;

  /// When a sync last completed successfully (device clock).
  final DateTime? lastSuccess;

  /// Human-readable detail for [SyncPhase.error]. Never contains
  /// credentials (storage exceptions don't carry any).
  final String? message;

  SyncState _copy(SyncPhase phase, {DateTime? lastSuccess, String? message}) =>
      SyncState(
        phase: phase,
        lastSuccess: lastSuccess ?? this.lastSuccess,
        message: message,
      );
}

/// Runs the [SyncEngine] whenever the [ChangeNotifier] says so
/// (SPEC.md §6):
///
/// - Desktop: a `PollingNotifier` every ~15 s, plus [onAppResumed] when the
///   window gets focus.
/// - Android: a `ManualNotifier`, so only [onAppResumed] (app open/resume).
final class SyncCoordinator {
  SyncCoordinator({
    required this.engine,
    required this.trigger,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final SyncEngine engine;
  final ChangeNotifier trigger;
  final DateTime Function() _clock;

  final _states = StreamController<SyncState>.broadcast();
  StreamSubscription<void>? _subscription;
  SyncState _state = SyncState.initial;
  bool _disposed = false;

  SyncState get state => _state;

  /// Emits on every state change.
  Stream<SyncState> get states => _states.stream;

  /// Starts listening to the trigger and syncs once right away.
  Future<void> start() {
    _subscription ??= trigger.changes.listen((_) => unawaited(syncNow()));
    trigger.start();
    return syncNow();
  }

  /// Call when the app opens, resumes or the window gets focus.
  void onAppResumed() {
    if (_state.phase != SyncPhase.unauthorized) trigger.nudge();
  }

  /// Syncs now. Never throws; the outcome is reported through [states].
  Future<void> syncNow({bool force = false}) async {
    if (_disposed || _state.phase == SyncPhase.unauthorized) return;
    _emit(_state._copy(SyncPhase.syncing));
    try {
      final result = await engine.sync(force: force);
      if (_disposed) return;
      _emit(
        result.offline
            ? _state._copy(SyncPhase.offline)
            : _state._copy(SyncPhase.idle, lastSuccess: _clock()),
      );
    } on StorageUnauthorizedException catch (e) {
      trigger.stop();
      _emit(_state._copy(SyncPhase.unauthorized, message: e.message));
    } on StorageException catch (e) {
      _emit(_state._copy(SyncPhase.error, message: e.message));
    } on Object {
      _emit(_state._copy(SyncPhase.error, message: 'Sync failed'));
    }
  }

  Future<void> dispose() async {
    _disposed = true;
    trigger.stop();
    await _subscription?.cancel();
    await _states.close();
  }

  void _emit(SyncState state) {
    _state = state;
    if (!_states.isClosed) _states.add(state);
  }
}

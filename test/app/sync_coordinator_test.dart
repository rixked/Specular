import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/app/sync_coordinator.dart';
import 'package:specular/backends/storage_backend.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/sync_engine.dart';
import 'package:specular/notifiers/manual_notifier.dart';
import 'package:specular/notifiers/polling_notifier.dart';

import '../fakes/fake_storage_backend.dart';

void main() {
  late FakeStorageBackend backend;
  late SyncEngine engine;

  /// Creates fresh fakes. Must run inside `fakeAsync` in fake-time tests,
  /// so the engine's futures belong to the fake zone.
  void setUpFresh() {
    backend = FakeStorageBackend();
    engine = SyncEngine(
      backend: backend,
      store: InMemoryLocalStore(),
      deviceId: 'a1b2c3',
    );
  }

  test('syncs on start and reports idle with a timestamp', () async {
    setUpFresh();
    final now = DateTime.utc(2026, 11, 16, 12);
    final coordinator = SyncCoordinator(
      engine: engine,
      trigger: ManualNotifier(),
      clock: () => now,
    );
    final phases = <SyncPhase>[];
    coordinator.states.listen((s) => phases.add(s.phase));

    await coordinator.start();
    await pumpEventQueue();

    expect(phases, [SyncPhase.syncing, SyncPhase.idle]);
    expect(coordinator.state.lastSuccess, now);
    expect(backend.callCount('PROPFIND'), greaterThan(0));
    await coordinator.dispose();
  });

  test('desktop: polls every 15 s and syncs on window focus', () {
    fakeAsync((async) {
      setUpFresh();
      final coordinator = SyncCoordinator(
        engine: engine,
        trigger: PollingNotifier(),
      );
      coordinator.start();
      async.flushMicrotasks();
      final afterStart = backend.callCount('PROPFIND');

      async.elapse(const Duration(seconds: 31));
      final afterPolls = backend.callCount('PROPFIND');
      expect(afterPolls - afterStart, 2);

      coordinator.onAppResumed();
      async.flushMicrotasks();
      expect(backend.callCount('PROPFIND'), afterPolls + 1);

      coordinator.dispose();
      async.flushMicrotasks();
    });
  });

  test('android: no timer, only open/resume', () {
    fakeAsync((async) {
      setUpFresh();
      final coordinator = SyncCoordinator(
        engine: engine,
        trigger: ManualNotifier(),
      );
      coordinator.start();
      async.flushMicrotasks();
      final afterStart = backend.callCount('PROPFIND');

      async.elapse(const Duration(minutes: 5));
      expect(backend.callCount('PROPFIND'), afterStart);

      coordinator.onAppResumed();
      async.flushMicrotasks();
      expect(backend.callCount('PROPFIND'), afterStart + 1);

      coordinator.dispose();
      async.flushMicrotasks();
    });
  });

  test('offline is reported and polling continues', () {
    fakeAsync((async) {
      setUpFresh();
      backend.online = false;
      final coordinator = SyncCoordinator(
        engine: engine,
        trigger: PollingNotifier(),
      );
      coordinator.start();
      async.flushMicrotasks();
      expect(coordinator.state.phase, SyncPhase.offline);
      expect(coordinator.state.lastSuccess, isNull);

      backend.online = true;
      async.elapse(const Duration(seconds: 15));
      expect(coordinator.state.phase, SyncPhase.idle);

      coordinator.dispose();
      async.flushMicrotasks();
    });
  });

  test('a revoked app password stops polling until the next login', () {
    fakeAsync((async) {
      setUpFresh();
      backend.fault = (op, path, phase) =>
          const StorageUnauthorizedException('401');
      final trigger = PollingNotifier();
      final coordinator = SyncCoordinator(engine: engine, trigger: trigger);
      coordinator.start();
      async.flushMicrotasks();

      expect(coordinator.state.phase, SyncPhase.unauthorized);
      expect(trigger.isRunning, isFalse);

      final calls = backend.calls.length;
      async.elapse(const Duration(minutes: 1));
      coordinator.onAppResumed();
      async.flushMicrotasks();
      expect(backend.calls.length, calls);

      coordinator.dispose();
      async.flushMicrotasks();
    });
  });

  test('other errors are reported and the next tick retries', () {
    fakeAsync((async) {
      setUpFresh();
      var fail = true;
      backend.fault = (op, path, phase) =>
          fail ? const StorageProtocolException('HTTP 418') : null;
      final coordinator = SyncCoordinator(
        engine: engine,
        trigger: PollingNotifier(),
      );
      coordinator.start();
      async.flushMicrotasks();
      expect(coordinator.state.phase, SyncPhase.error);
      expect(coordinator.state.message, 'HTTP 418');

      fail = false;
      async.elapse(const Duration(seconds: 15));
      expect(coordinator.state.phase, SyncPhase.idle);
      expect(coordinator.state.message, isNull);

      coordinator.dispose();
      async.flushMicrotasks();
    });
  });

  test('ManualNotifier only emits while started', () async {
    final notifier = ManualNotifier();
    var ticks = 0;
    notifier.changes.listen((_) => ticks++);
    notifier.nudge();
    notifier.start();
    notifier.nudge();
    notifier.stop();
    notifier.nudge();
    await pumpEventQueue();
    expect(ticks, 1);
    await notifier.dispose();
  });
}

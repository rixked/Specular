import 'package:flutter_test/flutter_test.dart';
import 'package:specular/backends/storage_backend.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/remote_layout.dart';
import 'package:specular/core/sync/sync_engine.dart';
import 'package:specular/platform/background/background_sync.dart';

import '../fakes/fake_storage_backend.dart';

void main() {
  late FakeStorageBackend backend;
  late InMemoryLocalStore store;
  late SyncEngine engine;
  var now = DateTime.utc(2026, 11, 16, 12);

  setUp(() {
    backend = FakeStorageBackend();
    store = InMemoryLocalStore();
    now = DateTime.utc(2026, 11, 16, 12);
    engine = SyncEngine(
      backend: backend,
      store: store,
      deviceId: 'a1b2c3',
      clock: () => now,
    );
  });

  tearDown(() => engine.dispose());

  test('uploads items queued while offline', () async {
    backend.online = false;
    final item = await engine.send('shared on the train');
    backend.online = true;
    now = now.add(const Duration(minutes: 15));

    expect(await syncInBackground(engine), isTrue);

    expect(backend.exists(RemoteLayout.itemPath(item.id)), isTrue);
    expect((await store.items()).single.status, SyncStatus.synced);
  });

  test('fetches new items into the local cache', () async {
    final other = SyncEngine(
      backend: backend,
      store: InMemoryLocalStore(),
      deviceId: 'd4e5f6',
    );
    await other.send('from the desktop');

    await syncInBackground(engine);

    expect((await store.items()).single.item.content, 'from the desktop');
    await other.dispose();
  });

  test('never fails: offline, logged out or revoked password', () async {
    expect(await syncInBackground(null), isTrue);

    backend.online = false;
    expect(await syncInBackground(engine), isTrue);

    backend.online = true;
    backend.fault = (op, path, phase) =>
        const StorageUnauthorizedException('401');
    expect(await syncInBackground(engine), isTrue);
  });
}

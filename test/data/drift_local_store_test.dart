import 'dart:io';

import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/remote_layout.dart';
import 'package:specular/core/sync/sync_engine.dart';
import 'package:specular/data/local_db/drift_local_store.dart';
import 'package:specular/data/local_db/local_database.dart';

import '../core/sync/local_store_contract.dart';
import '../fakes/fake_storage_backend.dart';

void main() {
  // Each test opens its own in-memory database on purpose.
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;

  LocalDatabase? db;
  runLocalStoreContract(
    'DriftLocalStore',
    () async => DriftLocalStore(db = LocalDatabase(NativeDatabase.memory())),
    dispose: () async => db?.close(),
  );

  group('DriftLocalStore persistence', () {
    late Directory dir;

    setUp(() async => dir = await Directory.systemTemp.createTemp('specular'));
    tearDown(() async => dir.delete(recursive: true));

    LocalDatabase openDb() =>
        LocalDatabase(NativeDatabase(File('${dir.path}/specular.sqlite')));

    test('an item queued offline is uploaded after an app restart', () async {
      final backend = FakeStorageBackend()..online = false;
      var now = DateTime.utc(2026, 11, 16, 12);

      // First launch: send while offline, then "quit".
      final db1 = openDb();
      final engine1 = SyncEngine(
        backend: backend,
        store: DriftLocalStore(db1),
        deviceId: 'a1b2c3',
        clock: () => now,
      );
      final item = await engine1.send('sent on the train');
      await engine1.dispose();
      await db1.close();

      // Second launch: back online.
      backend.online = true;
      now = now.add(const Duration(minutes: 5));
      final db2 = openDb();
      final store2 = DriftLocalStore(db2);
      expect((await store2.items()).single.status, SyncStatus.pending);

      final engine2 = SyncEngine(
        backend: backend,
        store: store2,
        deviceId: 'a1b2c3',
        clock: () => now,
      );
      final result = await engine2.sync();

      expect(result.uploaded, 1);
      expect(backend.exists(RemoteLayout.itemPath(item.id)), isTrue);
      expect((await store2.items()).single.status, SyncStatus.synced);
      await engine2.dispose();
      await db2.close();
    });

    test('the inbox survives a restart, so the UI is instant', () async {
      final backend = FakeStorageBackend();
      final sender = SyncEngine(
        backend: backend,
        store: InMemoryLocalStore(),
        deviceId: 'a1b2c3',
      );
      await sender.send('https://example.com');

      final db1 = openDb();
      await SyncEngine(
        backend: backend,
        store: DriftLocalStore(db1),
        deviceId: 'd4e5f6',
      ).sync();
      await db1.close();

      backend.online = false;
      final db2 = openDb();
      final items = await DriftLocalStore(db2).items();
      expect(items.single.item.content, 'https://example.com');
      expect(items.single.serverModified, isNotNull);
      await db2.close();
    });
  });
}

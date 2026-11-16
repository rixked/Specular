import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:specular/backends/storage_backend.dart';
import 'package:specular/core/models/item.dart';
import 'package:specular/core/models/item_type.dart';
import 'package:specular/core/sync/backoff.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/remote_layout.dart';
import 'package:specular/core/sync/sync_engine.dart';

import '../../fakes/fake_storage_backend.dart';

/// A device under test: an engine with its own local store and clock.
class _Device {
  _Device(this.backend, this.id, {DateTime? now})
    : now = now ?? DateTime.utc(2026, 11, 16, 12) {
    engine = SyncEngine(
      backend: backend,
      store: store,
      deviceId: id,
      clock: () => this.now,
      backoff: const Backoff(
        initial: Duration(seconds: 5),
        maxDelay: Duration(minutes: 2),
      ),
    );
  }

  final FakeStorageBackend backend;
  final String id;
  final store = InMemoryLocalStore();
  late final SyncEngine engine;
  DateTime now;

  Future<List<LocalItem>> items() => store.items();
  Future<List<String>> contents() async => [
    for (final li in await store.items()) li.item.content,
  ];
}

String _itemJson(String id, {String type = 'text', String content = 'hi'}) =>
    jsonEncode({
      'schema': 1,
      'id': id,
      'type': type,
      'content': content,
      'title': null,
      'createdAt': '2026-11-16T10:00:00Z',
      'sourceDevice': 'ffffff',
      'attachment': null,
    });

void main() {
  late DateTime serverNow;
  late FakeStorageBackend backend;
  late _Device phone;
  late _Device pc;

  setUp(() {
    serverNow = DateTime.utc(2026, 11, 16, 12);
    backend = FakeStorageBackend(serverClock: () => serverNow);
    phone = _Device(backend, 'a1b2c3');
    pc = _Device(backend, 'd4e5f6');
  });

  tearDown(() async {
    await phone.engine.dispose();
    await pc.engine.dispose();
  });

  group('layout', () {
    test('creates /Specular/ and /Notes/ on first use', () async {
      expect(backend.dirExists('Specular'), isFalse);
      await pc.engine.sync();
      for (final dir in RemoteLayout.requiredDirectories) {
        expect(backend.dirExists(dir), isTrue, reason: dir);
      }
    });

    test('a first send also creates the layout', () async {
      await phone.engine.send('hello');
      expect(backend.filesIn(RemoteLayout.inbox), hasLength(1));
    });
  });

  group('send', () {
    test('uploads an immutable item file in the documented format', () async {
      final item = await phone.engine.send(
        ' https://www.tiktok.com/@user/video/123 ',
      );

      expect(item.type, ItemType.link);
      expect(item.content, 'https://www.tiktok.com/@user/video/123');
      expect(item.id, startsWith('20261116T120000Z-a1b2c3-'));

      final path = RemoteLayout.itemPath(item.id);
      expect(backend.exists(path), isTrue);
      final json = jsonDecode(backend.read(path)) as Map<String, Object?>;
      expect(json['schema'], 1);
      expect(json['type'], 'link');
      expect(json['createdAt'], '2026-11-16T12:00:00Z');
      expect(json['sourceDevice'], 'a1b2c3');

      final local = (await phone.items()).single;
      expect(local.status, SyncStatus.synced);
    });

    test('uploads each item exactly once', () async {
      await phone.engine.ensureLayout();
      await phone.engine.send('one');
      await phone.engine.sync();
      await phone.engine.sync();
      final puts = backend.calls.where(
        (c) => c.startsWith('PUT Specular/inbox'),
      );
      expect(puts, hasLength(1));
    });

    test('rejects blank input', () async {
      await expectLater(phone.engine.send('  \n '), throwsArgumentError);
      expect(await phone.items(), isEmpty);
    });
  });

  group('receive', () {
    test('items sent on one device appear on another', () async {
      final received = <List<Item>>[];
      pc.engine.received.listen(received.add);

      await phone.engine.send('https://example.com/video');
      await phone.engine.send('a note');
      final result = await pc.engine.sync();

      expect(
        result.received.map((i) => i.content),
        unorderedEquals(['https://example.com/video', 'a note']),
      );
      expect(await pc.contents(), hasLength(2));
      expect(
        (await pc.items()).every((li) => li.status == SyncStatus.synced),
        isTrue,
      );
      await pumpEventQueue();
      expect(received, hasLength(1));
    });

    test('shows newest first', () async {
      await phone.engine.send('old');
      phone.now = phone.now.add(const Duration(minutes: 1));
      await phone.engine.send('new');
      await pc.engine.sync();
      expect(await pc.contents(), ['new', 'old']);
    });

    test('skips the listing when the inbox ETag is unchanged', () async {
      await phone.engine.send('x');
      await pc.engine.sync();
      final getsBefore = backend.callCount('GET');

      final result = await pc.engine.sync();

      expect(result.listingProcessed, isFalse);
      expect(result.received, isEmpty);
      expect(backend.callCount('GET'), getsBefore);
    });

    test('items deleted elsewhere disappear', () async {
      final item = await phone.engine.send('bye');
      await pc.engine.sync();
      await phone.engine.delete(item.id);

      final result = await pc.engine.sync();

      expect(result.removed, 1);
      expect(await pc.items(), isEmpty);
      expect(backend.exists(RemoteLayout.itemPath(item.id)), isFalse);
    });

    test(
      'unreadable item files are skipped, not fatal, and not refetched',
      () async {
        await pc.engine.ensureLayout();
        backend.seedFile(
          RemoteLayout.itemPath('20261116T100000Z-ffffff-000001'),
          '{broken',
        );
        backend.seedFile(
          RemoteLayout.itemPath('20261116T100000Z-ffffff-000002'),
          _itemJson('20261116T100000Z-ffffff-000002', content: 'ok'),
        );

        final first = await pc.engine.sync();
        expect(first.unreadable, 1);
        expect(await pc.contents(), ['ok']);

        final gets = backend.callCount('GET');
        await phone.engine.send('trigger a new ETag');
        await pc.engine.sync();
        expect(backend.callCount('GET'), gets + 1);
      },
    );

    test('files whose name does not match their ID are skipped', () async {
      await pc.engine.ensureLayout();
      backend.seedFile(
        RemoteLayout.itemPath('20261116T100000Z-ffffff-000001'),
        _itemJson('20261116T100000Z-ffffff-999999'),
      );
      backend.seedFile('Specular/inbox/readme.txt', 'not an item');

      final result = await pc.engine.sync();
      expect(result.unreadable, 1);
      expect(await pc.items(), isEmpty);
    });

    test('unknown item types are received and kept, not dropped', () async {
      await pc.engine.ensureLayout();
      const id = '20261116T100000Z-ffffff-000003';
      backend.seedFile(
        RemoteLayout.itemPath(id),
        _itemJson(id, type: 'hologram', content: 'from the future'),
      );

      await pc.engine.sync();
      final local = (await pc.items()).single;
      expect(local.item.type, const ItemType('hologram'));

      final note = await pc.engine.keep(id);
      expect(note, 'from the future.md');
    });
  });

  group('offline queue (SPEC.md §6)', () {
    test(
      'sending offline queues the item and uploads it on reconnect',
      () async {
        backend.online = false;
        final item = await phone.engine.send('offline note');

        var local = (await phone.items()).single;
        expect(local.status, SyncStatus.pending);
        expect(local.uploadAttempts, 1);
        expect(local.lastError, isNotNull);

        final offlineResult = await phone.engine.sync();
        expect(offlineResult.offline, isTrue);

        backend.online = true;
        phone.now = phone.now.add(const Duration(seconds: 5));
        final result = await phone.engine.sync();

        expect(result.uploaded, 1);
        expect(backend.exists(RemoteLayout.itemPath(item.id)), isTrue);
        local = (await phone.items()).single;
        expect(local.status, SyncStatus.synced);
        expect(local.uploadAttempts, 0);
        expect(local.lastError, isNull);

        await pc.engine.sync();
        expect(await pc.contents(), ['offline note']);
      },
    );

    test('failed uploads back off exponentially', () async {
      backend.online = false;
      await phone.engine.send('x'); // attempt 1 -> next in 5 s

      final putsAfterSend = backend.callCount('PUT');
      phone.now = phone.now.add(const Duration(seconds: 4));
      await phone.engine.sync();
      expect(
        backend.callCount('PUT'),
        putsAfterSend,
        reason: 'still backing off',
      );

      phone.now = phone.now.add(const Duration(seconds: 1));
      await phone.engine.sync(); // attempt 2 -> next in 10 s
      expect(backend.callCount('PUT'), putsAfterSend + 1);
      final local = (await phone.items()).single;
      expect(local.uploadAttempts, 2);
      expect(local.nextAttemptAt, phone.now.add(const Duration(seconds: 10)));
    });

    test('a lost PUT response does not create a duplicate', () async {
      var failOnce = true;
      backend.fault = (op, path, phase) {
        if (op == 'PUT' && phase == 'after' && failOnce) {
          failOnce = false;
          return const StorageUnavailableException('connection reset');
        }
        return null;
      };

      final item = await phone.engine.send('once');
      expect((await phone.items()).single.status, SyncStatus.pending);

      phone.now = phone.now.add(const Duration(minutes: 1));
      final result = await phone.engine.sync();

      expect(result.offline, isFalse);
      expect(backend.filesIn(RemoteLayout.inbox), ['${item.id}.json']);
      expect((await phone.items()).single.status, SyncStatus.synced);
    });

    test(
      'a pending item can be deleted offline and is never uploaded',
      () async {
        backend.online = false;
        final item = await phone.engine.send('oops');
        await phone.engine.delete(item.id);
        expect(await phone.items(), isEmpty);

        backend.online = true;
        phone.now = phone.now.add(const Duration(minutes: 5));
        await phone.engine.sync();
        expect(backend.filesIn(RemoteLayout.inbox), isEmpty);
      },
    );

    test('deleting a synced item offline fails and keeps it', () async {
      final item = await phone.engine.send('keep me');
      backend.online = false;
      await expectLater(
        phone.engine.delete(item.id),
        throwsA(isA<StorageUnavailableException>()),
      );
      expect(await phone.items(), hasLength(1));
    });
  });

  group('expiry (SPEC.md §3.5)', () {
    test(
      'items older than 7 days by server time disappear everywhere',
      () async {
        final old = await phone.engine.send('old');
        await pc.engine.sync();
        serverNow = serverNow.add(const Duration(days: 2));
        final fresh = await phone.engine.send('fresh');
        await pc.engine.sync();

        serverNow = serverNow.add(const Duration(days: 5, seconds: 1));
        final result = await pc.engine.sync();

        expect(result.expired, 1);
        expect(backend.exists(RemoteLayout.itemPath(old.id)), isFalse);
        expect(backend.exists(RemoteLayout.itemPath(fresh.id)), isTrue);
        expect(await pc.contents(), ['fresh']);

        await phone.engine.sync();
        expect(await phone.contents(), ['fresh']);
      },
    );

    test('expiry runs even when the inbox ETag is unchanged', () async {
      await phone.engine.send('old');
      await pc.engine.sync();
      serverNow = serverNow.add(const Duration(days: 8));
      final result = await pc.engine.sync();
      expect(result.expired, 1);
      expect(await pc.items(), isEmpty);
    });

    test('uses the server clock, not the device clock', () async {
      phone.now = DateTime.utc(2027, 6, 1); // phone clock far ahead
      await phone.engine.send('recent on the server');
      pc.now = DateTime.utc(2030); // pc clock even further ahead

      final result = await pc.engine.sync();
      expect(result.expired, 0);
      expect(await pc.contents(), ['recent on the server']);
    });

    test(
      'an item already deleted by another device counts as expired',
      () async {
        await phone.engine.send('old');
        serverNow = serverNow.add(const Duration(days: 8));
        backend.fault = (op, path, phase) => op == 'DELETE' && phase == 'before'
            ? StorageNotFoundException(path)
            : null;

        final result = await pc.engine.sync();
        expect(result.expired, 1);
        expect(await pc.items(), isEmpty);
      },
    );

    test('kept items are not affected', () async {
      final item = await phone.engine.send('important');
      await phone.engine.keep(item.id);
      serverNow = serverNow.add(const Duration(days: 30));
      await phone.engine.sync();
      expect(backend.filesIn(RemoteLayout.notes), ['important.md']);
    });
  });

  group('keep (SPEC.md §3.4, §5.3)', () {
    test('writes a Markdown note and removes the item everywhere', () async {
      await phone.engine.announceDevice(name: 'Pixel', platform: 'android');
      final item = await phone.engine.send('https://www.tiktok.com/@u/video/1');
      await pc.engine.sync();

      final fileName = await pc.engine.keep(item.id);

      expect(fileName, 'tiktok.com 2026-11-16.md');
      expect(
        backend.read(RemoteLayout.notePath(fileName)),
        'https://www.tiktok.com/@u/video/1\n\nSent from Pixel · 2026-11-16\n',
      );
      expect(backend.exists(RemoteLayout.itemPath(item.id)), isFalse);
      expect(await pc.items(), isEmpty);

      await phone.engine.sync();
      expect(await phone.items(), isEmpty);
    });

    test('appends (2) on a name clash', () async {
      await pc.engine.ensureLayout();
      backend.seedFile(RemoteLayout.notePath('Groceries.md'), 'existing');
      final item = await pc.engine.send('Groceries\nmilk, eggs');

      final fileName = await pc.engine.keep(item.id);

      expect(fileName, 'Groceries (2).md');
      expect(backend.read(RemoteLayout.notePath('Groceries.md')), 'existing');
      expect(
        backend.read(RemoteLayout.notePath(fileName)),
        startsWith('Groceries\nmilk, eggs\n\nSent from'),
      );
    });

    test(
      'retries with the next name if another device takes it first',
      () async {
        final item = await pc.engine.send('Race');
        var injected = false;
        backend.fault = (op, path, phase) {
          if (op == 'PUT' &&
              path == RemoteLayout.notePath('Race.md') &&
              !injected) {
            injected = true;
            backend.seedFile(
              RemoteLayout.notePath('Race.md'),
              'from the other device',
            );
            return StorageAlreadyExistsException(path);
          }
          return null;
        };

        expect(await pc.engine.keep(item.id), 'Race (2).md');
      },
    );

    test('falls back to the device ID if the sender is unknown', () async {
      final item = await phone.engine.send('anon');
      await pc.engine.sync();
      await pc.engine.keep(item.id);
      expect(
        backend.read(RemoteLayout.notePath('anon.md')),
        contains('Sent from a1b2c3 · '),
      );
    });

    test('works for items that are still pending', () async {
      backend.fault = (op, path, phase) =>
          op == 'PUT' && path.startsWith(RemoteLayout.inbox)
          ? const StorageProtocolException('500')
          : null;
      final item = await phone.engine.send('not uploaded yet');
      expect((await phone.items()).single.status, SyncStatus.pending);

      await phone.engine.keep(item.id);

      backend.fault = null;
      phone.now = phone.now.add(const Duration(minutes: 5));
      await phone.engine.sync();
      expect(backend.filesIn(RemoteLayout.inbox), isEmpty);
      expect(backend.filesIn(RemoteLayout.notes), ['not uploaded yet.md']);
    });

    test('unknown IDs are rejected', () async {
      await expectLater(pc.engine.keep('nope'), throwsArgumentError);
    });

    test('notes go to their own Specular category in the Notes app', () async {
      await pc.engine.ensureLayout();
      backend.seedFile('Notes/My own note.md', 'not from Specular');
      final item = await pc.engine.send('Kept separately');

      await pc.engine.keep(item.id);

      expect(RemoteLayout.notes, 'Notes/Specular');
      expect(backend.filesIn('Notes/Specular'), ['Kept separately.md']);
      expect(backend.filesIn('Notes'), ['My own note.md']);
    });
  });

  group('Kept view (SPEC.md §3.4.1)', () {
    test('lists kept notes newest first, on every device', () async {
      final first = await phone.engine.send('First kept');
      await phone.engine.keep(first.id);
      serverNow = serverNow.add(const Duration(hours: 1));
      final second = await phone.engine.send('https://example.com/b');
      await phone.engine.keep(second.id);
      backend.seedFile(RemoteLayout.notePath('sub/ignored.md'), 'x');

      final notes = await pc.engine.keptNotes();

      expect(notes.map((n) => n.title), [
        'example.com 2026-11-16',
        'First kept',
      ]);
      expect(notes.first.lastModified, serverNow);
    });

    test('is empty before anything was kept', () async {
      expect(await pc.engine.keptNotes(), isEmpty);
    });

    test('reads a kept note in full', () async {
      final item = await phone.engine.send('Line one\nline two');
      final fileName = await phone.engine.keep(item.id);

      final text = await pc.engine.readKeptNote(fileName);

      expect(text, startsWith('Line one\nline two\n\nSent from '));
    });

    test('refuses paths outside the Kept folder', () async {
      await expectLater(
        pc.engine.readKeptNote('../Notes/My own note.md'),
        throwsArgumentError,
      );
    });
  });

  group('errors and concurrency', () {
    test('revoked credentials surface from sync', () async {
      backend.fault = (op, path, phase) =>
          const StorageUnauthorizedException('401');
      await expectLater(
        pc.engine.sync(),
        throwsA(isA<StorageUnauthorizedException>()),
      );
    });

    test('send still queues locally when credentials are revoked', () async {
      backend.fault = (op, path, phase) =>
          const StorageUnauthorizedException('401');
      await phone.engine.send('queued');
      expect((await phone.items()).single.status, SyncStatus.pending);
    });

    test('overlapping sync requests are coalesced', () async {
      await pc.engine.ensureLayout();
      final propfindsBefore = backend.callCount('PROPFIND');

      final a = pc.engine.sync();
      final b = pc.engine.sync();
      final c = pc.engine.sync(force: true);
      expect(identical(a, b), isTrue);
      expect(identical(a, c), isTrue);
      final result = await a;

      expect(result.listingProcessed, isTrue);
      expect(backend.callCount('PROPFIND'), propfindsBefore + 1);
    });

    test('operations run one at a time in call order', () async {
      final item = await phone.engine.send('x');
      await pc.engine.sync();
      final keep = pc.engine.keep(item.id);
      final sync = pc.engine.sync();
      await Future.wait([keep, sync]);
      expect(await pc.items(), isEmpty);
    });
  });
}

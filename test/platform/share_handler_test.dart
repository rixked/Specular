import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:specular/backends/storage_backend.dart';
import 'package:specular/core/models/item_type.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/remote_layout.dart';
import 'package:specular/core/sync/sync_engine.dart';
import 'package:specular/platform/share_intent/share_app.dart';
import 'package:specular/platform/share_intent/share_handler.dart';

import '../fakes/fake_storage_backend.dart';

void main() {
  late FakeStorageBackend backend;
  late InMemoryLocalStore store;
  late SyncEngine engine;

  setUp(() {
    backend = FakeStorageBackend();
    store = InMemoryLocalStore();
    engine = SyncEngine(backend: backend, store: store, deviceId: 'a1b2c3');
  });

  tearDown(() => engine.dispose());

  group('handleShare', () {
    test('a shared TikTok link becomes a link item', () async {
      final result = await handleShare(
        const SharePayload(text: 'https://vm.tiktok.com/ZMabc123/'),
        engine,
      );
      expect(result.outcome, ShareOutcome.sent);
      expect(result.item!.type, ItemType.link);
      expect(result.item!.content, 'https://vm.tiktok.com/ZMabc123/');
      expect(result.item!.title, isNull);
    });

    test('a browser share keeps the page title from EXTRA_SUBJECT', () async {
      final result = await handleShare(
        const SharePayload(
          text: 'https://example.com/article',
          subject: '  How light bends  ',
        ),
        engine,
      );
      expect(result.item!.type, ItemType.link);
      expect(result.item!.title, 'How light bends');
    });

    test('text with a link inside stays a text item', () async {
      final result = await handleShare(
        const SharePayload(
          text: 'Look at this! https://www.instagram.com/p/abc/',
          subject: 'ignored for text',
        ),
        engine,
      );
      expect(result.item!.type, ItemType.text);
      expect(result.item!.title, isNull);
    });

    test('falls back to the subject when there is no text', () async {
      final result = await handleShare(
        const SharePayload(subject: 'Only a subject'),
        engine,
      );
      expect(result.item!.content, 'Only a subject');
    });

    test('is stored locally before any upload', () async {
      backend.online = false;
      final result = await handleShare(
        const SharePayload(text: 'offline share'),
        engine,
      );
      expect(result.outcome, ShareOutcome.sent);
      expect((await store.items()).single.status, SyncStatus.pending);
      expect(backend.calls, isEmpty, reason: 'no network before confirming');
    });

    test('reports empty shares and missing login', () async {
      expect(
        (await handleShare(const SharePayload(text: '  '), engine)).outcome,
        ShareOutcome.nothingToSend,
      );
      expect(
        (await handleShare(const SharePayload(text: 'hi'), null)).outcome,
        ShareOutcome.notLoggedIn,
      );
    });
  });

  group('uploadShared', () {
    test('uploads the shared item', () async {
      final result = await handleShare(
        const SharePayload(text: 'https://youtu.be/abc'),
        engine,
      );
      await uploadShared(engine);
      expect(backend.exists(RemoteLayout.itemPath(result.item!.id)), isTrue);
      expect((await store.items()).single.status, SyncStatus.synced);
    });

    test('gives up after the timeout and leaves the item queued', () async {
      final hang = Completer<void>();
      final slow = _SlowBackend(backend, hang.future);
      final slowEngine = SyncEngine(
        backend: slow,
        store: store,
        deviceId: 'a1b2c3',
      );
      await handleShare(const SharePayload(text: 'slow'), slowEngine);

      await uploadShared(slowEngine, timeout: const Duration(milliseconds: 50));

      expect((await store.items()).single.status, SyncStatus.pending);

      // Once the network recovers, the queued item still goes out.
      hang.complete();
      await slowEngine.uploadPending();
      expect((await store.items()).single.status, SyncStatus.synced);
      await slowEngine.dispose();
    });

    test('never throws, even when offline', () async {
      backend.online = false;
      await handleShare(const SharePayload(text: 'x'), engine);
      await uploadShared(engine);
      expect((await store.items()).single.status, SyncStatus.pending);
    });
  });

  group('ShareConfirmation', () {
    testWidgets('shows "Sent ✦" after sending', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: ShareConfirmation(outcome: ShareOutcome.sent)),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sent ✦'), findsOneWidget);
    });

    testWidgets('tells the user to log in first', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: ShareConfirmation(outcome: ShareOutcome.notLoggedIn),
        ),
      );
      expect(find.text('Open Specular and log in first'), findsOneWidget);
    });
  });
}

/// Delegates to [inner] but lets PUT requests hang until [release].
final class _SlowBackend implements StorageBackend {
  _SlowBackend(this.inner, this.release);

  final FakeStorageBackend inner;
  final Future<void> release;

  @override
  Future<void> put(String path, Uint8List data, {bool overwrite = true}) async {
    await release;
    return inner.put(path, data, overwrite: overwrite);
  }

  @override
  Future<void> ensureDirectory(String path) => inner.ensureDirectory(path);
  @override
  Future<DirectoryListing> list(String path) => inner.list(path);
  @override
  Future<Uint8List> get(String path) => inner.get(path);
  @override
  Future<void> delete(String path) => inner.delete(path);
  @override
  Future<void> move(String from, String to, {bool overwrite = false}) =>
      inner.move(from, to, overwrite: overwrite);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:specular/core/models/item.dart';
import 'package:specular/core/models/item_type.dart';
import 'package:specular/core/sync/local_store.dart';

Item _item(String suffix, DateTime createdAt, {ItemType? type}) => Item(
  id: '20261116T120000Z-a1b2c3-$suffix',
  type: type ?? ItemType.text,
  content: 'content $suffix',
  createdAt: createdAt,
  sourceDevice: 'a1b2c3',
);

/// Behavior every [LocalStore] implementation must have.
void runLocalStoreContract(
  String name,
  Future<LocalStore> Function() create, {
  Future<void> Function()? dispose,
}) {
  group('$name (LocalStore contract)', () {
    late LocalStore store;
    final t0 = DateTime.utc(2026, 11, 16, 12);

    setUp(() async => store = await create());
    tearDown(() async => dispose?.call());

    test('starts empty', () async {
      expect(await store.items(), isEmpty);
      expect(await store.item('x'), isNull);
      expect(await store.inboxEtag(), isNull);
    });

    test('round-trips every field', () async {
      final next = DateTime.utc(2026, 11, 16, 12, 0, 5, 123);
      await store.put(
        LocalItem(
          item: _item('000001', t0),
          status: SyncStatus.pending,
          serverModified: DateTime.utc(2026, 11, 16, 12, 0, 1),
          uploadAttempts: 3,
          nextAttemptAt: next,
          lastError: 'offline',
        ),
      );

      final li = (await store.item('20261116T120000Z-a1b2c3-000001'))!;
      expect(li.item, _item('000001', t0));
      expect(li.status, SyncStatus.pending);
      expect(li.serverModified, DateTime.utc(2026, 11, 16, 12, 0, 1));
      expect(li.serverModified!.isUtc, isTrue);
      expect(li.uploadAttempts, 3);
      expect(li.nextAttemptAt!.isAtSameMomentAs(next), isTrue);
      expect(li.lastError, 'offline');
    });

    test('keeps unknown item types', () async {
      await store.put(
        LocalItem(
          item: _item('000001', t0, type: const ItemType('hologram')),
          status: SyncStatus.synced,
        ),
      );
      expect(
        (await store.items()).single.item.type,
        const ItemType('hologram'),
      );
    });

    test('lists newest first, ties broken by ID', () async {
      for (final (suffix, minutes) in [
        ('000001', 0),
        ('000003', 2),
        ('000002', 2),
        ('000004', 1),
      ]) {
        await store.put(
          LocalItem(
            item: _item(suffix, t0.add(Duration(minutes: minutes))),
            status: SyncStatus.synced,
          ),
        );
      }
      expect((await store.items()).map((li) => li.id.substring(24)), [
        '000003',
        '000002',
        '000004',
        '000001',
      ]);
    });

    test('put replaces, remove deletes, removing twice is fine', () async {
      final item = _item('000001', t0);
      await store.put(LocalItem(item: item, status: SyncStatus.pending));
      await store.put(LocalItem(item: item, status: SyncStatus.synced));
      expect((await store.items()).single.status, SyncStatus.synced);
      expect((await store.items()).single.nextAttemptAt, isNull);

      await store.remove(item.id);
      await store.remove(item.id);
      expect(await store.items(), isEmpty);
    });

    test('stores the inbox ETag', () async {
      await store.setInboxEtag('"abc"');
      expect(await store.inboxEtag(), '"abc"');
      await store.setInboxEtag('"def"');
      expect(await store.inboxEtag(), '"def"');
      await store.setInboxEtag(null);
      expect(await store.inboxEtag(), isNull);
    });

    test('watch emits the current state, then every change', () async {
      await store.put(
        LocalItem(item: _item('000001', t0), status: SyncStatus.synced),
      );

      final emissions = <List<String>>[];
      final sub = store.watch().listen(
        (items) => emissions.add([for (final i in items) i.id]),
      );
      await pumpEventQueue();
      expect(emissions, hasLength(1));
      expect(emissions.last, hasLength(1));

      await store.put(
        LocalItem(
          item: _item('000002', t0.add(const Duration(minutes: 1))),
          status: SyncStatus.pending,
        ),
      );
      await pumpEventQueue();
      expect(emissions.last, hasLength(2));

      await store.remove('20261116T120000Z-a1b2c3-000001');
      await pumpEventQueue();
      expect(emissions.last, ['20261116T120000Z-a1b2c3-000002']);

      await sub.cancel();
    });
  });
}

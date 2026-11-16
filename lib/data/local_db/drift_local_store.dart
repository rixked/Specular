import 'package:drift/drift.dart';

import '../../core/models/item.dart';
import '../../core/sync/local_store.dart';
import 'local_database.dart';

/// [LocalStore] backed by SQLite via drift (SPEC.md §6).
final class DriftLocalStore implements LocalStore {
  DriftLocalStore(this._db);

  static const _inboxEtagKey = 'inbox_etag';

  final LocalDatabase _db;

  Selectable<InboxRow> _allQuery() => _db.select(_db.inboxItems)
    ..orderBy([
      (t) => OrderingTerm.desc(t.createdAt),
      (t) => OrderingTerm.desc(t.id),
    ]);

  @override
  Future<List<LocalItem>> items() async =>
      _toLocalItems(await _allQuery().get());

  @override
  Future<LocalItem?> item(String id) async {
    final row = await (_db.select(
      _db.inboxItems,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _toLocalItem(row);
  }

  @override
  Future<void> put(LocalItem item) =>
      _db.into(_db.inboxItems).insertOnConflictUpdate(_toCompanion(item));

  @override
  Future<void> remove(String id) =>
      (_db.delete(_db.inboxItems)..where((t) => t.id.equals(id))).go();

  @override
  Future<String?> inboxEtag() async {
    final row = await (_db.select(
      _db.keyValues,
    )..where((t) => t.key.equals(_inboxEtagKey))).getSingleOrNull();
    return row?.value;
  }

  @override
  Future<void> setInboxEtag(String? etag) => _db
      .into(_db.keyValues)
      .insertOnConflictUpdate(
        KeyValuesCompanion.insert(key: _inboxEtagKey, value: Value(etag)),
      );

  @override
  Stream<List<LocalItem>> watch() => _allQuery().watch().map(_toLocalItems);

  /// Rows that can't be parsed (should never happen, since only this class
  /// writes them) are skipped instead of breaking the whole inbox.
  static List<LocalItem> _toLocalItems(List<InboxRow> rows) => [
    for (final row in rows) ?_tryToLocalItem(row),
  ];

  static LocalItem? _tryToLocalItem(InboxRow row) {
    try {
      return _toLocalItem(row);
    } on FormatException {
      return null;
    } on ArgumentError {
      return null; // Unknown status name.
    }
  }

  static LocalItem _toLocalItem(InboxRow row) => LocalItem(
    item: Item.decode(row.itemJson),
    status: SyncStatus.values.byName(row.status),
    serverModified: row.serverModified?.toUtc(),
    uploadAttempts: row.uploadAttempts,
    nextAttemptAt: row.nextAttemptAt,
    lastError: row.lastError,
  );

  static InboxItemsCompanion _toCompanion(LocalItem item) =>
      InboxItemsCompanion.insert(
        id: item.id,
        itemJson: item.item.encode(),
        createdAt: item.item.createdAt,
        status: item.status.name,
        serverModified: Value(item.serverModified),
        uploadAttempts: Value(item.uploadAttempts),
        nextAttemptAt: Value(item.nextAttemptAt),
        lastError: Value(item.lastError),
      );
}

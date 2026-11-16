import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'local_database.g.dart';

/// The local mirror of the inbox plus the outgoing queue (SPEC.md §6).
///
/// The item itself is stored as its wire JSON, so changes to the item
/// format don't need a database migration. Columns exist only for what the
/// app sorts or filters by.
@DataClassName('InboxRow')
@TableIndex(name: 'inbox_items_created_at', columns: {#createdAt, #id})
class InboxItems extends Table {
  TextColumn get id => text()();

  /// The item file's JSON (SPEC.md §5.2).
  TextColumn get itemJson => text()();

  /// Copy of the item's `createdAt`, for sorting.
  DateTimeColumn get createdAt => dateTime()();

  /// `pending` or `synced`.
  TextColumn get status => text()();

  DateTimeColumn get serverModified => dateTime().nullable()();
  IntColumn get uploadAttempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextAttemptAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Small settings, for example the last seen inbox ETag.
@DataClassName('KeyValueRow')
class KeyValues extends Table {
  TextColumn get key => text()();
  TextColumn get value => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}

@DriftDatabase(tables: [InboxItems, KeyValues])
class LocalDatabase extends _$LocalDatabase {
  LocalDatabase(super.executor);

  /// Opens the app's database file in the platform's app data directory.
  factory LocalDatabase.open() =>
      LocalDatabase(driftDatabase(name: 'specular'));

  @override
  int get schemaVersion => 1;
}

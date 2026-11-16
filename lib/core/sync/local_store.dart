import 'dart:async';

import '../models/item.dart';

/// Whether a local item has reached the server yet.
enum SyncStatus {
  /// Written locally, waiting to be uploaded (shown as "pending" in the UI).
  pending,

  /// Present on the server.
  synced,
}

/// An inbox item as mirrored on this device.
final class LocalItem {
  const LocalItem({
    required this.item,
    required this.status,
    this.serverModified,
    this.uploadAttempts = 0,
    this.nextAttemptAt,
    this.lastError,
  });

  final Item item;
  final SyncStatus status;

  /// The server's `getlastmodified` for the item file, once known.
  final DateTime? serverModified;

  /// Failed upload attempts so far.
  final int uploadAttempts;

  /// Earliest time of the next upload attempt (backoff), device clock.
  final DateTime? nextAttemptAt;

  /// Description of the last upload failure, for display. Never contains
  /// credentials.
  final String? lastError;

  String get id => item.id;

  LocalItem copyWith({
    SyncStatus? status,
    DateTime? serverModified,
    int? uploadAttempts,
    DateTime? Function()? nextAttemptAt,
    String? Function()? lastError,
  }) => LocalItem(
    item: item,
    status: status ?? this.status,
    serverModified: serverModified ?? this.serverModified,
    uploadAttempts: uploadAttempts ?? this.uploadAttempts,
    nextAttemptAt: nextAttemptAt != null ? nextAttemptAt() : this.nextAttemptAt,
    lastError: lastError != null ? lastError() : this.lastError,
  );
}

/// The local mirror of the inbox plus the outgoing queue (SPEC.md §6).
///
/// The production implementation lives in `lib/data/local_db/` (drift);
/// [InMemoryLocalStore] is used in tests and as a stand-in.
abstract interface class LocalStore {
  /// All items, newest first.
  Future<List<LocalItem>> items();

  Future<LocalItem?> item(String id);

  /// Inserts or replaces the item with the same ID.
  Future<void> put(LocalItem item);

  /// Removes the item. Succeeds if it doesn't exist.
  Future<void> remove(String id);

  /// The inbox folder ETag seen at the last processed listing.
  Future<String?> inboxEtag();

  Future<void> setInboxEtag(String? etag);

  /// Emits the full item list (newest first) on every change, starting with
  /// the current state.
  Stream<List<LocalItem>> watch();
}

/// Sorts newest first: by creation time, then by ID.
int compareNewestFirst(LocalItem a, LocalItem b) {
  final byTime = b.item.createdAt.compareTo(a.item.createdAt);
  return byTime != 0 ? byTime : b.id.compareTo(a.id);
}

final class InMemoryLocalStore implements LocalStore {
  final _items = <String, LocalItem>{};
  final _controller = StreamController<List<LocalItem>>.broadcast();
  String? _etag;

  List<LocalItem> _sorted() => _items.values.toList()..sort(compareNewestFirst);

  @override
  Future<List<LocalItem>> items() async => _sorted();

  @override
  Future<LocalItem?> item(String id) async => _items[id];

  @override
  Future<void> put(LocalItem item) async {
    _items[item.id] = item;
    _controller.add(_sorted());
  }

  @override
  Future<void> remove(String id) async {
    if (_items.remove(id) != null) _controller.add(_sorted());
  }

  @override
  Future<String?> inboxEtag() async => _etag;

  @override
  Future<void> setInboxEtag(String? etag) async => _etag = etag;

  @override
  Stream<List<LocalItem>> watch() async* {
    yield _sorted();
    yield* _controller.stream;
  }
}

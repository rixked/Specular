import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import '../../backends/storage_backend.dart';
import '../item_types/item_type_registry.dart';
import '../item_types/note_draft.dart';
import '../models/device.dart';
import '../models/item.dart';
import '../models/item_ids.dart';
import 'backoff.dart';
import 'local_store.dart';
import 'remote_layout.dart';

typedef Clock = DateTime Function();

/// What one [SyncEngine.sync] run did.
final class SyncResult {
  const SyncResult({
    this.uploaded = 0,
    this.received = const [],
    this.removed = 0,
    this.expired = 0,
    this.unreadable = 0,
    this.listingProcessed = false,
    this.offline = false,
  });

  /// Queued items that reached the server.
  final int uploaded;

  /// Items that are new on this device, newest first.
  final List<Item> received;

  /// Items deleted or kept on another device and removed here.
  final int removed;

  /// Items deleted because they were older than the expiry period.
  final int expired;

  /// Item files that could not be parsed and were skipped.
  final int unreadable;

  /// False if the inbox ETag was unchanged and the listing was skipped.
  final bool listingProcessed;

  /// True if the server could not be reached. Queued items stay queued.
  final bool offline;
}

/// The core sync loop (SPEC.md §6): outgoing queue, change detection,
/// diffing, expiry, Keep and Delete.
///
/// All operations are serialized, so a poll tick never races with a Keep or
/// Delete the user just triggered.
///
/// Errors: [StorageUnavailableException] is turned into an offline result by
/// [sync] and leaves items queued by [send]. [StorageUnauthorizedException]
/// is rethrown by [sync], [keep] and [delete] so the UI can ask the user to
/// log in again.
final class SyncEngine {
  SyncEngine({
    required this.backend,
    required this.store,
    required this.deviceId,
    ItemTypeRegistry? registry,
    Clock? clock,
    Random? random,
    this.expiry = const Duration(days: 7),
    this.backoff = const Backoff(),
  }) : registry = registry ?? ItemTypeRegistry.standard(),
       _clock = clock ?? DateTime.now,
       _random = random; // ignore: prefer_initializing_formals

  final StorageBackend backend;
  final LocalStore store;

  /// This device's ID; part of every item ID it creates.
  final String deviceId;
  final ItemTypeRegistry registry;

  /// Unkept items older than this (by server time) are deleted.
  final Duration expiry;
  final Backoff backoff;

  final Clock _clock;
  final Random? _random;

  final _received = StreamController<List<Item>>.broadcast();
  Future<void> _tail = Future.value();
  Future<SyncResult>? _queuedSync;
  bool _queuedForce = false;

  /// Unparsable item files by file name, with the ETag they had, so they
  /// aren't downloaded again on every sync.
  final _unreadable = <String, String?>{};
  final _deviceNames = <String, String>{};

  /// Emits the items found by each sync that received something, for
  /// notifications and the "glint" animation.
  Stream<List<Item>> get received => _received.stream;

  /// The local inbox, newest first, including pending items.
  Stream<List<LocalItem>> watchInbox() => store.watch();

  /// Creates an item from [input], queues it and tries to upload it.
  ///
  /// The item is stored locally before any network access, so it is never
  /// lost. If the upload fails it stays `pending` and is retried by [sync].
  /// [title] is an optional display title, for example a link's page title.
  /// Throws [ArgumentError] if [input] is blank.
  Future<Item> send(String input, {String? title}) async {
    final item = await enqueue(input, title: title);
    await uploadPending();
    return item;
  }

  /// Like [send], but only stores the item locally. Returns as soon as the
  /// item is safe, without touching the network. Use [uploadPending] or
  /// [sync] to upload it.
  Future<Item> enqueue(String input, {String? title}) => _serialized(() async {
    final content = input.trim();
    if (content.isEmpty) {
      throw ArgumentError.value(input, 'input', 'Nothing to send');
    }
    final trimmedTitle = title?.trim();
    final now = _clock().toUtc();
    final item = Item(
      id: ItemIds.generate(now: now, deviceId: deviceId, random: _random),
      type: registry.classify(content),
      content: content,
      title: (trimmedTitle == null || trimmedTitle.isEmpty)
          ? null
          : trimmedTitle,
      createdAt: now,
      sourceDevice: deviceId,
    );
    await store.put(LocalItem(item: item, status: SyncStatus.pending));
    return item;
  });

  /// Tries to upload queued items that are due, without fetching anything.
  /// Returns how many reached the server. Never throws for network or
  /// server problems; failed items stay queued.
  Future<int> uploadPending() => _serialized(() async {
    final uploaded = _Counter();
    try {
      await _flushOutgoing(uploaded);
    } on StorageException {
      // Stays queued; sync() reports persistent problems.
    }
    return uploaded.value;
  });

  /// Uploads queued items, then fetches remote changes and applies expiry.
  ///
  /// Calls made while a sync is already waiting to run share its result.
  /// With [force], the listing is processed even if the ETag is unchanged.
  Future<SyncResult> sync({bool force = false}) {
    _queuedForce |= force;
    final queued = _queuedSync;
    if (queued != null) return queued;
    final run = _serialized(() {
      _queuedSync = null;
      final runForce = _queuedForce;
      _queuedForce = false;
      return _syncOnce(force: runForce);
    });
    _queuedSync = run;
    return run;
  }

  /// Writes the item as a note to `/Notes/` and removes it from the inbox
  /// on all devices (SPEC.md §3.4). Returns the note's file name.
  ///
  /// If removing the inbox file fails after the note was written, the item
  /// stays in the inbox and a retry creates a second note (`… (2).md`).
  Future<String> keep(String id) => _serialized(() async {
    final local = await store.item(id);
    if (local == null) throw ArgumentError.value(id, 'id', 'Unknown item');
    final item = local.item;
    final context = NoteContext(
      deviceName: await _deviceName(item.sourceDevice),
    );
    final draft = registry.handlerFor(item.type).toNote(item, context);
    final fileName = await _putNote(draft);
    await _deleteRemoteItem(id);
    await store.remove(id);
    return fileName;
  });

  /// Removes the item from the inbox on all devices.
  ///
  /// A pending item can be deleted while offline; it is simply never
  /// uploaded.
  Future<void> delete(String id) => _serialized(() async {
    final local = await store.item(id);
    try {
      await _deleteRemoteItem(id);
    } on StorageUnavailableException {
      if (local?.status != SyncStatus.pending) rethrow;
    }
    await store.remove(id);
  });

  /// Publishes this device's name in `/Specular/devices/`, so other devices
  /// can show it in note footers.
  Future<void> announceDevice({
    required String name,
    required String platform,
  }) => _serialized(() async {
    _deviceNames[deviceId] = name;
    final device = Device(
      id: deviceId,
      name: name,
      platform: platform,
      lastSeen: _clock().toUtc(),
    );
    await _withLayout(
      () => backend.put(
        RemoteLayout.devicePath(deviceId),
        _utf8(device.encode()),
      ),
    );
  });

  /// Creates `/Specular/` and its subfolders, and `/Notes/Specular/`.
  /// Normally not needed: the engine does this on first use.
  Future<void> ensureLayout() => _serialized(_ensureLayout);

  /// Everything kept so far: the notes in `/Notes/Specular/`, newest first
  /// (SPEC.md §3.4.1). The folder itself is the source of truth, so the
  /// list is the same on every device.
  Future<List<KeptNote>> keptNotes() => _serialized(() async {
    final DirectoryListing listing;
    try {
      listing = await backend.list(RemoteLayout.notes);
    } on StorageNotFoundException {
      return const [];
    }
    final notes = [
      for (final entry in listing.entries)
        if (!entry.isDirectory && entry.name.endsWith(RemoteLayout.noteSuffix))
          KeptNote(fileName: entry.name, lastModified: entry.lastModified),
    ];
    notes.sort((a, b) {
      final byTime = (b.lastModified ?? DateTime(0)).compareTo(
        a.lastModified ?? DateTime(0),
      );
      return byTime != 0 ? byTime : a.fileName.compareTo(b.fileName);
    });
    return notes;
  });

  /// The Markdown text of a kept note.
  Future<String> readKeptNote(String fileName) => _serialized(() async {
    if (fileName.contains('/') || fileName.contains('\\')) {
      throw ArgumentError.value(fileName, 'fileName', 'Not a plain file name');
    }
    return utf8.decode(await backend.get(RemoteLayout.notePath(fileName)));
  });

  Future<void> dispose() => _received.close();

  // ---------------------------------------------------------------------------

  Future<T> _serialized<T>(Future<T> Function() operation) {
    final result = _tail.then((_) => operation());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  Future<SyncResult> _syncOnce({required bool force}) async {
    final uploads = _Counter();
    try {
      final reachable = await _flushOutgoing(uploads);
      if (!reachable) return SyncResult(uploaded: uploads.value, offline: true);
      return await _pull(force: force, uploaded: uploads.value);
    } on StorageUnavailableException {
      return SyncResult(uploaded: uploads.value, offline: true);
    }
  }

  /// Uploads due pending items, oldest first. Returns false if the server
  /// was unreachable.
  Future<bool> _flushOutgoing(_Counter uploaded) async {
    final now = _clock();
    final pending = (await store.items())
        .where((li) => li.status == SyncStatus.pending)
        .toList()
        .reversed;
    for (final local in pending) {
      final next = local.nextAttemptAt;
      if (next != null && next.isAfter(now)) continue;
      try {
        await _withLayout(
          () => backend.put(
            RemoteLayout.itemPath(local.id),
            _utf8(local.item.encode()),
            overwrite: false,
          ),
        );
      } on StorageAlreadyExistsException {
        // An earlier attempt reached the server but its response was lost.
        // Items are immutable, so the existing file is ours.
      } on StorageUnavailableException catch (e) {
        await _recordFailure(local, e, now);
        return false;
      } on StorageUnauthorizedException {
        rethrow;
      } on StorageException catch (e) {
        await _recordFailure(local, e, now);
        continue;
      }
      await store.put(
        local.copyWith(
          status: SyncStatus.synced,
          uploadAttempts: 0,
          nextAttemptAt: () => null,
          lastError: () => null,
        ),
      );
      uploaded.value++;
    }
    return true;
  }

  Future<void> _recordFailure(
    LocalItem local,
    StorageException error,
    DateTime now,
  ) {
    final attempts = local.uploadAttempts + 1;
    return store.put(
      local.copyWith(
        uploadAttempts: attempts,
        nextAttemptAt: () => now.add(backoff.delayAfter(attempts)),
        lastError: () => error.message,
      ),
    );
  }

  Future<SyncResult> _pull({required bool force, required int uploaded}) async {
    final listing = await _withLayout(() => backend.list(RemoteLayout.inbox));
    final serverNow = (listing.serverTime ?? _clock()).toUtc();

    final remote = <String, RemoteEntry>{};
    for (final entry in listing.entries) {
      final id = _itemIdOf(entry);
      if (id != null) remote[id] = entry;
    }

    // Expiry runs on every sync, even if nothing changed, because time
    // passes. It compares server times only (SPEC.md §3.5).
    var expired = 0;
    for (final MapEntry(key: id, value: entry) in remote.entries.toList()) {
      final modified = entry.lastModified;
      final isExpired =
          modified != null && serverNow.difference(modified) > expiry;
      if (!isExpired) continue;
      await _deleteRemoteItem(id);
      remote.remove(id);
      await store.remove(id);
      expired++;
    }

    final etag = listing.etag;
    if (!force && etag != null && etag == await store.inboxEtag()) {
      return SyncResult(uploaded: uploaded, expired: expired);
    }

    final local = {for (final li in await store.items()) li.id: li};
    final received = <Item>[];
    var unreadable = 0;

    for (final MapEntry(key: id, value: entry) in remote.entries) {
      final existing = local[id];
      if (existing != null) {
        if (existing.status == SyncStatus.pending ||
            existing.serverModified != entry.lastModified) {
          await store.put(
            existing.copyWith(
              status: SyncStatus.synced,
              serverModified: entry.lastModified,
              uploadAttempts: 0,
              nextAttemptAt: () => null,
              lastError: () => null,
            ),
          );
        }
        continue;
      }
      if (_unreadable.containsKey(entry.name) &&
          _unreadable[entry.name] == entry.etag) {
        unreadable++;
        continue;
      }
      final Item item;
      try {
        final bytes = await backend.get(RemoteLayout.itemPath(id));
        item = Item.decode(utf8.decode(bytes));
        if (item.id != id) {
          throw FormatException('Item ID does not match file name', item.id);
        }
      } on StorageNotFoundException {
        continue; // Deleted between listing and download.
      } on FormatException {
        _unreadable[entry.name] = entry.etag;
        unreadable++;
        continue;
      }
      await store.put(
        LocalItem(
          item: item,
          status: SyncStatus.synced,
          serverModified: entry.lastModified,
        ),
      );
      received.add(item);
    }

    var removed = 0;
    for (final li in local.values) {
      if (li.status == SyncStatus.synced && !remote.containsKey(li.id)) {
        await store.remove(li.id);
        removed++;
      }
    }

    await store.setInboxEtag(etag);
    received.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (received.isNotEmpty && !_received.isClosed) {
      _received.add(List.unmodifiable(received));
    }
    return SyncResult(
      uploaded: uploaded,
      received: List.unmodifiable(received),
      removed: removed,
      expired: expired,
      unreadable: unreadable,
      listingProcessed: true,
    );
  }

  /// The item ID for an inbox entry, or null if it isn't an item file.
  static String? _itemIdOf(RemoteEntry entry) {
    if (entry.isDirectory || !entry.name.endsWith(RemoteLayout.itemSuffix)) {
      return null;
    }
    final id = entry.name.substring(
      0,
      entry.name.length - RemoteLayout.itemSuffix.length,
    );
    return ItemIds.isValid(id) ? id : null;
  }

  /// Deletes an inbox file. Already deleted counts as success (SPEC.md §3.5).
  Future<void> _deleteRemoteItem(String id) async {
    try {
      await backend.delete(RemoteLayout.itemPath(id));
    } on StorageNotFoundException {
      // Deleted by another device already.
    }
  }

  /// Writes [draft] under a free file name, retrying if another device took
  /// the name concurrently.
  Future<String> _putNote(NoteDraft draft) async {
    final existing = <String>{};
    try {
      final listing = await backend.list(RemoteLayout.notes);
      existing.addAll(listing.entries.map((e) => e.name));
    } on StorageNotFoundException {
      await backend.ensureDirectory(RemoteLayout.notes);
    }
    final body = _utf8(draft.body);
    for (var attempt = 0; ; attempt++) {
      final fileName = noteFileName(draft.title, existing);
      try {
        await backend.put(
          RemoteLayout.notePath(fileName),
          body,
          overwrite: false,
        );
        return fileName;
      } on StorageAlreadyExistsException {
        if (attempt >= 20) rethrow;
        existing.add(fileName);
      }
    }
  }

  /// The display name of a device, falling back to its ID.
  Future<String> _deviceName(String id) async {
    final cached = _deviceNames[id];
    if (cached != null) return cached;
    try {
      final bytes = await backend.get(RemoteLayout.devicePath(id));
      final name = Device.decode(utf8.decode(bytes)).name;
      return _deviceNames[id] = name;
    } on StorageNotFoundException {
      return id;
    } on FormatException {
      return id;
    }
  }

  /// Runs [operation]; if a directory is missing, creates the layout and
  /// retries once. This is how `/Specular/` gets created on first use.
  Future<T> _withLayout<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on StorageNotFoundException {
      await _ensureLayout();
      return operation();
    }
  }

  Future<void> _ensureLayout() async {
    for (final dir in RemoteLayout.requiredDirectories) {
      await backend.ensureDirectory(dir);
    }
  }

  static Uint8List _utf8(String text) => utf8.encode(text);
}

/// A note in the Kept view.
final class KeptNote {
  const KeptNote({required this.fileName, this.lastModified});

  /// For example `How light bends.md`.
  final String fileName;

  /// When it was kept (server time).
  final DateTime? lastModified;

  /// The file name without `.md`, which is the note's title.
  String get title => fileName.endsWith(RemoteLayout.noteSuffix)
      ? fileName.substring(0, fileName.length - RemoteLayout.noteSuffix.length)
      : fileName;
}

final class _Counter {
  int value = 0;
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:specular/backends/storage_backend.dart';

/// Hook to inject a failure: return an exception to throw for this call, or
/// null to run it normally. [phase] is `before` or `after` (the operation
/// already took effect, for simulating a lost response).
typedef FaultInjector = StorageException? Function(
  String operation,
  String path,
  String phase,
);

/// An in-memory [StorageBackend] that behaves like Nextcloud WebDAV for the
/// parts Specular relies on.
final class FakeStorageBackend implements StorageBackend {
  FakeStorageBackend({DateTime Function()? serverClock})
    : serverClock = serverClock ?? (() => DateTime.utc(2026, 11, 16, 12));

  /// The server's clock, used for `lastModified` and `serverTime`.
  DateTime Function() serverClock;

  /// When false, every call throws [StorageUnavailableException].
  bool online = true;
  FaultInjector? fault;

  final _files = <String, _FakeFile>{};
  final _dirs = <String>{''};
  final _dirVersions = <String, int>{};
  int _etagCounter = 0;

  /// Every call as `OPERATION path`, in order.
  final calls = <String>[];

  // --- test helpers ----------------------------------------------------------

  void seedFile(String path, String content, {DateTime? lastModified}) {
    _mkdirs(_parentOf(path));
    _files[path] = _FakeFile(
      utf8.encode(content),
      lastModified ?? serverClock(),
      _nextEtag(),
    );
    _touch(_parentOf(path));
  }

  bool exists(String path) => _files.containsKey(path);
  bool dirExists(String path) => _dirs.contains(path);
  String read(String path) => utf8.decode(_files[path]!.data);

  /// File names directly inside [dir], sorted.
  List<String> filesIn(String dir) =>
      _files.keys.where((p) => _parentOf(p) == dir).map(_nameOf).toList()
        ..sort();

  int callCount(String operation) =>
      calls.where((c) => c.startsWith('$operation ')).length;

  // --- StorageBackend ---------------------------------------------------------

  @override
  Future<void> ensureDirectory(String path) async {
    _enter('MKCOL', path);
    _mkdirs(path);
  }

  @override
  Future<DirectoryListing> list(String path) async {
    _enter('PROPFIND', path);
    if (!_dirs.contains(path)) throw StorageNotFoundException(path);
    final entries = <RemoteEntry>[
      for (final MapEntry(key: p, value: f) in _files.entries)
        if (_parentOf(p) == path)
          RemoteEntry(
            name: _nameOf(p),
            isDirectory: false,
            etag: f.etag,
            lastModified: f.lastModified,
            size: f.data.length,
          ),
      for (final d in _dirs)
        if (d.isNotEmpty && _parentOf(d) == path)
          RemoteEntry(name: _nameOf(d), isDirectory: true),
    ];
    return DirectoryListing(
      etag: '"$path@${_dirVersions[path] ?? 0}"',
      entries: entries,
      serverTime: serverClock(),
    );
  }

  @override
  Future<Uint8List> get(String path) async {
    _enter('GET', path);
    final file = _files[path];
    if (file == null) throw StorageNotFoundException(path);
    return Uint8List.fromList(file.data);
  }

  @override
  Future<void> put(String path, Uint8List data, {bool overwrite = true}) async {
    _enter('PUT', path);
    if (!_dirs.contains(_parentOf(path))) {
      throw StorageNotFoundException('Parent of $path');
    }
    if (!overwrite && _files.containsKey(path)) {
      throw StorageAlreadyExistsException(path);
    }
    _files[path] = _FakeFile(
      Uint8List.fromList(data),
      serverClock(),
      _nextEtag(),
    );
    _touch(_parentOf(path));
    _exit('PUT', path);
  }

  @override
  Future<void> delete(String path) async {
    _enter('DELETE', path);
    if (_files.remove(path) == null) throw StorageNotFoundException(path);
    _touch(_parentOf(path));
    _exit('DELETE', path);
  }

  @override
  Future<void> move(String from, String to, {bool overwrite = false}) async {
    _enter('MOVE', from);
    final file = _files[from];
    if (file == null) throw StorageNotFoundException(from);
    if (!_dirs.contains(_parentOf(to))) throw StorageNotFoundException(to);
    if (!overwrite && _files.containsKey(to)) {
      throw StorageAlreadyExistsException(to);
    }
    _files.remove(from);
    _files[to] = file;
    _touch(_parentOf(from));
    _touch(_parentOf(to));
    _exit('MOVE', from);
  }

  // --- internals ------------------------------------------------------------

  void _enter(String operation, String path) {
    calls.add('$operation $path');
    if (!online) throw const StorageUnavailableException('offline');
    final error = fault?.call(operation, path, 'before');
    if (error != null) throw error;
  }

  void _exit(String operation, String path) {
    final error = fault?.call(operation, path, 'after');
    if (error != null) throw error;
  }

  void _mkdirs(String path) {
    if (path.isEmpty || _dirs.contains(path)) return;
    _mkdirs(_parentOf(path));
    _dirs.add(path);
    _touch(_parentOf(path));
  }

  void _touch(String dir) => _dirVersions[dir] = (_dirVersions[dir] ?? 0) + 1;

  String _nextEtag() => '"e${++_etagCounter}"';

  static String _parentOf(String path) {
    final i = path.lastIndexOf('/');
    return i < 0 ? '' : path.substring(0, i);
  }

  static String _nameOf(String path) =>
      path.substring(path.lastIndexOf('/') + 1);
}

final class _FakeFile {
  _FakeFile(this.data, this.lastModified, this.etag);

  final Uint8List data;
  final DateTime lastModified;
  final String etag;
}

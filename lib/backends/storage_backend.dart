import 'dart:typed_data';

/// Remote file storage used by Specular (SPEC.md §7, extension point 2).
///
/// Paths are relative to the user's storage root and use `/` as separator,
/// for example `Specular/inbox/<id>.json`. For Nextcloud the root is
/// `{server}/remote.php/dav/files/{loginName}/`.
///
/// Implementations report failures with [StorageException] subtypes so the
/// sync engine can react without knowing about HTTP.
abstract interface class StorageBackend {
  /// Creates the directory at [path] and any missing parents. Succeeds if it
  /// already exists.
  Future<void> ensureDirectory(String path);

  /// Lists the direct children of the directory at [path].
  ///
  /// Throws [StorageNotFoundException] if the directory does not exist.
  Future<DirectoryListing> list(String path);

  /// Throws [StorageNotFoundException] if the file does not exist.
  Future<Uint8List> get(String path);

  /// Writes a file.
  ///
  /// With `overwrite: false`, throws [StorageAlreadyExistsException] if the
  /// file exists (WebDAV: `If-None-Match: *`). Throws
  /// [StorageNotFoundException] if the parent directory does not exist.
  Future<void> put(String path, Uint8List data, {bool overwrite = true});

  /// Throws [StorageNotFoundException] if the file does not exist.
  Future<void> delete(String path);

  /// Moves a file. Throws [StorageNotFoundException] if [from] does not
  /// exist and, with `overwrite: false`, [StorageAlreadyExistsException] if
  /// [to] exists.
  Future<void> move(String from, String to, {bool overwrite = false});
}

/// The result of listing a directory.
final class DirectoryListing {
  const DirectoryListing({
    required this.etag,
    required this.entries,
    this.serverTime,
  });

  /// The directory's own ETag. Changes whenever its contents change.
  final String? etag;
  final List<RemoteEntry> entries;

  /// The server's current time (HTTP `Date` header), if known. Used for
  /// expiry so that device clocks don't matter.
  final DateTime? serverTime;
}

/// One file or directory in a [DirectoryListing].
final class RemoteEntry {
  const RemoteEntry({
    required this.name,
    required this.isDirectory,
    this.etag,
    this.lastModified,
    this.size,
  });

  /// The file name without directory, for example `<id>.json`.
  final String name;
  final bool isDirectory;
  final String? etag;

  /// Server-side modification time (WebDAV `getlastmodified`), UTC.
  final DateTime? lastModified;
  final int? size;
}

sealed class StorageException implements Exception {
  const StorageException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// The file or directory does not exist (HTTP 404, or 409 on a missing
/// parent).
final class StorageNotFoundException extends StorageException {
  const StorageNotFoundException(super.message);
}

/// The target already exists (HTTP 412 with `If-None-Match: *`).
final class StorageAlreadyExistsException extends StorageException {
  const StorageAlreadyExistsException(super.message);
}

/// Credentials are missing, wrong or revoked (HTTP 401/403). The user has
/// to log in again.
final class StorageUnauthorizedException extends StorageException {
  const StorageUnauthorizedException(super.message);
}

/// The server can't be reached right now: offline, timeout, DNS, 5xx.
/// The operation may be retried later.
final class StorageUnavailableException extends StorageException {
  const StorageUnavailableException(super.message);
}

/// The server's TLS certificate is not trusted by the system and does not
/// match a pinned fingerprint (SPEC.md §8). The user may trust it
/// explicitly after comparing [fingerprint].
final class StorageUntrustedCertificateException extends StorageException {
  const StorageUntrustedCertificateException(this.host, this.fingerprint)
    : super('Untrusted certificate for $host');

  final String host;

  /// SHA-256 of the certificate, as `AB:CD:…`.
  final String fingerprint;
}

/// Any other unexpected response.
final class StorageProtocolException extends StorageException {
  const StorageProtocolException(super.message);
}

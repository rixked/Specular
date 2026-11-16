import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'nextcloud_credentials.dart';

/// Where the app password is kept between launches.
abstract interface class CredentialStore {
  Future<NextcloudCredentials?> read();
  Future<void> write(NextcloudCredentials credentials);

  /// Forgets the credentials, for example on logout or after a 401.
  Future<void> clear();
}

/// Stores credentials in OS secure storage only: libsecret on Linux,
/// Credential Manager on Windows, Keystore on Android (SPEC.md §8).
/// Never in plain files.
final class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'nextcloud_credentials';

  final FlutterSecureStorage _storage;

  @override
  Future<NextcloudCredentials?> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return NextcloudCredentials.fromJson(decoded);
      }
    } on Exception {
      // Corrupt or from an incompatible version: treat as logged out.
    }
    await clear();
    return null;
  }

  @override
  Future<void> write(NextcloudCredentials credentials) =>
      _storage.write(key: _key, value: jsonEncode(credentials.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: _key);
}

/// In-memory [CredentialStore] for tests.
final class InMemoryCredentialStore implements CredentialStore {
  NextcloudCredentials? _value;

  @override
  Future<NextcloudCredentials?> read() async => _value;

  @override
  Future<void> write(NextcloudCredentials credentials) async =>
      _value = credentials;

  @override
  Future<void> clear() async => _value = null;
}

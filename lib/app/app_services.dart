import '../backends/nextcloud/credential_store.dart';
import '../backends/nextcloud/nextcloud_credentials.dart';
import '../backends/nextcloud/webdav_backend.dart';
import '../backends/storage_backend.dart';
import '../core/sync/sync_engine.dart';
import '../data/local_db/drift_local_store.dart';
import '../data/local_db/local_database.dart';
import '../data/local_db/local_settings.dart';

/// Wires the building blocks together: local database, credentials,
/// Nextcloud backend and sync engine.
///
/// Used by the main app and by the Android share target, which runs in its
/// own Flutter engine.
final class AppServices {
  AppServices._({
    required this.database,
    required this.settings,
    required this.credentialStore,
    required this.deviceId,
  });

  /// Opens the database and, if the user is logged in, the sync engine.
  static Future<AppServices> open({CredentialStore? credentialStore}) async {
    final database = LocalDatabase.open();
    final settings = LocalSettings(database);
    final services = AppServices._(
      database: database,
      settings: settings,
      credentialStore: credentialStore ?? SecureCredentialStore(),
      deviceId: await settings.deviceId(),
    );
    final credentials = await services.credentialStore.read();
    if (credentials != null) services._attach(credentials);
    return services;
  }

  final LocalDatabase database;
  final LocalSettings settings;
  final CredentialStore credentialStore;
  final String deviceId;

  NextcloudCredentials? _credentials;
  NextcloudWebDavBackend? _backend;
  SyncEngine? _engine;

  NextcloudCredentials? get credentials => _credentials;

  /// Null until the user has logged in.
  SyncEngine? get engine => _engine;

  bool get isLoggedIn => _engine != null;

  /// Stores [credentials] in secure storage, starts the sync engine and
  /// publishes this device's name (SPEC.md §3.1).
  Future<void> signIn(
    NextcloudCredentials credentials, {
    required String deviceName,
    required String platform,
  }) async {
    await _detach();
    await credentialStore.write(credentials);
    await settings.setDeviceName(deviceName);
    _attach(credentials);
    try {
      await _engine!.announceDevice(name: deviceName, platform: platform);
    } on StorageException {
      // Not critical: other devices fall back to the device ID.
    }
  }

  /// Forgets the credentials. The local inbox stays, so queued items are
  /// not lost.
  Future<void> signOut() async {
    await _detach();
    await credentialStore.clear();
  }

  Future<void> close() async {
    await _detach();
    await database.close();
  }

  void _attach(NextcloudCredentials credentials) {
    _credentials = credentials;
    _backend = NextcloudWebDavBackend(credentials: credentials);
    _engine = SyncEngine(
      backend: _backend!,
      store: DriftLocalStore(database),
      deviceId: deviceId,
    );
  }

  Future<void> _detach() async {
    await _engine?.dispose();
    _backend?.close();
    _engine = null;
    _backend = null;
    _credentials = null;
  }
}

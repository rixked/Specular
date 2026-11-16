import '../backends/nextcloud/credential_store.dart';
import '../backends/nextcloud/nextcloud_credentials.dart';
import '../backends/nextcloud/webdav_backend.dart';
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
    this.credentials,
    this.engine,
    this.backend,
  });

  /// Opens the database and, if the user is logged in, the sync engine.
  static Future<AppServices> open({CredentialStore? credentialStore}) async {
    final database = LocalDatabase.open();
    final settings = LocalSettings(database);
    final store = credentialStore ?? SecureCredentialStore();
    final deviceId = await settings.deviceId();
    final credentials = await store.read();

    NextcloudWebDavBackend? backend;
    SyncEngine? engine;
    if (credentials != null) {
      backend = NextcloudWebDavBackend(credentials: credentials);
      engine = SyncEngine(
        backend: backend,
        store: DriftLocalStore(database),
        deviceId: deviceId,
      );
    }
    return AppServices._(
      database: database,
      settings: settings,
      credentialStore: store,
      deviceId: deviceId,
      credentials: credentials,
      engine: engine,
      backend: backend,
    );
  }

  final LocalDatabase database;
  final LocalSettings settings;
  final CredentialStore credentialStore;
  final String deviceId;
  final NextcloudCredentials? credentials;

  /// Null until the user has logged in.
  final SyncEngine? engine;
  final NextcloudWebDavBackend? backend;

  bool get isLoggedIn => engine != null;

  Future<void> close() async {
    await engine?.dispose();
    backend?.close();
    await database.close();
  }
}

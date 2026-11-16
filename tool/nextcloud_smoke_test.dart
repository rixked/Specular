// End-to-end check of the Nextcloud backend against a real server.
//
//   dart run tool/nextcloud_smoke_test.dart https://cloud.example.com
//
// Logs in with Login Flow v2 (approve in the browser), then sends an item,
// receives it with a second simulated device, keeps it as a note and deletes
// everything it created. The app password is never printed. Revoke it
// afterwards in Nextcloud → Settings → Security ("Specular smoke test").
import 'dart:io';

import 'package:specular/backends/nextcloud/login_flow.dart';
import 'package:specular/backends/nextcloud/webdav_backend.dart';
import 'package:specular/core/sync/local_store.dart';
import 'package:specular/core/sync/remote_layout.dart';
import 'package:specular/core/sync/sync_engine.dart';

Future<void> main(List<String> args) async {
  if (args.length != 1) {
    stderr.writeln('Usage: dart run tool/nextcloud_smoke_test.dart <server>');
    exitCode = 64;
    return;
  }

  final flow = NextcloudLoginFlow(clientName: 'Specular smoke test');
  final session = await flow.start(args.single);
  stdout
    ..writeln('Open this URL and approve access:')
    ..writeln('  ${session.loginUrl}')
    ..writeln('Waiting for approval…');
  final credentials = await flow.waitForCredentials(session);
  flow.close();
  stdout.writeln('✓ Logged in as ${credentials.loginName}');

  final backend = NextcloudWebDavBackend(
    credentials: credentials,
    userAgent: 'Specular smoke test',
  );
  final sender = SyncEngine(
    backend: backend,
    store: InMemoryLocalStore(),
    deviceId: 'smoke1',
  );
  final receiver = SyncEngine(
    backend: backend,
    store: InMemoryLocalStore(),
    deviceId: 'smoke2',
  );

  String? noteFile;
  String? itemId;
  try {
    await sender.announceDevice(name: 'Smoke test', platform: 'cli');
    stdout.writeln('✓ /Specular/ layout ready, device announced');

    final item = await sender.send('Specular smoke test ${DateTime.now()}');
    itemId = item.id;
    stdout.writeln('✓ Sent ${item.id}');

    final result = await receiver.sync();
    final got = result.received.any((i) => i.id == item.id);
    if (!got) throw StateError('Receiver did not see the item');
    stdout.writeln(
      '✓ Received on second device '
      '(inbox has ${result.received.length} new item(s))',
    );

    noteFile = await receiver.keep(item.id);
    stdout.writeln('✓ Kept as /${RemoteLayout.notePath(noteFile)}');

    final senderResult = await sender.sync();
    stdout.writeln(
      '✓ Removed from the sender\'s inbox '
      '(${senderResult.removed} removed)',
    );
    stdout.writeln('\nAll checks passed.');
  } finally {
    if (noteFile != null) {
      await _tryDelete(backend, RemoteLayout.notePath(noteFile));
    }
    if (itemId != null) {
      await _tryDelete(backend, RemoteLayout.itemPath(itemId));
    }
    await _tryDelete(backend, RemoteLayout.devicePath('smoke1'));
    backend.close();
    stdout.writeln(
      'Cleaned up. Revoke the "Specular smoke test" app password '
      'in Nextcloud → Settings → Security.',
    );
  }
}

Future<void> _tryDelete(NextcloudWebDavBackend backend, String path) async {
  try {
    await backend.delete(path);
  } on Exception {
    // Already gone.
  }
}

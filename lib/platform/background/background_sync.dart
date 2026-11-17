import 'dart:io' show Platform;

import 'package:workmanager/workmanager.dart';

import '../../app/app_services.dart';
import '../../core/sync/sync_engine.dart';

const _uniqueName = 'specular-periodic-sync';
const _taskName = 'specular.sync';

/// Android only (SPEC.md §6): while the app is closed, sync about every
/// 15 minutes, the minimum Android allows, and only with a network.
///
/// Each run uploads queued items, fetches new ones into the local cache and
/// applies expiry, so the inbox is current when the app opens.
Future<void> scheduleBackgroundSync() async {
  if (!Platform.isAndroid) return;
  final workmanager = Workmanager();
  await workmanager.initialize(backgroundSyncDispatcher);
  await workmanager.registerPeriodicTask(
    _uniqueName,
    _taskName,
    frequency: const Duration(minutes: 15),
    constraints: Constraints(networkType: NetworkType.connected),
    existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
  );
}

/// Entry point of the background isolate that `workmanager` starts.
@pragma('vm:entry-point')
void backgroundSyncDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    final services = await AppServices.open();
    try {
      return await syncInBackground(services.engine);
    } finally {
      await services.close();
    }
  });
}

/// One background run. Always reports success: being offline or logged
/// out is not worth an extra retry, the next periodic run comes anyway.
Future<bool> syncInBackground(SyncEngine? engine) async {
  if (engine == null) return true;
  try {
    await engine.sync();
  } on Object {
    // Logged out or a server problem: the app shows it when opened.
  }
  return true;
}

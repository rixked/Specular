import 'dart:io' show Platform;

import 'package:flutter/widgets.dart';

import '../notifiers/change_notifier.dart' as specular;
import '../notifiers/manual_notifier.dart';
import '../notifiers/polling_notifier.dart';

/// The sync trigger for the current platform (SPEC.md §6): polling every
/// ~15 s on desktop, only on open/resume on Android.
specular.ChangeNotifier platformSyncTrigger() =>
    Platform.isAndroid || Platform.isIOS ? ManualNotifier() : PollingNotifier();

/// Calls [onResumed] when the app comes to the foreground: app resume on
/// Android, window focus on desktop. Dispose the listener with the app.
AppLifecycleListener listenForResume(VoidCallback onResumed) =>
    AppLifecycleListener(onResume: onResumed);

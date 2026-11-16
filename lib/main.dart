import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app/app_services.dart';
import 'app/sync_coordinator.dart';
import 'app/sync_lifecycle.dart';
import 'core/sync/local_store.dart';
import 'platform/share_intent/share_app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();
  final engine = services.engine;
  final coordinator = engine == null
      ? null
      : SyncCoordinator(engine: engine, trigger: platformSyncTrigger());
  runApp(SpecularApp(services: services, coordinator: coordinator));
  unawaited(coordinator?.start());
}

/// Entry point of the Android share target, started by `ShareActivity.kt`.
@pragma('vm:entry-point')
Future<void> shareMain() => runShareApp();

class SpecularApp extends StatefulWidget {
  const SpecularApp({super.key, required this.services, this.coordinator});

  final AppServices services;

  /// Null until the user has logged in.
  final SyncCoordinator? coordinator;

  @override
  State<SpecularApp> createState() => _SpecularAppState();
}

class _SpecularAppState extends State<SpecularApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    final coordinator = widget.coordinator;
    if (coordinator != null) {
      _lifecycle = listenForResume(coordinator.onAppResumed);
    }
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    unawaited(widget.coordinator?.dispose());
    unawaited(widget.services.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Specular',
      theme: ThemeData(brightness: Brightness.dark),
      home: Scaffold(
        body: Center(
          child: _PlaceholderStatus(
            coordinator: widget.coordinator,
            inbox: widget.services.engine?.watchInbox(),
          ),
        ),
      ),
    );
  }
}

/// Temporary status display until the real UI exists (SPEC.md §9, §13).
class _PlaceholderStatus extends StatelessWidget {
  const _PlaceholderStatus({required this.coordinator, required this.inbox});

  final SyncCoordinator? coordinator;
  final Stream<List<LocalItem>>? inbox;

  @override
  Widget build(BuildContext context) {
    final coordinator = this.coordinator;
    if (coordinator == null) return const Text('Specular · not logged in');
    return StreamBuilder<SyncState>(
      stream: coordinator.states,
      initialData: coordinator.state,
      builder: (context, state) => StreamBuilder<List<LocalItem>>(
        stream: inbox,
        builder: (context, items) => Text(
          'Specular · ${state.data!.phase.name} · '
          '${items.data?.length ?? 0} items',
        ),
      ),
    );
  }
}

import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'app/app_services.dart';
import 'app/device_info.dart';
import 'app/sync_coordinator.dart';
import 'app/sync_lifecycle.dart';
import 'backends/nextcloud/login_flow.dart';
import 'backends/nextcloud/nextcloud_credentials.dart';
import 'platform/share_intent/share_app.dart';
import 'ui/home/home_screen.dart';
import 'ui/login/login_screen.dart';
import 'ui/theme/specular_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final services = await AppServices.open();
  runApp(SpecularApp(services: services));
}

/// Entry point of the Android share target, started by `ShareActivity.kt`.
@pragma('vm:entry-point')
Future<void> shareMain() => runShareApp();

class SpecularApp extends StatefulWidget {
  const SpecularApp({super.key, required this.services});

  final AppServices services;

  @override
  State<SpecularApp> createState() => _SpecularAppState();
}

class _SpecularAppState extends State<SpecularApp> {
  SyncCoordinator? _coordinator;
  StreamSubscription<SyncState>? _stateSubscription;
  late final AppLifecycleListener _lifecycle;
  String? _loginMessage;

  AppServices get _services => widget.services;

  @override
  void initState() {
    super.initState();
    _lifecycle = listenForResume(() => _coordinator?.onAppResumed());
    if (_services.isLoggedIn) _startSync();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_stopSync());
    unawaited(_services.close());
    super.dispose();
  }

  void _startSync() {
    final coordinator = SyncCoordinator(
      engine: _services.engine!,
      trigger: platformSyncTrigger(),
    );
    _coordinator = coordinator;
    _stateSubscription = coordinator.states.listen((state) {
      if (state.phase == SyncPhase.unauthorized) {
        unawaited(
          _logOut(
            message:
                'Nextcloud rejected the app password. '
                'Please log in again.',
          ),
        );
      }
    });
    unawaited(coordinator.start());
  }

  Future<void> _stopSync() async {
    await _stateSubscription?.cancel();
    _stateSubscription = null;
    await _coordinator?.dispose();
    _coordinator = null;
  }

  Future<void> _onLoggedIn(NextcloudCredentials credentials) async {
    await _services.signIn(
      credentials,
      deviceName: defaultDeviceName(),
      platform: currentPlatform(),
    );
    if (!mounted) return;
    setState(() {
      _loginMessage = null;
      _startSync();
    });
  }

  Future<void> _logOut({String? message}) async {
    await _stopSync();
    await _services.signOut();
    if (!mounted) return;
    setState(() => _loginMessage = message);
  }

  @override
  Widget build(BuildContext context) {
    final coordinator = _coordinator;
    final engine = _services.engine;
    return MaterialApp(
      title: 'Specular',
      debugShowCheckedModeBanner: false,
      theme: specularTheme(),
      home: coordinator != null && engine != null
          ? HomeScreen(
              engine: engine,
              coordinator: coordinator,
              onLogOut: _logOut,
            )
          : LoginScreen(
              message: _loginMessage,
              onLoggedIn: _onLoggedIn,
              flowFactory: () => NextcloudLoginFlow(
                clientName: 'Specular (${defaultDeviceName()})',
              ),
            ),
    );
  }
}

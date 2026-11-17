import 'dart:async';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../app/app_services.dart';
import '../../ui/common/glass_toast.dart';
import '../../ui/theme/specular_theme.dart';
import 'share_handler.dart';

const _channel = MethodChannel('de.rixk.specular/share');

/// Entry point of the Android share target (see `ShareActivity.kt`).
Future<void> runShareApp() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const _ShareApp());
}

class _ShareApp extends StatefulWidget {
  const _ShareApp();

  @override
  State<_ShareApp> createState() => _ShareAppState();
}

class _ShareAppState extends State<_ShareApp> {
  ShareOutcome? _outcome;

  @override
  void initState() {
    super.initState();
    unawaited(_run());
  }

  Future<void> _run() async {
    AppServices? services;
    try {
      final payload = SharePayload.fromMap(
        await _channel.invokeMapMethod<Object?, Object?>('getShared'),
      );
      services = await AppServices.open();
      final result = await handleShare(payload, services.engine);
      if (mounted) setState(() => _outcome = result.outcome);

      if (result.outcome == ShareOutcome.sent) {
        unawaited(HapticFeedback.lightImpact());
        // Show "Sent" for about a second; upload meanwhile.
        await Future.wait([
          Future<void>.delayed(const Duration(milliseconds: 900)),
          uploadShared(services.engine!),
        ]);
      } else {
        await Future<void>.delayed(const Duration(milliseconds: 2200));
      }
    } on Object {
      if (mounted) setState(() => _outcome = ShareOutcome.failed);
      await Future<void>.delayed(const Duration(milliseconds: 2200));
    } finally {
      await services?.close();
      await _channel.invokeMethod<void>('finish');
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      theme: specularTheme(),
      home: ShareConfirmation(outcome: _outcome),
    );
  }
}

/// The small Soft Glass confirmation pill shown over the app the user
/// shared from (SPEC.md §3.2, §9).
class ShareConfirmation extends StatelessWidget {
  const ShareConfirmation({super.key, required this.outcome});

  /// Null while the item is being stored (a few milliseconds).
  final ShareOutcome? outcome;

  static String? messageFor(ShareOutcome? outcome) => switch (outcome) {
    null => null,
    ShareOutcome.sent => 'Sent',
    ShareOutcome.notLoggedIn => 'Open Specular and log in first',
    ShareOutcome.nothingToSend => 'Nothing to send',
    ShareOutcome.failed => "Couldn't send. Please try again",
  };

  @override
  Widget build(BuildContext context) {
    final message = messageFor(outcome);
    return Material(
      type: MaterialType.transparency,
      child: SafeArea(
        child: Align(
          alignment: const Alignment(0, 0.7),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: GlassToast(
              visible: message != null,
              message: message ?? '',
              icon: outcome == ShareOutcome.sent ? Icons.check_rounded : null,
            ),
          ),
        ),
      ),
    );
  }
}

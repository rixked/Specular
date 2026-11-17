import 'dart:async';
import 'dart:io' show exit;

import 'package:material_ui/material_ui.dart';
import 'package:pub_semver/pub_semver.dart';

import '../../core/updates/releases.dart';
import '../../platform/updater/update_service.dart';

/// What the update banner shows.
sealed class UpdateState {
  const UpdateState();
}

final class NoUpdate extends UpdateState {
  const NoUpdate();
}

/// A newer release exists and was not dismissed.
final class UpdateReady extends UpdateState {
  const UpdateReady(this.release, {this.message});
  final ReleaseInfo release;

  /// For example "Allow Specular to install apps, then tap Install again."
  final String? message;
}

final class UpdateDownloading extends UpdateState {
  const UpdateDownloading(this.release, this.progress);
  final ReleaseInfo release;

  /// 0 to 1, or null when the size is unknown.
  final double? progress;
}

final class UpdateFailed extends UpdateState {
  const UpdateFailed(this.release, this.message);
  final ReleaseInfo release;
  final String message;
}

/// Runs the update check and install flow for the UI (SPEC.md §3.6):
/// a check on every app start and every 24 hours while running, unless
/// switched off; a manual check is always possible.
final class UpdateController {
  UpdateController({
    required this.service,
    required this.settings,
    void Function()? quitApp,
    this.interval = const Duration(hours: 24),
  }) : _quitApp = quitApp ?? (() => exit(0));

  final UpdateService service;
  final UpdateSettings settings;
  final Duration interval;
  final void Function() _quitApp;

  final state = ValueNotifier<UpdateState>(const NoUpdate());
  final autoCheck = ValueNotifier<bool>(true);
  Timer? _timer;
  Version? _dismissed;

  Version get currentVersion => service.currentVersion;
  UpdatePlatform get platform => service.platform;

  /// Checks right away (if enabled) and then periodically.
  Future<void> start() async {
    autoCheck.value = await settings.autoCheckUpdates();
    _timer = Timer.periodic(interval, (_) {
      if (autoCheck.value) unawaited(check());
    });
    if (autoCheck.value) await check();
  }

  /// Checks now. Manual checks report "up to date" and errors to the
  /// caller; the banner only appears for an available update.
  Future<UpdateCheck> check() async {
    final result = await service.check();
    if (result is UpdateAvailable &&
        result.release.version != _dismissed &&
        state.value is! UpdateDownloading) {
      state.value = UpdateReady(result.release);
    }
    return result;
  }

  Future<void> setAutoCheck(bool enabled) async {
    autoCheck.value = enabled;
    await settings.setAutoCheckUpdates(enabled);
  }

  /// Hides the banner for this version until a newer one appears.
  void dismiss() {
    final current = state.value;
    if (current is UpdateReady) _dismissed = current.release.version;
    if (current is UpdateFailed) _dismissed = current.release.version;
    state.value = const NoUpdate();
  }

  /// Downloads, verifies and installs the update. Nothing is installed
  /// without this explicit call (the user's tap on Install).
  Future<void> install() async {
    final release = switch (state.value) {
      UpdateReady(:final release) => release,
      UpdateFailed(:final release) => release,
      _ => null,
    };
    if (release == null || !platform.installsInApp) return;

    state.value = UpdateDownloading(release, null);
    try {
      final file = await service.download(
        release,
        onProgress: (p) => state.value = UpdateDownloading(release, p),
      );
      final outcome = await service.install(file);
      switch (outcome) {
        case InstallOutcome.started:
          state.value = UpdateReady(release, message: 'Installing…');
          if (platform == UpdatePlatform.windows) _quitApp();
        case InstallOutcome.needsPermission:
          state.value = UpdateReady(
            release,
            message: 'Allow Specular to install apps, then tap Install again.',
          );
      }
    } on UpdateVerificationException catch (e) {
      state.value = UpdateFailed(release, e.message);
    } on Object {
      state.value = UpdateFailed(
        release,
        "Couldn't download the update. Check your connection.",
      );
    }
  }

  void dispose() {
    _timer?.cancel();
    service.close();
    state.dispose();
    autoCheck.dispose();
  }
}

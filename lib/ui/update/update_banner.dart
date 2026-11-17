import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../common/url_opener.dart';
import '../theme/tokens.dart';
import 'update_controller.dart';

/// A small, dismissible banner: "Update available · v0.2.0" (SPEC.md §3.6).
/// It never blocks the app; nothing is installed without a tap on Install.
class UpdateBanner extends StatelessWidget {
  const UpdateBanner({
    super.key,
    required this.controller,
    this.openUrl = openInBrowser,
  });

  final UpdateController controller;
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<UpdateState>(
      valueListenable: controller.state,
      builder: (context, state, _) {
        final visible = state is! NoUpdate;
        return AnimatedSwitcher(
          duration: SpecularMotion.of(context, SpecularMotion.fade),
          child: visible
              ? _Banner(
                  key: const Key('update-banner'),
                  state: state,
                  controller: controller,
                  openUrl: openUrl,
                )
              : const SizedBox.shrink(),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    super.key,
    required this.state,
    required this.controller,
    required this.openUrl,
  });

  final UpdateState state;
  final UpdateController controller;
  final UrlOpener openUrl;

  @override
  Widget build(BuildContext context) {
    final (release, title, detail, progress) = switch (state) {
      UpdateReady(:final release, :final message) => (
        release,
        'Update available · v${release.version}',
        message,
        null,
      ),
      UpdateDownloading(:final release, :final progress) => (
        release,
        'Downloading v${release.version}…',
        progress == null ? null : '${(progress * 100).round()} %',
        progress ?? -1.0,
      ),
      UpdateFailed(:final release, :final message) => (
        release,
        'Update failed',
        message,
        null,
      ),
      NoUpdate() => throw StateError('Banner shown without an update'),
    };
    final downloading = state is UpdateDownloading;
    final installsInApp = controller.platform.installsInApp;

    return Semantics(
      liveRegion: true,
      child: Material(
        color: Color.alphaBlend(
          Colors.white.withValues(alpha: 0.08),
          SpecularColors.cardUnderlay,
        ),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpecularRadii.card),
          side: BorderSide(
            color: SpecularColors.accent.withValues(alpha: 0.45),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 4, 10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Icon(
                    state is UpdateFailed
                        ? Icons.error_outline_rounded
                        : Icons.system_update_alt_rounded,
                    size: 20,
                    color: state is UpdateFailed
                        ? SpecularColors.error
                        : SpecularColors.accent,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (!downloading)
                    IconButton(
                      tooltip: 'Dismiss',
                      onPressed: controller.dismiss,
                      icon: const Icon(Icons.close_rounded, size: 18),
                      color: SpecularColors.icon,
                      constraints: const BoxConstraints.tightFor(
                        width: 44,
                        height: 44,
                      ),
                    ),
                ],
              ),
              if (detail != null)
                Padding(
                  padding: const EdgeInsets.only(left: 30, right: 12),
                  child: Text(
                    detail,
                    style: const TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: SpecularColors.textSecondary,
                    ),
                  ),
                ),
              if (progress != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(30, 8, 12, 4),
                  child: LinearProgressIndicator(
                    value: progress < 0 ? null : progress,
                    minHeight: 3,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              if (!downloading)
                Padding(
                  padding: const EdgeInsets.only(left: 18, top: 2),
                  child: Wrap(
                    spacing: 4,
                    children: [
                      TextButton(
                        onPressed: () => unawaited(openUrl(release.pageUrl)),
                        child: Text(
                          installsInApp ? "What's new" : 'Open release page',
                        ),
                      ),
                      if (installsInApp)
                        TextButton(
                          key: const Key('update-install'),
                          onPressed: () => unawaited(controller.install()),
                          child: Text(
                            state is UpdateFailed ? 'Try again' : 'Install',
                          ),
                        ),
                    ],
                  ),
                ),
              if (!installsInApp && !downloading)
                const Padding(
                  padding: EdgeInsets.fromLTRB(30, 0, 12, 4),
                  child: Text(
                    'Update with your package manager (pacman / yay).',
                    style: TextStyle(
                      fontSize: 12.5,
                      color: SpecularColors.textSecondary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Puts the update banner above any screen, at the top.
class UpdateOverlay extends StatelessWidget {
  const UpdateOverlay({
    super.key,
    required this.controller,
    required this.child,
  });

  final UpdateController? controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final controller = this.controller;
    if (controller == null) return child;
    return Stack(
      children: [
        child,
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: UpdateBanner(controller: controller),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

import 'dart:ui' show lerpDouble;

import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// A frosted-glass card (SPEC.md §9).
///
/// - [sheen] from 1 (new) to 0 (about to expire) fades fill, border and
///   highlight, so age is visible without reading numbers.
/// - [prism] draws the permanent prism-colored edge of kept items, over an
///   opaque underlay so text stays readable.
/// - [glint] sweeps a highlight across the card once (on receive). Skipped
///   when the OS asks for reduced motion.
class GlassCard extends StatefulWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.sheen = 1,
    this.prism = false,
    this.glint = false,
    this.onGlintDone,
  });

  final Widget child;
  final double sheen;
  final bool prism;
  final bool glint;
  final VoidCallback? onGlintDone;

  @override
  State<GlassCard> createState() => _GlassCardState();
}

class _GlassCardState extends State<GlassCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glint = AnimationController(
    vsync: this,
    duration: SpecularMotion.glint,
  );

  @override
  void initState() {
    super.initState();
    if (widget.glint) _scheduleGlint();
  }

  @override
  void didUpdateWidget(GlassCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.glint && !oldWidget.glint) _scheduleGlint();
  }

  void _scheduleGlint() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      if (!SpecularMotion.reduced(context)) {
        await _glint.forward(from: 0).orCancel.catchError((Object _) {});
      }
      if (mounted) widget.onGlintDone?.call();
    });
  }

  @override
  void dispose() {
    _glint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.sheen.clamp(0.0, 1.0);
    final fill = lerpDouble(0.025, 0.075, s)!;
    final border = lerpDouble(0.055, 0.12, s)!;
    final highlight = lerpDouble(0, 0.16, s)!;
    final shadow = lerpDouble(0, 0.28, s)!;
    final radius = BorderRadius.circular(SpecularRadii.card);

    Widget card = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: widget.prism
            ? Color.alphaBlend(
                Colors.white.withValues(alpha: 0.075),
                SpecularColors.cardUnderlay,
              )
            : Colors.white.withValues(alpha: fill),
        border: widget.prism
            ? null
            : Border.all(color: Colors.white.withValues(alpha: border)),
        boxShadow: [
          if (shadow > 0)
            BoxShadow(
              color: Colors.black.withValues(alpha: shadow),
              blurRadius: 28,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          children: [
            widget.child,
            // The thin top highlight of glass.
            Positioned(
              top: 0,
              left: 18,
              right: 18,
              height: 1,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.white.withValues(alpha: 0),
                        Colors.white.withValues(
                          alpha: widget.prism ? 0.16 : highlight,
                        ),
                        Colors.white.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedBuilder(
                  animation: _glint,
                  builder: (context, _) {
                    if (!_glint.isAnimating) return const SizedBox.shrink();
                    final t = Curves.easeOutCubic.transform(_glint.value);
                    return FractionalTranslation(
                      translation: Offset(lerpDouble(-1.3, 1.3, t)!, 0),
                      child: const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment(-1, -0.35),
                            end: Alignment(1, 0.35),
                            colors: [
                              Color(0x00FFFFFF),
                              Color(0x4DFFFFFF),
                              Color(0x00FFFFFF),
                            ],
                            stops: [0.35, 0.5, 0.65],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );

    if (widget.prism) {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(SpecularRadii.card + 1.5),
          gradient: const LinearGradient(
            begin: Alignment(-1, -0.6),
            end: Alignment(1, 0.6),
            colors: SpecularColors.prism,
          ),
        ),
        child: Padding(padding: const EdgeInsets.all(1.5), child: card),
      );
    }
    return card;
  }
}

/// How much sheen an unkept item has left after [age] (1 → 0 over 7 days).
double sheenForAge(Duration age) {
  if (age <= Duration.zero) return 1;
  final remaining = 1 - age.inSeconds / itemLifetime.inSeconds;
  return remaining.clamp(0.0, 1.0);
}

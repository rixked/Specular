import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// The deep background with one soft light source in the top-left corner
/// (SPEC.md §9).
class SpecularBackground extends StatelessWidget {
  const SpecularBackground({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: SpecularColors.background,
      child: Stack(
        children: [
          Positioned(
            top: -140,
            left: -110,
            width: 420,
            height: 420,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      SpecularColors.accent.withValues(alpha: 0.20),
                      SpecularColors.accent.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.68],
                  ),
                ),
              ),
            ),
          ),
          Positioned.fill(child: child),
        ],
      ),
    );
  }
}

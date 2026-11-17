import 'package:material_ui/material_ui.dart';

/// Soft Glass design tokens (SPEC.md §9).
///
/// All text colors meet WCAG AA (4.5:1) on [background] and on glass cards.
abstract final class SpecularColors {
  /// Near-black with a slight blue tint.
  static const background = Color(0xFF0A0E16);

  /// Opaque base under cards that sit on a colored edge, so the edge never
  /// shows through the text.
  static const cardUnderlay = Color(0xFF0D121B);

  static const text = Color(0xFFE8EDF6);
  static const textSecondary = Color(0xFFA3AEC0);
  static const icon = Color(0xFFC9D3E3);

  /// The one spectral accent.
  static const accent = Color(0xFF7DD3FC);

  /// Text and icons drawn on [accent].
  static const onAccent = Color(0xFF04202E);

  static const pendingBackground = Color(0x24FBD38D);
  static const pendingText = Color(0xFFFCD9A0);

  static const error = Color(0xFFFCA5A5);

  /// The prism edge of kept items, left to right.
  static const prism = [
    Color(0xFFFF8FB3),
    Color(0xFFFFC27A),
    Color(0xFFF4F08E),
    Color(0xFF86F2C4),
    Color(0xFF82CBFF),
    Color(0xFFBBA2FF),
  ];
}

abstract final class SpecularRadii {
  static const card = 20.0;
  static const control = 16.0;
  static const iconTile = 12.0;
  static const button = 14.0;
}

/// Every animation stays under 300 ms and never blocks input (SPEC.md §9).
abstract final class SpecularMotion {
  static const glint = Duration(milliseconds: 280);
  static const expand = Duration(milliseconds: 180);
  static const fade = Duration(milliseconds: 180);

  /// How long the "Sent" confirmation stays visible.
  static const toastVisible = Duration(milliseconds: 1200);

  /// True when the OS asks for reduced motion (SPEC.md §9).
  static bool reduced(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  /// [duration], or zero when motion is reduced.
  static Duration of(BuildContext context, Duration duration) =>
      reduced(context) ? Duration.zero : duration;
}

/// Unkept items lose their sheen over this period (SPEC.md §9).
const itemLifetime = Duration(days: 7);

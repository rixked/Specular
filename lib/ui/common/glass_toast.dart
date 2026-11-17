import 'package:material_ui/material_ui.dart';

import '../theme/tokens.dart';

/// A short confirmation pill, for example "Sent" with a check mark.
///
/// It is a status message, not a button: it fades in, stays briefly and
/// fades out, and never takes taps.
class GlassToast extends StatelessWidget {
  const GlassToast({
    super.key,
    required this.visible,
    required this.message,
    this.icon,
  });

  /// "Sent" with the accent check mark.
  const GlassToast.sent({super.key, required this.visible})
    : message = 'Sent',
      icon = Icons.check_rounded;

  final bool visible;
  final String message;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Semantics(
        liveRegion: true,
        excludeSemantics: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: SpecularMotion.of(context, SpecularMotion.fade),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
            decoration: BoxDecoration(
              color: const Color(0xEB101622),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x66000000),
                  blurRadius: 30,
                  offset: Offset(0, 10),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: SpecularColors.accent),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    message,
                    style: const TextStyle(
                      color: SpecularColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

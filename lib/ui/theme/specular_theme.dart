import 'package:material_ui/material_ui.dart';

import 'tokens.dart';

/// The app's dark Soft Glass theme (SPEC.md §9).
ThemeData specularTheme() {
  const scheme = ColorScheme.dark(
    surface: SpecularColors.background,
    onSurface: SpecularColors.text,
    primary: SpecularColors.accent,
    onPrimary: SpecularColors.onAccent,
    secondary: SpecularColors.accent,
    onSecondary: SpecularColors.onAccent,
    error: SpecularColors.error,
  );
  final base = ThemeData(
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: 'Inter',
    scaffoldBackgroundColor: SpecularColors.background,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: SpecularColors.text,
      displayColor: SpecularColors.text,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: 0.07),
      hintStyle: const TextStyle(color: SpecularColors.textSecondary),
      labelStyle: const TextStyle(color: SpecularColors.textSecondary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: _outline(Colors.white.withValues(alpha: 0.14)),
      enabledBorder: _outline(Colors.white.withValues(alpha: 0.14)),
      focusedBorder: _outline(SpecularColors.accent),
      errorBorder: _outline(SpecularColors.error),
      focusedErrorBorder: _outline(SpecularColors.error),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: SpecularColors.accent,
        foregroundColor: SpecularColors.onAccent,
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(SpecularRadii.control),
        ),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: SpecularColors.accent,
        minimumSize: const Size(44, 44),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xF0101622),
      contentTextStyle: TextStyle(color: SpecularColors.text),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: SpecularColors.accent,
    ),
  );
}

OutlineInputBorder _outline(Color color) => OutlineInputBorder(
  borderRadius: BorderRadius.circular(SpecularRadii.control),
  borderSide: BorderSide(color: color),
);

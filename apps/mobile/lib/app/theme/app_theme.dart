import 'package:flutter/material.dart';

import 'tokens.g.dart';

/// Tema escuro do EvoFit: Material 3 com cores e formas vindas dos tokens de design.
abstract final class AppTheme {
  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: EvoColors.accent,
      onPrimary: EvoColors.onAccent,
      secondary: EvoColors.accent,
      onSecondary: EvoColors.onAccent,
      error: EvoColors.danger,
      onError: EvoColors.onAccent,
      surface: EvoColors.bgSurface,
      onSurface: EvoColors.textPrimary,
      onSurfaceVariant: EvoColors.textSecondary,
      surfaceContainerHighest: EvoColors.bgElevated,
      outline: EvoColors.borderSubtle,
      outlineVariant: EvoColors.borderSubtle,
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(
      bodyColor: EvoColors.textPrimary,
      displayColor: EvoColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: EvoColors.bgBase,
      textTheme: text.copyWith(
        displaySmall: text.displaySmall?.copyWith(
          fontSize: EvoFontSize.displaySm,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: EvoFontSize.title,
          fontWeight: FontWeight.w600,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: EvoFontSize.titleSm,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: text.bodyLarge?.copyWith(fontSize: EvoFontSize.body),
        bodyMedium: text.bodyMedium?.copyWith(
          fontSize: EvoFontSize.bodySm,
          color: EvoColors.textSecondary,
        ),
        labelSmall: text.labelSmall?.copyWith(
          fontSize: EvoFontSize.caption,
          color: EvoColors.textSecondary,
        ),
      ),
      cardTheme: const CardThemeData(
        color: EvoColors.bgSurface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(EvoRadius.card)),
          side: BorderSide(color: EvoColors.borderSubtle),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(evoTouchTargetMin, evoTouchTargetMin),
          padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(EvoRadius.input)),
          ),
          textStyle: const TextStyle(
            fontSize: EvoFontSize.body,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(evoTouchTargetMin, evoTouchTargetMin),
          padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
          foregroundColor: EvoColors.textPrimary,
          side: const BorderSide(color: EvoColors.borderSubtle),
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(EvoRadius.input)),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        },
      ),
    );
  }
}

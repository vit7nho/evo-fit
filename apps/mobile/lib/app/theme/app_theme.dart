import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'motion.dart';
import 'tokens.g.dart';

/// Tema claro e monocromático do EvoFit: fundo off-white, superfícies brancas e preto
/// como cor de ação. Vermelho e verde só aparecem para erro e sucesso.
abstract final class AppTheme {
  /// Ícones escuros na barra de status e na de navegação, sobre o fundo off-white.
  static const systemOverlay = SystemUiOverlayStyle(
    statusBarColor: Color(0x00000000),
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarColor: EvoColors.bgBase,
    systemNavigationBarIconBrightness: Brightness.dark,
  );

  static const _pill = StadiumBorder();
  static const _buttonSize = Size(evoTouchTargetMin, 56);
  static const _buttonText = TextStyle(
    fontSize: EvoFontSize.body,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.1,
  );

  static OutlineInputBorder _inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(EvoRadius.input)),
        borderSide: BorderSide(color: color, width: width),
      );

  static ThemeData light() {
    const scheme = ColorScheme(
      brightness: Brightness.light,
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
      surfaceContainerHigh: EvoColors.bgSurface,
      surfaceContainer: EvoColors.bgSurface,
      surfaceContainerLow: EvoColors.bgBase,
      outline: EvoColors.borderStrong,
      outlineVariant: EvoColors.borderSubtle,
      surfaceTint: Color(0x00000000),
    );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme);
    final text = base.textTheme.apply(
      bodyColor: EvoColors.textPrimary,
      displayColor: EvoColors.textPrimary,
    );

    return base.copyWith(
      scaffoldBackgroundColor: EvoColors.bgBase,
      textTheme: text.copyWith(
        displayMedium: text.displayMedium?.copyWith(
          fontSize: EvoFontSize.display,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.6,
          height: 1.05,
        ),
        displaySmall: text.displaySmall?.copyWith(
          fontSize: EvoFontSize.displaySm,
          fontWeight: FontWeight.w800,
          letterSpacing: -1.1,
          height: 1.1,
        ),
        titleLarge: text.titleLarge?.copyWith(
          fontSize: EvoFontSize.title,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
        titleMedium: text.titleMedium?.copyWith(
          fontSize: EvoFontSize.body,
          fontWeight: FontWeight.w600,
        ),
        bodyLarge: text.bodyLarge?.copyWith(
          fontSize: EvoFontSize.body,
          height: 1.45,
        ),
        bodyMedium: text.bodyMedium?.copyWith(
          fontSize: EvoFontSize.bodySm,
          color: EvoColors.textSecondary,
          height: 1.4,
        ),
        labelLarge: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
        labelSmall: text.labelSmall?.copyWith(
          fontSize: EvoFontSize.caption,
          color: EvoColors.textSecondary,
          letterSpacing: 0.2,
        ),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: EvoColors.bgBase,
        foregroundColor: EvoColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Color(0x00000000),
        centerTitle: false,
        systemOverlayStyle: systemOverlay,
        titleTextStyle: TextStyle(
          color: EvoColors.textPrimary,
          fontSize: EvoFontSize.titleSm,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
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
          backgroundColor: EvoColors.accent,
          foregroundColor: EvoColors.onAccent,
          disabledBackgroundColor: EvoColors.bgElevated,
          disabledForegroundColor: EvoColors.textSecondary,
          minimumSize: _buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
          shape: _pill,
          textStyle: _buttonText,
          elevation: 0,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: EvoColors.textPrimary,
          backgroundColor: EvoColors.bgSurface,
          minimumSize: _buttonSize,
          padding: const EdgeInsets.symmetric(horizontal: EvoSpace.xl),
          side: const BorderSide(color: EvoColors.borderStrong),
          shape: _pill,
          textStyle: _buttonText,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: EvoColors.textPrimary,
          minimumSize: const Size(evoTouchTargetMin, evoTouchTargetMin),
          shape: _pill,
          textStyle: const TextStyle(
            fontSize: EvoFontSize.bodySm,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: EvoColors.textPrimary,
          minimumSize: const Size(evoTouchTargetMin, evoTouchTargetMin),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: EvoColors.bgSurface,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: EvoSpace.lg + 2,
          vertical: EvoSpace.lg + 2,
        ),
        border: _inputBorder(EvoColors.borderStrong),
        enabledBorder: _inputBorder(EvoColors.borderStrong),
        focusedBorder: _inputBorder(EvoColors.accent, 1.8),
        errorBorder: _inputBorder(EvoColors.danger),
        focusedErrorBorder: _inputBorder(EvoColors.danger, 1.8),
        labelStyle: const TextStyle(color: EvoColors.textSecondary),
        floatingLabelStyle: WidgetStateTextStyle.resolveWith(
          (states) => TextStyle(
            color: states.contains(WidgetState.error)
                ? EvoColors.danger
                : EvoColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
        helperStyle: const TextStyle(color: EvoColors.textSecondary),
        errorStyle: const TextStyle(color: EvoColors.danger),
        suffixIconColor: EvoColors.textSecondary,
        errorMaxLines: 3,
        helperMaxLines: 3,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? EvoColors.accent
              : const Color(0x00000000),
        ),
        checkColor: const WidgetStatePropertyAll(EvoColors.onAccent),
        side: const BorderSide(color: EvoColors.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(6)),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: EvoColors.bgSurface,
        surfaceTintColor: Color(0x00000000),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(EvoRadius.card)),
        ),
        titleTextStyle: TextStyle(
          color: EvoColors.textPrimary,
          fontSize: EvoFontSize.titleSm,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: EvoColors.accent,
        linearTrackColor: EvoColors.bgElevated,
        circularTrackColor: Color(0x00000000),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: EvoColors.accent,
        contentTextStyle: TextStyle(color: EvoColors.onAccent),
        behavior: SnackBarBehavior.floating,
        shape: StadiumBorder(),
      ),
      dividerTheme: const DividerThemeData(
        color: EvoColors.borderSubtle,
        thickness: 1,
        space: 1,
      ),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: EvoColors.accent,
        selectionColor: EvoColors.bgElevated,
        selectionHandleColor: EvoColors.accent,
      ),
      splashFactory: InkRipple.splashFactory,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: EvoPageTransitionsBuilder()},
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'theme_surface_style.dart';

import '../models/theme_config.dart';

class AppTheme {
  // We keep static getters for convenience, but they should be used in builder
  // where we can watch the themeProvider.

  static ThemeData buildTheme(ThemeConfig config) {
    final family =
        const {
          'sans-serif': 'Roboto',
          'serif': 'Noto Serif',
          'monospace': 'Roboto Mono',
        }[config.fontFamily] ??
        config.fontFamily;
    final baseText = ThemeData.dark().textTheme.apply(
      bodyColor: config.text,
      displayColor: config.text,
    );
    final textTheme = family == 'Nunito'
        ? baseText.apply(fontFamily: 'Nunito')
        : config.fontFamily == 'sans-serif'
        ? baseText
        : GoogleFonts.getTextTheme(
            GoogleFonts.asMap().containsKey(family) ? family : 'Roboto',
            ThemeData.dark().textTheme.apply(
              bodyColor: config.text,
              displayColor: config.text,
            ),
          );
    return ThemeData(
      extensions: [
        ThemeSurfaceStyle(
          opacity: config.glassOpacity,
          blur: config.blurSigma,
          borderWidth: config.borderWidth,
        ),
      ],
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: Colors.transparent,
      primaryColor: config.primary,
      colorScheme: ColorScheme.dark(
        primary: config.primary,
        surface: config.surface,
        background: config.background,
      ),
      cardTheme: CardThemeData(
        color: config.surface.withOpacity(config.glassOpacity),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(config.cardRadius),
          side: BorderSide(
            color: config.primary.withOpacity(0.14),
            width: config.borderWidth,
          ),
        ),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: config.background.withOpacity(0.4),
        foregroundColor: config.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        surfaceTintColor: Colors.transparent,
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: config.surface.withOpacity(.94),
        contentTextStyle: TextStyle(color: config.text),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(config.cardRadius),
          side: BorderSide(color: config.primary.withOpacity(.32)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? config.primary
              : config.textDim,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? config.primary.withOpacity(0.35)
              : config.surface,
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: config.primary,
        selectionColor: config.primary.withOpacity(0.35),
        selectionHandleColor: config.primary,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          backgroundColor: WidgetStatePropertyAll(config.primary),
          foregroundColor: WidgetStatePropertyAll(config.background),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(config.cardRadius),
            ),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(config.primary),
          side: WidgetStatePropertyAll(
            BorderSide(color: config.primary.withOpacity(.55)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(config.cardRadius),
            ),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStatePropertyAll(config.primary),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(config.cardRadius),
            ),
          ),
        ),
      ),
    );
  }

  // Fallback static values for initial launch/const contexts
  static const Color background = Color(0xFF080808);
  static const Color surface = Color(0xFF141414);
  static const Color primary = Color(0xFFE00000);
  static const Color primaryDark = Color(0xFF700000);
  static const Color text = Colors.white;
  static const Color textDim = Color(0xFF888888);
  static const Color meshIdle1 = Color(0xFF220505);
  static const Color meshIdle2 = Color(0xFF110202);
  static const Color meshActive1 = Color(0xFF3A0000);
  static const Color meshActive2 = Color(0xFF1F0000);

  static ThemeData get darkTheme => buildTheme(ThemeConfig.defaultTheme);
}

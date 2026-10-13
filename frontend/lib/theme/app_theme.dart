/// QuickBite cream/orange theme.
///
/// Palette:
/// * Backgrounds: warm cream `#FFF8F0` (scaffold), `#F7EBDD` (raised cards).
/// * Primary: deep orange `#E8641B` as the brand accent; `#B34A0E` as the
///   *text-on-color* primary. White on `#E8641B` is only ~3.1:1 contrast, so
///   buttons and other filled controls use the darker `#B34A0E` (≈5.9:1 vs
///   white) to meet WCAG AA for normal text. `#E8641B` is reserved for large
///   graphics, icons and non-text accents.
/// * Ink: warm browns — `#3E2723` body text on cream is ≈13:1.
///
/// The theme respects the OS text scaler: no fixed `textScaleFactor` clamps,
/// no hard-coded text heights; layout uses flexible constraints so a 200%
/// text scale reflows instead of overflowing.
library;

import 'package:flutter/material.dart';

class AppColors {
  static const cream = Color(0xFFFFF8F0);
  static const creamRaised = Color(0xFFF7EBDD);
  static const creamPressed = Color(0xFFF1DFC9);

  /// Brand accent (large graphics / icons only — not for small text on white).
  static const orange = Color(0xFFE8641B);

  /// Primary for filled controls: white text on this is WCAG AA.
  static const orangeDeep = Color(0xFFB34A0E);
  static const orangeDeepDark = Color(0xFF8F3A08);

  static const ink = Color(0xFF3E2723);
  static const inkSoft = Color(0xFF6D4C41);
  static const inkFaint = Color(0xFF8D6E63);

  static const success = Color(0xFF1B7A3D);
  static const successBg = Color(0xFFDFF2E3);
  static const warning = Color(0xFF9A6200);
  static const warningBg = Color(0xFFFFF0D1);
  static const info = Color(0xFF1565C0);
  static const infoBg = Color(0xFFDCEBFB);
  static const danger = Color(0xFFB3261E);
  static const dangerBg = Color(0xFFF9DEDC);

  /// Status chip colors (background, foreground) — foregrounds are dark so
  /// they keep ≥4.5:1 contrast on the tinted backgrounds.
  static const statusColors = <String, (Color bg, Color fg)>{
    'PENDING': (warningBg, Color(0xFF7A4D00)),
    'PAID': (infoBg, Color(0xFF0D47A1)),
    'CONFIRMED': (Color(0xFFD3F0EC), Color(0xFF00695C)),
    'DRIVER_ASSIGNED': (successBg, Color(0xFF14532D)),
    'PAYMENT_FAILED': (dangerBg, Color(0xFF7F1D1D)),
    'FAILED': (dangerBg, Color(0xFF7F1D1D)),
  };
}

ThemeData buildAppTheme() {
  const scheme = ColorScheme(
    brightness: Brightness.light,
    primary: AppColors.orangeDeep,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFFFE3CF),
    onPrimaryContainer: Color(0xFF5D2C0C),
    secondary: AppColors.orange,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFFFE3CF),
    onSecondaryContainer: Color(0xFF5D2C0C),
    tertiary: Color(0xFF7A4D00),
    onTertiary: Colors.white,
    error: AppColors.danger,
    onError: Colors.white,
    surface: AppColors.cream,
    onSurface: AppColors.ink,
    surfaceContainerHighest: AppColors.creamRaised,
    onSurfaceVariant: AppColors.inkSoft,
    outline: Color(0xFFD7BFA9),
    outlineVariant: Color(0xFFEAD9C2),
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.cream,
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.cream,
      foregroundColor: AppColors.ink,
      elevation: 0,
      centerTitle: false,
    ),
    cardTheme: CardThemeData(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: const EdgeInsets.symmetric(vertical: 6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.orangeDeep,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 52),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.orangeDeep,
        side: const BorderSide(color: AppColors.orangeDeep, width: 1.5),
        minimumSize: const Size(48, 52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: AppColors.orangeDeep,
        minimumSize: const Size(48, 44),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD7BFA9)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFD7BFA9)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.orangeDeep, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: AppColors.danger),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: AppColors.creamRaised,
      selectedColor: AppColors.orangeDeep,
      labelStyle: const TextStyle(color: AppColors.ink),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      side: const BorderSide(color: Color(0xFFD7BFA9)),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.orangeDeep,
      foregroundColor: Colors.white,
    ),
    snackBarTheme: const SnackBarThemeData(
      backgroundColor: AppColors.ink,
      contentTextStyle: TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.orangeDeep,
    ),
  );
}

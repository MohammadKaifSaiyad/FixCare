import 'package:flutter/material.dart';

/// FixCare design tokens — the exact palette from the design file
/// (Claude Design/…/FixCare Customer App.dc.html), captured in
/// docs/designs/2026-09-05-auth-screens-visual-spec.md.
///
/// Single fixed light theme (the design defines no dark variant).
class FixCareColors {
  FixCareColors._();

  static const primary = Color(0xFFC2521B); // terracotta — CTAs, brand, active
  static const success = Color(0xFF1D6B4F); // green — logo check badge, "serviceable"

  static const background = Color(0xFFFBF7F4); // app background (warm cream)
  static const surface = Color(0xFFFFFFFF); // fields, cards
  static const darkSurface = Color(0xFF241A15); // the one dark surface (booking card)

  static const textPrimary = Color(0xFF241A15); // near-black warm
  static const textSecondary = Color(0xFF5C4B43); // secondary
  static const textMuted = Color(0xFF7A6A62); // muted / helper
  static const textFaint = Color(0xFF8B7A71); // legal microcopy
  static const placeholder = Color(0xFF9A8A81);

  static const border = Color(0xFFEADFD8); // field / card borders
  static const borderStrong = Color(0xFFD8C9C0); // dividers, dashed pending

  static const primaryTint = Color(0xFFFDECE2); // badge/avatar tile bg
  static const taglineTint = Color(0xFFFBDCCB); // tagline on terracotta

  // Disabled primary button (throttled state)
  static const disabledFill = Color(0xFFEFE1D8);
  static const disabledText = Color(0xFFB09B90);

  // Error (OTP wrong-code state)
  static const errorFill = Color(0xFFFEF1EE);
  static const errorBorder = Color(0xFFC9442B);
  static const errorText = Color(0xFFA63116);

  // Dev-OTP hint banner
  static const devHintFill = Color(0xFFFFF6E8);
  static const devHintBorder = Color(0xFFF0DDBC);
  static const devHintText = Color(0xFF6B5320);
}

/// Radius system from the design: pills 999, cards/buttons 16, fields 14, chips 12.
class FixCareRadii {
  FixCareRadii._();
  static const field = 14.0;
  static const button = 16.0;
  static const card = 16.0;
  static const tile = 16.0;
}

/// Legacy aliases (kept so existing imports keep compiling).
const fixCarePrimary = FixCareColors.primary;
const fixCareSuccess = FixCareColors.success;

ThemeData buildFixCareTheme() {
  const scheme = ColorScheme.light(
    primary: FixCareColors.primary,
    onPrimary: Colors.white,
    secondary: FixCareColors.success,
    onSecondary: Colors.white,
    surface: FixCareColors.background,
    onSurface: FixCareColors.textPrimary,
    error: FixCareColors.errorBorder,
    onError: Colors.white,
  );

  TextStyle t(double size, FontWeight w, Color c, {double? spacing, double? height}) =>
      TextStyle(fontSize: size, fontWeight: w, color: c, letterSpacing: spacing, height: height);

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: FixCareColors.background,
    fontFamily: 'Outfit',
    // Text scale mapped to the spec's weights/sizes/colors.
    textTheme: TextTheme(
      // headings
      headlineMedium: t(28, FontWeight.w600, FixCareColors.textPrimary, spacing: -0.5, height: 1.2),
      titleLarge: t(18, FontWeight.w600, FixCareColors.textPrimary),
      // body
      bodyLarge: t(15, FontWeight.w400, FixCareColors.textPrimary, height: 1.5),
      bodyMedium: t(14.5, FontWeight.w400, FixCareColors.textMuted, height: 1.5),
      bodySmall: t(13, FontWeight.w400, FixCareColors.textMuted),
      // Button-only: white text assumes a colored (terracotta) fill. Do NOT
      // reuse labelLarge for a label on the cream background — it'd be invisible.
      labelLarge: t(17, FontWeight.w600, Colors.white),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: FixCareColors.background,
      surfaceTintColor: Colors.transparent,
      foregroundColor: FixCareColors.textPrimary,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontFamily: 'Outfit',
        fontSize: 18,
        fontWeight: FontWeight.w600,
        color: FixCareColors.textPrimary,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: FixCareColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: FixCareColors.disabledFill,
        disabledForegroundColor: FixCareColors.disabledText,
        minimumSize: const Size.fromHeight(56), // spec: CTAs are 56px tall
        textStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w600),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(FixCareRadii.button)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: FixCareColors.surface,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      hintStyle: const TextStyle(color: FixCareColors.placeholder, fontWeight: FontWeight.w400),
      labelStyle: const TextStyle(color: FixCareColors.textMuted),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FixCareRadii.field),
        borderSide: const BorderSide(color: FixCareColors.border, width: 1.5),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FixCareRadii.field),
        borderSide: const BorderSide(color: FixCareColors.primary, width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FixCareRadii.field),
        borderSide: const BorderSide(color: FixCareColors.errorBorder, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(FixCareRadii.field),
        borderSide: const BorderSide(color: FixCareColors.errorBorder, width: 1.5),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: FixCareColors.primary,
        textStyle: const TextStyle(fontFamily: 'Outfit', fontSize: 14, fontWeight: FontWeight.w600),
      ),
    ),
  );
}

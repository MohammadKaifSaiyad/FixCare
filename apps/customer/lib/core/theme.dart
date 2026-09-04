import 'package:flutter/material.dart';

const fixCarePrimary = Color(0xFFC2521B);
const fixCareSuccess = Color(0xFF1D6B4F);

ThemeData buildFixCareTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: fixCarePrimary,
    primary: fixCarePrimary,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Outfit', // bundled later; falls back to system until then
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size.fromHeight(52), // ≥48dp touch targets
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
  );
}

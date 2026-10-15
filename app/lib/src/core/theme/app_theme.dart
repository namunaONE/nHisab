import 'package:flutter/material.dart';

/// Fidelity theme: Primary #002C6D navy depth, Secondary #4FD166 growth green.
class AppTheme {
  static const primarySeed = Color(0xFF002C6D);
  static const secondarySeed = Color(0xFF4FD166);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      secondary: secondarySeed,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.primary),
        headingTextStyle: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.bold),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      secondary: secondarySeed,
      brightness: Brightness.dark,
    );
    return ThemeData(useMaterial3: true, colorScheme: scheme);
  }
}

import 'package:flutter/material.dart';

/// Fidelity theme: Primary #002C6D navy depth, Secondary #4FD166 growth green.
///
/// All roles derived from the two seeds via [ColorScheme.fromSeed]. No dynamic
// color. Every widget should resolve colors/shapes/typography from Theme so the
// design system stays single-source-of-truth (see docs/05-design-system.md).
class AppTheme {
  static const primarySeed = Color(0xFF002C6D);
  static const secondarySeed = Color(0xFF4FD166);

  static const errorColor = Color(0xFFBA1A1A);

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      secondary: secondarySeed,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      // ---- Typography (M3 15 roles, docs/05 #2) ----
      textTheme: _textTheme(scheme),
      // ---- Cards ----
      cardTheme: _cardThemeData(scheme),
      // ---- Buttons ----
      filledButtonTheme: _filledButtonTheme(scheme),
      elevatedButtonTheme: _elevatedButtonTheme(scheme),
      outlinedButtonTheme: _outlinedButtonTheme(scheme),
      textButtonTheme: _textButtonTheme(scheme),
      iconButtonTheme: _iconButtonTheme(scheme),
      segmentedButtonTheme: _segmentedButtonTheme(scheme),
      // ---- Inputs ----
      inputDecorationTheme: _inputDecorationTheme(scheme),
      // ---- NavigationBar ----
      navigationBarTheme: _navigationBarTheme(scheme),
      // ---- AppBar ----
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      // ---- DataTable2 ----
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.primary),
        headingTextStyle: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: primarySeed,
      secondary: secondarySeed,
      brightness: Brightness.dark,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
      textTheme: _textTheme(scheme),
      cardTheme: _cardThemeData(scheme),
      filledButtonTheme: _filledButtonTheme(scheme),
      elevatedButtonTheme: _elevatedButtonTheme(scheme),
      outlinedButtonTheme: _outlinedButtonTheme(scheme),
      textButtonTheme: _textButtonTheme(scheme),
      iconButtonTheme: _iconButtonTheme(scheme),
      segmentedButtonTheme: _segmentedButtonTheme(scheme),
      inputDecorationTheme: _inputDecorationTheme(scheme),
      navigationBarTheme: _navigationBarTheme(scheme),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      dataTableTheme: DataTableThemeData(
        headingRowColor: WidgetStatePropertyAll(scheme.primary),
        headingTextStyle: TextStyle(
          color: scheme.onPrimary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  // =========================================================================
  // Typography
  // =========================================================================
  static TextTheme _textTheme(ColorScheme scheme) {
    final base = TextTheme();
    return base.copyWith(
      // Brand moments - reserved weight for display only
      displayLarge: base.displayLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
        letterSpacing: -0.5,
      ),
      displayMedium: base.displayMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
        letterSpacing: -0.25,
      ),
      displaySmall: base.displaySmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurfaceVariant,
      ),
      // Page headers
      headlineLarge: base.headlineLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
      ),
      headlineMedium: base.headlineMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
      ),
      headlineSmall: base.headlineSmall?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurfaceVariant,
      ),
      // Portfolio totals footer (bold primary)
      titleLarge: base.titleLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.primary,
      ),
      // Page titles Ledger / Parties
      titleMedium: base.titleMedium?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
      ),
      titleSmall: base.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        color: scheme.onSurfaceVariant,
      ),
      // Tabular ledger cells, right-aligned numerics, tabular figures
      bodyLarge: base.bodyLarge?.copyWith(
        color: scheme.onSurface,
      ),
      bodyMedium: base.bodyMedium?.copyWith(
        color: scheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      bodySmall: base.bodySmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      // Dual date AD | BS pill
      labelLarge: base.labelLarge?.copyWith(
        fontWeight: FontWeight.bold,
        color: scheme.onSurface,
      ),
      labelMedium: base.labelMedium?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
      labelSmall: base.labelSmall?.copyWith(
        color: scheme.onSurfaceVariant,
      ),
    );
  }

  // =========================================================================
  // Cards - outlined preferred for dense financial lists (docs/05 #4)
  // =========================================================================
  static CardThemeData _cardThemeData(ColorScheme scheme) {
    return CardThemeData(
      color: scheme.surfaceContainerLowest,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }

  // =========================================================================
  // Buttons - M3 default 40dp tall fully rounded (docs/05 #3)
  // =========================================================================
  static FilledButtonThemeData _filledButtonTheme(ColorScheme scheme) {
    return FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.secondary,
        foregroundColor: const Color(0xFF00210A), // dark text on growth green
        elevation: 0,
      ).copyWith(
        minimumSize: WidgetStateProperty.all(const Size(88, 40)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  static ElevatedButtonThemeData _elevatedButtonTheme(ColorScheme scheme) {
    return ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
      ).copyWith(
        minimumSize: WidgetStateProperty.all(const Size(88, 40)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  static OutlinedButtonThemeData _outlinedButtonTheme(ColorScheme scheme) {
    return OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.primary, width: 1.5),
        elevation: 0,
      ).copyWith(
        minimumSize: WidgetStateProperty.all(const Size(88, 40)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  static TextButtonThemeData _textButtonTheme(ColorScheme scheme) {
    return TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        elevation: 0,
      ).copyWith(
        minimumSize: WidgetStateProperty.all(const Size(64, 40)),
        shape: WidgetStateProperty.all(
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        ),
      ),
    );
  }

  static IconButtonThemeData _iconButtonTheme(ColorScheme scheme) {
    return IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: scheme.onSurfaceVariant,
        iconSize: 20,
        minimumSize: const Size(48, 48),
        padding: EdgeInsets.zero,
      ),
    );
  }

  static SegmentedButtonThemeData _segmentedButtonTheme(ColorScheme scheme) {
    return SegmentedButtonThemeData(
      style: SegmentedButton.styleFrom(
        foregroundColor: scheme.onSurface,
        selectedForegroundColor: scheme.primary,
        selectedBackgroundColor: scheme.primaryContainer,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        visualDensity: VisualDensity.compact,
      ),
    );
  }

  // =========================================================================
  // Inputs - mobile keyboards per field, inline error in error color
  // =========================================================================
  static InputDecorationTheme _inputDecorationTheme(ColorScheme scheme) {
    return InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 1.5),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.error, width: 2),
      ),
      labelStyle: TextStyle(
        color: scheme.onSurfaceVariant,
        fontSize: 14,
      ),
      hintStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.6),
        fontSize: 14,
      ),
      errorStyle: TextStyle(
        color: scheme.error,
        fontSize: 12,
        height: 1.2,
      ),
      helperStyle: TextStyle(
        color: scheme.onSurfaceVariant.withValues(alpha: 0.7),
        fontSize: 12,
      ),
    );
  }

  // =========================================================================
  // Bottom NavigationBar - 5 destinations (Docs/05 #4)
  // =========================================================================
  static NavigationBarThemeData _navigationBarTheme(ColorScheme scheme) {
    return NavigationBarThemeData(
      backgroundColor: scheme.surfaceContainerLowest.withValues(alpha: 0.9),
      indicatorColor: scheme.primaryContainer.withValues(alpha: 0.6),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return TextStyle(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
            fontSize: 12,
          );
        }
        return TextStyle(
          color: scheme.onSurfaceVariant,
          fontSize: 12,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return IconThemeData(color: scheme.primary, size: 22);
        }
        return IconThemeData(color: scheme.onSurfaceVariant, size: 22);
      }),
    );
  }
}

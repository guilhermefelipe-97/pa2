import 'package:flutter/material.dart';

/// Curator & Taste. Os nomes legados mantêm os formulários nesta paleta.
abstract final class NaAreaColors {
  static const coral = Color(0xFF904D00);
  static const coralEscuro = Color(0xFF000000);
  static const laranja = Color(0xFF904D00);
  static const sol = Color(0xFFFFDCC3);
  static const areia = Color(0xFFFFF8F5);
  static const areiaEscura = Color(0xFFF0E6E0);
  static const azulMar = Color(0xFF006B62);
  static const azulMarEscuro = Color(0xFF005049);
  static const tinta = Color(0xFF1F1B17);
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ).copyWith(
          primary: Colors.black,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFE9E1DD),
          onPrimaryContainer: NaAreaColors.tinta,
          secondary: const Color(0xFF904D00),
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFFFDCC3),
          onSecondaryContainer: const Color(0xFF663500),
          tertiary: const Color(0xFF006B62),
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFD5F5EF),
          onTertiaryContainer: const Color(0xFF005049),
          surface: NaAreaColors.areia,
          onSurface: NaAreaColors.tinta,
          onSurfaceVariant: const Color(0xFF4D4540),
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFFCF2EB),
          surfaceContainer: const Color(0xFFF6ECE6),
          surfaceContainerHigh: const Color(0xFFF0E6E0),
          surfaceContainerHighest: const Color(0xFFEAE1DA),
          outline: const Color(0xFF7E7570),
          outlineVariant: const Color(0xFFD0C4BE),
          error: const Color(0xFFBA1A1A),
        );
    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Plus Jakarta Sans',
    ).textTheme;
    TextStyle heading(double size, double height) => TextStyle(
      fontFamily: 'Epilogue',
      fontSize: size,
      height: height / size,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.4,
      color: scheme.onSurface,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final text = base.copyWith(
      displayLarge: heading(36, 44),
      displayMedium: heading(32, 40),
      displaySmall: heading(28, 34),
      headlineLarge: heading(28, 34),
      headlineMedium: heading(24, 30),
      headlineSmall: heading(24, 30),
      titleLarge: heading(20, 26),
      titleMedium: base.titleMedium?.copyWith(
        fontSize: 17,
        fontWeight: FontWeight.w600,
      ),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 16, height: 1.5),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 14, height: 1.43),
      bodySmall: base.bodySmall?.copyWith(fontSize: 12, height: 1.33),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      fontFamily: 'Plus Jakarta Sans',
      scaffoldBackgroundColor: scheme.surface,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 20,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: Colors.white,
        surfaceTintColor: Colors.transparent,
        elevation: 1,
        shadowColor: const Color(0x161F1B17),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: const StadiumBorder(),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(minimumSize: const Size(48, 48)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        indicatorColor: scheme.secondaryContainer,
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.secondaryContainer,
        shape: const StadiumBorder(),
        side: BorderSide.none,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

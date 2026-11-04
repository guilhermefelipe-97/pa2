import 'package:flutter/material.dart';

abstract final class NaAreaColors {
  static const coral = Color(0xFF904D00);
  static const coralEscuro = Color(0xFF000000);
  static const laranja = Color(0xFF904D00);
  static const sol = Color(0xFFFFDCC3);
  static const areia = Color(0xFFFFF8F5);
  static const areiaEscura = Color(0xFFF6ECE6);
  static const azulMar = Color(0xFF0C9488);
  static const azulMarEscuro = Color(0xFF00201D);
  static const tinta = Color(0xFF1F1B17);
}

abstract final class AppTheme {
  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: NaAreaColors.coralEscuro,
          brightness: Brightness.light,
        ).copyWith(
          primary: NaAreaColors.coralEscuro,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFF1E1B19),
          onPrimaryContainer: Colors.white,
          secondary: NaAreaColors.coral,
          onSecondary: Colors.white,
          secondaryContainer: const Color(0xFFFFDCC3),
          onSecondaryContainer: const Color(0xFF663500),
          tertiary: NaAreaColors.azulMar,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFF00201D),
          onTertiaryContainer: const Color(0xFF0C9488),
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
        elevation: 0,
        shadowColor: const Color(0x161F1B17),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        backgroundColor: NaAreaColors.coralEscuro,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        height: 64,
        indicatorColor: Colors.transparent,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected)
                ? scheme.secondary
                : scheme.onSurface,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => text.labelSmall!.copyWith(
            color: states.contains(WidgetState.selected)
                ? scheme.secondary
                : scheme.onSurface,
          ),
        ),
        elevation: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(28),
          borderSide: BorderSide.none,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: scheme.surfaceContainer,
        selectedColor: scheme.primary,
        checkmarkColor: scheme.onPrimary,
        labelStyle: text.labelSmall!.copyWith(color: scheme.onSurface),
        secondaryLabelStyle: text.labelSmall!.copyWith(color: scheme.onPrimary),
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Paleta "pôr-do-sol potiguar": coral/laranja do céu de Ponta Negra, areia
/// das dunas e o azul do mar.
abstract final class NaAreaColors {
  static const coral = Color(0xFFFF6B4A);

  /// Coral mais fechado: cor primária (contraste com texto branco em botões).
  static const coralEscuro = Color(0xFFD9482B);
  static const laranja = Color(0xFFFF9F1C);
  static const sol = Color(0xFFFFC857);
  static const areia = Color(0xFFFFF4E6);
  static const areiaEscura = Color(0xFFF3E2CB);
  static const azulMar = Color(0xFF0E7C9B);

  /// Azul-mar fechado para texto sobre areia (contraste >= 4,5:1).
  static const azulMarEscuro = Color(0xFF0A6680);
  static const tinta = Color(0xFF2E211A);
}

abstract final class AppTheme {
  /// Modo claro. Títulos em Fredoka (arredondada, divertida), corpo em Nunito
  /// (legível). As fontes vêm do google_fonts em tempo de execução; sem rede,
  /// cai na fonte padrão do sistema.
  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: NaAreaColors.coral,
          brightness: Brightness.light,
        ).copyWith(
          primary: NaAreaColors.coralEscuro,
          onPrimary: Colors.white,
          primaryContainer: const Color(0xFFFFDAD0),
          onPrimaryContainer: const Color(0xFF3B0A00),
          secondary: NaAreaColors.laranja,
          onSecondary: NaAreaColors.tinta,
          secondaryContainer: const Color(0xFFFFE7C2),
          onSecondaryContainer: const Color(0xFF3A2400),
          tertiary: NaAreaColors.azulMarEscuro,
          onTertiary: Colors.white,
          tertiaryContainer: const Color(0xFFD3EEF5),
          onTertiaryContainer: const Color(0xFF00303D),
          surface: NaAreaColors.areia,
          onSurface: NaAreaColors.tinta,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: const Color(0xFFFFF9F2),
          surfaceContainer: const Color(0xFFFBEEDD),
          surfaceContainerHigh: NaAreaColors.areiaEscura,
        );

    final base = ThemeData(useMaterial3: true, colorScheme: scheme).textTheme;
    final body = GoogleFonts.nunitoTextTheme(
      base,
    ).apply(bodyColor: NaAreaColors.tinta, displayColor: NaAreaColors.tinta);
    TextStyle? title(TextStyle? s) =>
        GoogleFonts.fredoka(textStyle: s, fontWeight: FontWeight.w600);
    final text = body.copyWith(
      displayLarge: title(body.displayLarge),
      displayMedium: title(body.displayMedium),
      displaySmall: title(body.displaySmall),
      headlineLarge: title(body.headlineLarge),
      headlineMedium: title(body.headlineMedium),
      headlineSmall: title(body.headlineSmall),
      titleLarge: title(body.titleLarge),
      titleMedium: title(body.titleMedium),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      textTheme: text,
      scaffoldBackgroundColor: NaAreaColors.areia,
      appBarTheme: AppBarTheme(
        backgroundColor: NaAreaColors.areia,
        foregroundColor: NaAreaColors.tinta,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 2,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 3,
        shadowColor: NaAreaColors.tinta.withValues(alpha: 0.18),
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.only(bottom: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: NaAreaColors.coralEscuro,
        foregroundColor: Colors.white,
        shape: StadiumBorder(),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      ),
      chipTheme: ChipThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

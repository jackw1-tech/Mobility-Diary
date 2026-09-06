import 'package:flutter/material.dart';
import 'package:diary/theme/app_text_styles.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/theme/semantic_colors.dart';

/// Tema ispirato al design system Uber:
///  - duetto bianco/nero, nero `primary` come unico colore di conversione;
///  - la pillola (`borderRadiusPill`) come forma firma di ogni elemento
///    interattivo;
///  - card piatte (Level 0) con raggio 16px;
///  - input riempiti su canvas-soft;
///  - nav e scaffold su canvas bianco.
///
/// In dark mode il contrasto si inverte: sfondo quasi nero, testo bianco,
/// il bianco diventa il colore di conversione.
class AppTheme {
  static const StadiumBorder _pill = StadiumBorder();

  // ─────────────────────────────────────────────────────────────────────
  // LIGHT THEME
  // ─────────────────────────────────────────────────────────────────────

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: ColorPalette.primary,
      onPrimary: Colors.white,
      secondary: ColorPalette.primary,
      onSecondary: Colors.white,
      surface: ColorPalette.surface,
      onSurface: ColorPalette.textPrimary,
      onSurfaceVariant: ColorPalette.textSecondary,
      surfaceContainerHighest: ColorPalette.surfaceSoft,
      surfaceContainerHigh: ColorPalette.surfaceSofter,
      error: ColorPalette.error,
      onError: Colors.white,
      outline: ColorPalette.surfacePressed,
      outlineVariant: ColorPalette.hairline,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ColorPalette.background,
      textTheme: AppTextStyles.textTheme,
      extensions: const [SemanticColors.light],
      dividerTheme: const DividerThemeData(
        color: ColorPalette.hairline,
        thickness: 1,
        space: 1,
      ),

      // Nav bar Uber: canvas bianco, testo ink, piatta.
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorPalette.surface,
        foregroundColor: ColorPalette.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: Dimensions.appBarElevation,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: ColorPalette.textPrimary,
        ),
      ),

      // CTA primario: pillola nera.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ColorPalette.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingLarge,
            vertical: Dimensions.paddingSmall,
          ),
          shape: _pill,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ColorPalette.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingLarge,
            vertical: Dimensions.paddingSmall,
          ),
          shape: _pill,
        ),
      ),
      // CTA secondario: pillola bianca con bordo ink.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ColorPalette.textPrimary,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingLarge,
            vertical: Dimensions.paddingSmall,
          ),
          side: const BorderSide(color: ColorPalette.textPrimary),
          shape: _pill,
        ),
      ),
      // Azione terziaria: testo ink, comunque a pillola per il ripple.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ColorPalette.textPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingMedium,
            vertical: Dimensions.paddingSmall,
          ),
          shape: _pill,
        ),
      ),

      // Card canonica: piatta, raggio 16, bordo hairline.
      cardTheme: CardThemeData(
        color: ColorPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: Dimensions.cardElevation,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
          side: const BorderSide(color: ColorPalette.hairline),
        ),
      ),

      // Input riempito su canvas-soft, raggio 8, senza linea.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ColorPalette.surfaceSoft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Dimensions.paddingMedium,
          vertical: Dimensions.paddingMedium,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide: const BorderSide(color: ColorPalette.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide: const BorderSide(color: ColorPalette.error),
        ),
        labelStyle: const TextStyle(color: ColorPalette.textSecondary),
        hintStyle: const TextStyle(color: ColorPalette.textHint),
      ),

      // Chip / category-button: pillola su canvas-soft.
      chipTheme: ChipThemeData(
        backgroundColor: ColorPalette.surfaceSoft,
        labelStyle: AppTextStyles.button.copyWith(fontSize: 14),
        side: BorderSide.none,
        shape: _pill,
      ),

      // SnackBar / toast: ink nero, testo bianco. Ancorato in basso (fixed):
      // il comportamento floating puo' finire fuori schermo sopra la mappa a
      // tutto schermo e mandare in crash il layout (assert scaffold.dart).
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ColorPalette.primary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        ),
      ),

      // Drawer / dialog su canvas bianco.
      drawerTheme: const DrawerThemeData(
        backgroundColor: ColorPalette.surface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ColorPalette.surface,
        surfaceTintColor: Colors.transparent,
        elevation: Dimensions.dialogElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ColorPalette.primary,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ColorPalette.primary,
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────
  // DARK THEME — inversione contrasto Uber-style
  // ─────────────────────────────────────────────────────────────────────

  static ThemeData get darkTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.dark,
      primary: ColorPalette.darkPrimary,
      onPrimary: ColorPalette.darkSurface,
      secondary: ColorPalette.darkPrimary,
      onSecondary: ColorPalette.darkSurface,
      surface: ColorPalette.darkSurface,
      onSurface: ColorPalette.darkTextPrimary,
      onSurfaceVariant: ColorPalette.darkTextSecondary,
      surfaceContainerHighest: ColorPalette.darkSurfaceSoft,
      surfaceContainerHigh: ColorPalette.darkSurfaceSofter,
      error: ColorPalette.darkError,
      onError: Colors.black,
      outline: ColorPalette.darkSurfacePressed,
      outlineVariant: ColorPalette.darkHairline,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ColorPalette.darkBackground,
      textTheme: AppTextStyles.textTheme,
      extensions: const [SemanticColors.dark],
      dividerTheme: const DividerThemeData(
        color: ColorPalette.darkHairline,
        thickness: 1,
        space: 1,
      ),

      // Nav bar: sfondo scuro, testo bianco, piatta.
      appBarTheme: const AppBarTheme(
        backgroundColor: ColorPalette.darkSurface,
        foregroundColor: ColorPalette.darkTextPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: Dimensions.appBarElevation,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: 0,
          color: ColorPalette.darkTextPrimary,
        ),
      ),

      // CTA primario: pillola bianca.
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: ColorPalette.darkPrimary,
          foregroundColor: ColorPalette.darkSurface,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingLarge,
            vertical: Dimensions.paddingSmall,
          ),
          shape: _pill,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: ColorPalette.darkPrimary,
          foregroundColor: ColorPalette.darkSurface,
          elevation: 0,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingLarge,
            vertical: Dimensions.paddingSmall,
          ),
          shape: _pill,
        ),
      ),
      // CTA secondario: pillola scura con bordo bianco.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ColorPalette.darkTextPrimary,
          minimumSize: const Size(0, Dimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingLarge,
            vertical: Dimensions.paddingSmall,
          ),
          side: const BorderSide(color: ColorPalette.darkTextPrimary),
          shape: _pill,
        ),
      ),
      // Azione terziaria: testo bianco.
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: ColorPalette.darkTextPrimary,
          padding: const EdgeInsets.symmetric(
            horizontal: Dimensions.paddingMedium,
            vertical: Dimensions.paddingSmall,
          ),
          shape: _pill,
        ),
      ),

      // Card canonica: sfondo scuro, raggio 16, bordo hairline scuro.
      cardTheme: CardThemeData(
        color: ColorPalette.darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: Dimensions.cardElevation,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
          side: const BorderSide(color: ColorPalette.darkHairline),
        ),
      ),

      // Input riempito su surface-soft scuro.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: ColorPalette.darkSurfaceSoft,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Dimensions.paddingMedium,
          vertical: Dimensions.paddingMedium,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide:
              const BorderSide(color: ColorPalette.darkPrimary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
          borderSide: const BorderSide(color: ColorPalette.darkError),
        ),
        labelStyle: const TextStyle(color: ColorPalette.darkTextSecondary),
        hintStyle: const TextStyle(color: ColorPalette.darkTextHint),
      ),

      // Chip: pillola su surface-soft scuro.
      chipTheme: ChipThemeData(
        backgroundColor: ColorPalette.darkSurfaceSoft,
        labelStyle: AppTextStyles.button.copyWith(fontSize: 14),
        side: BorderSide.none,
        shape: _pill,
      ),

      // SnackBar: bianco su scuro.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ColorPalette.darkPrimary,
        contentTextStyle: const TextStyle(color: ColorPalette.darkSurface),
        behavior: SnackBarBehavior.fixed,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        ),
      ),

      // Drawer / dialog su surface scuro.
      drawerTheme: const DrawerThemeData(
        backgroundColor: ColorPalette.darkSurface,
        surfaceTintColor: Colors.transparent,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: ColorPalette.darkSurface,
        surfaceTintColor: Colors.transparent,
        elevation: Dimensions.dialogElevation,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        ),
      ),

      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: ColorPalette.darkPrimary,
        foregroundColor: ColorPalette.darkSurface,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: ColorPalette.darkPrimary,
      ),
    );
  }
}

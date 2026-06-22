import 'package:flutter/material.dart';
import 'package:diary/theme/app_text_styles.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/Dimensions.dart';

/// Tema ispirato al design system Uber:
///  - duetto bianco/nero, nero `primary` come unico colore di conversione;
///  - la pillola (`borderRadiusPill`) come forma firma di ogni elemento
///    interattivo;
///  - card piatte (Level 0) con raggio 16px;
///  - input riempiti su canvas-soft;
///  - nav e scaffold su canvas bianco.
class AppTheme {
  static const StadiumBorder _pill = StadiumBorder();

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme(
      brightness: Brightness.light,
      primary: ColorPalette.primary,
      onPrimary: Colors.white,
      secondary: ColorPalette.primary,
      onSecondary: Colors.white,
      surface: ColorPalette.surface,
      onSurface: ColorPalette.textPrimary,
      surfaceContainerHighest: ColorPalette.surfaceSoft,
      error: ColorPalette.error,
      onError: Colors.white,
      outline: ColorPalette.surfacePressed,
      outlineVariant: ColorPalette.hairline,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: ColorPalette.surface,
      textTheme: AppTextStyles.textTheme,
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

      // SnackBar / toast: ink nero, testo bianco, flottante.
      snackBarTheme: SnackBarThemeData(
        backgroundColor: ColorPalette.primary,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
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

  // Il brand Uber e' una sola voce bianco/nero: niente tema scuro dedicato,
  // si riusa quello chiaro per coerenza assoluta.
  static ThemeData get darkTheme => lightTheme;
}

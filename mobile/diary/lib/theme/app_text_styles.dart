import 'package:flutter/material.dart';
import 'package:diary/theme/color_palette.dart';

/// Tipografia ispirata a Uber: display in peso 700 (sentence-case), corpo in
/// 400/500, nessun letter-spacing decorativo. I font proprietari (UberMove /
/// UberMoveText) sono sostituiti dal sans di sistema; lo stile resta fedele
/// nella gerarchia di pesi e nel tracking neutro.
class AppTextStyles {
  // Display (UberMove 700, line-height stretto, tracking 0).
  static const TextStyle headline1 = TextStyle(
    fontSize: 32,
    fontWeight: FontWeight.w700,
    height: 40 / 32,
    letterSpacing: 0,
    color: ColorPalette.textPrimary,
  );

  static const TextStyle headline2 = TextStyle(
    fontSize: 24,
    fontWeight: FontWeight.w700,
    height: 32 / 24,
    letterSpacing: 0,
    color: ColorPalette.textPrimary,
  );

  // Corpo (UberMoveText 400/500).
  static const TextStyle body1 = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w400,
    height: 24 / 16,
    letterSpacing: 0,
    color: ColorPalette.textPrimary,
  );

  static const TextStyle body2 = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w400,
    height: 20 / 14,
    letterSpacing: 0,
    color: ColorPalette.textPrimary,
  );

  // Pulsanti: peso 500, mai 700, tracking neutro.
  static const TextStyle button = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w500,
    height: 20 / 16,
    letterSpacing: 0,
  );

  static TextTheme get textTheme {
    return const TextTheme(
      // display-xxl / display-xl / display-lg
      displayLarge: TextStyle(
        fontSize: 36,
        fontWeight: FontWeight.w700,
        height: 44 / 36,
        letterSpacing: 0,
        color: ColorPalette.textPrimary,
      ),
      displayMedium: headline1, // 32 / 700
      displaySmall: headline2, // 24 / 700
      // headline-* (titoli di sezione)
      headlineMedium: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        height: 32 / 24,
        letterSpacing: 0,
        color: ColorPalette.textPrimary,
      ),
      headlineSmall: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 28 / 20,
        letterSpacing: 0,
        color: ColorPalette.textPrimary,
      ),
      // title-* (display-sm / body-strong)
      titleLarge: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        height: 28 / 20,
        letterSpacing: 0,
        color: ColorPalette.textPrimary,
      ),
      titleMedium: TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w500,
        height: 20 / 16,
        letterSpacing: 0,
        color: ColorPalette.textPrimary,
      ),
      titleSmall: TextStyle(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        height: 16 / 14,
        letterSpacing: 0,
        color: ColorPalette.textPrimary,
      ),
      // body-*
      bodyLarge: body1, // 16 / 400
      bodyMedium: body2, // 14 / 400
      bodySmall: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w400,
        height: 20 / 12,
        letterSpacing: 0,
        color: ColorPalette.textSecondary,
      ),
      // label-* (chip / button)
      labelLarge: button,
      labelMedium: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        height: 16 / 12,
        letterSpacing: 0,
        color: ColorPalette.textPrimary,
      ),
    );
  }
}

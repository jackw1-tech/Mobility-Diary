import 'package:flutter/material.dart';
import 'package:diary/theme/color_palette.dart';

@immutable
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.success,
    required this.warning,
    required this.error,
    required this.info,
    required this.textHint,
    required this.surfaceSoft,
    required this.surfaceSofter,
    required this.surfacePressed,
    required this.hairline,
  });

  final Color success;
  final Color warning;
  final Color error;
  final Color info;
  final Color textHint;
  final Color surfaceSoft;
  final Color surfaceSofter;
  final Color surfacePressed;
  final Color hairline;

  static const light = SemanticColors(
    success: ColorPalette.success,
    warning: ColorPalette.warning,
    error: ColorPalette.error,
    info: ColorPalette.info,
    textHint: ColorPalette.textHint,
    surfaceSoft: ColorPalette.surfaceSoft,
    surfaceSofter: ColorPalette.surfaceSofter,
    surfacePressed: ColorPalette.surfacePressed,
    hairline: ColorPalette.hairline,
  );

  static const dark = SemanticColors(
    success: ColorPalette.darkSuccess,
    warning: ColorPalette.darkWarning,
    error: ColorPalette.darkError,
    info: ColorPalette.darkInfo,
    textHint: ColorPalette.darkTextHint,
    surfaceSoft: ColorPalette.darkSurfaceSoft,
    surfaceSofter: ColorPalette.darkSurfaceSofter,
    surfacePressed: ColorPalette.darkSurfacePressed,
    hairline: ColorPalette.darkHairline,
  );

  @override
  SemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? error,
    Color? info,
    Color? textHint,
    Color? surfaceSoft,
    Color? surfaceSofter,
    Color? surfacePressed,
    Color? hairline,
  }) {
    return SemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      error: error ?? this.error,
      info: info ?? this.info,
      textHint: textHint ?? this.textHint,
      surfaceSoft: surfaceSoft ?? this.surfaceSoft,
      surfaceSofter: surfaceSofter ?? this.surfaceSofter,
      surfacePressed: surfacePressed ?? this.surfacePressed,
      hairline: hairline ?? this.hairline,
    );
  }

  @override
  SemanticColors lerp(covariant SemanticColors? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      error: Color.lerp(error, other.error, t)!,
      info: Color.lerp(info, other.info, t)!,
      textHint: Color.lerp(textHint, other.textHint, t)!,
      surfaceSoft: Color.lerp(surfaceSoft, other.surfaceSoft, t)!,
      surfaceSofter: Color.lerp(surfaceSofter, other.surfaceSofter, t)!,
      surfacePressed: Color.lerp(surfacePressed, other.surfacePressed, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
    );
  }
}

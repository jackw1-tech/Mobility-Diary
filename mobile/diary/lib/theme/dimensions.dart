// ignore: file_names
class Dimensions {
  // Spacing — base 4px come la scala Uber.
  static const double paddingXSmall = 4.0;
  static const double paddingSmall = 8.0;
  static const double paddingMedium = 16.0;
  static const double paddingLarge = 24.0;
  static const double paddingXLarge = 32.0;

  // Border radius (scala Uber: md 8, lg 12, xl 16, pill 999).
  static const double borderRadiusSmall = 8.0; // input field (rounded.md)
  static const double borderRadiusMedium = 12.0; // card secondaria (rounded.lg)
  static const double borderRadiusLarge = 16.0; // card canonica (rounded.xl)
  static const double borderRadiusXLarge = 16.0;
  static const double borderRadiusPill = 999.0; // forma firma: la pillola

  // Elevations — Uber usa il piatto (Level 0) come default.
  static const double cardElevation = 0.0;
  static const double appBarElevation = 0.0;
  static const double dialogElevation = 0.0;

  // Sizes
  static const double iconSize = 24.0;
  static const double buttonHeight = 48.0;
  static const double buttonMinWidth = 120.0;
  static const double dividerHeight = 1.0;

  // Animation durations
  static const int animationDurationShort = 200; // milliseconds
  static const int animationDurationMedium = 300; // milliseconds
  static const int animationDurationLong = 500; // milliseconds
}

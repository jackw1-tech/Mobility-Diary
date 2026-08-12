import 'package:diary/theme/color_palette.dart';
import 'package:flutter/material.dart';

/// Maniglia grigia in cima ai bottom sheet trascinabili.
class SheetHandle extends StatelessWidget {
  const SheetHandle({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: ColorPalette.textSecondary.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

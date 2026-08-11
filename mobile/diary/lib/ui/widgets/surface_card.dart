import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';

/// Card generica con sfondo `surface`, bordo hairline, angoli arrotondati e
/// padding standard — pattern ripetuto identico in piu' pagine (home,
/// statistiche, dettaglio viaggio). Puramente di presentazione: nessuna
/// logica applicativa (Pine: layer UI).
class SurfaceCard extends StatelessWidget {
  final Widget child;
  final String? title;

  const SurfaceCard({required this.child, this.title, super.key});

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorPalette.surface,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        border: Border.all(color: ColorPalette.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: title == null
            ? child
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: Dimensions.paddingMedium),
                  child,
                ],
              ),
      ),
    );
  }
}

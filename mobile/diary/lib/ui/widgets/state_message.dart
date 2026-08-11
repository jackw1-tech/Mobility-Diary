import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';

/// Placeholder centrato per stati vuoti/errore di una pagina o sezione:
/// icona + testo + pulsante "Riprova" opzionale. Pattern ripetuto identico
/// in piu' pagine (Pine: solo UI, nessuna logica applicativa).
class StateMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  const StateMessage({
    required this.icon,
    required this.text,
    this.onRetry,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingLarge),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: ColorPalette.textSecondary),
            const SizedBox(height: Dimensions.paddingSmall),
            Text(text, textAlign: TextAlign.center),
            if (onRetry != null) ...[
              const SizedBox(height: Dimensions.paddingMedium),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh),
                label: const Text('Riprova'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

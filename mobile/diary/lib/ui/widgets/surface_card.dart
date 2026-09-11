import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';

class SurfaceCard extends StatelessWidget {
  final Widget child;
  final String? title;

  const SurfaceCard({required this.child, this.title, super.key});

  @override
  Widget build(BuildContext context) {
    final title = this.title;
    final sem = Theme.of(context).extension<SemanticColors>()!;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        border: Border.all(color: sem.hairline),
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
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: Dimensions.paddingMedium),
                  child,
                ],
              ),
      ),
    );
  }
}

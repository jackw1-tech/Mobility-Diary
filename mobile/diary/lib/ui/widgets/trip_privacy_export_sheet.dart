import 'dart:async';

import 'package:diary/model/entities/privacy/trip_privacy_export.dart';
import 'package:diary/repositories/trip_privacy_export_repository.dart';
import 'package:diary/state_management/cubits/trip_privacy_export_cubit/trip_privacy_export_cubit.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Apre il preview testuale dell'export privacy-aware del viaggio.
///
/// Il diario mobile normale resta privato e preciso: questo foglio usa la
/// Preferenza Privacy salvata e mostra l'anteprima prima di copiare/condividere.
Future<void> showTripPrivacyExportSheet(BuildContext context, int tripId) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    // Il repository va risolto dal context del BlocProvider (ancorato allo
    // stesso DependencyInjector), mai da un context esterno alla UI: la
    // schermata deve dipendere solo dal Cubit, mai direttamente dal Repository.
    builder: (_) => BlocProvider<TripPrivacyExportCubit>(
      create: (context) =>
          TripPrivacyExportCubit(context.read<TripPrivacyExportRepository>())
            ..load(tripId),
      child: TripPrivacyExportView(tripId: tripId),
    ),
  );
}

class TripPrivacyExportView extends StatelessWidget {
  final int tripId;

  const TripPrivacyExportView({required this.tripId, super.key});

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.85,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Dimensions.paddingMedium,
          0,
          Dimensions.paddingMedium,
          Dimensions.paddingMedium,
        ),
        child: BlocBuilder<TripPrivacyExportCubit, TripPrivacyExportState>(
          builder: (context, state) {
            switch (state.status) {
              case TripPrivacyExportStatus.initial:
              case TripPrivacyExportStatus.loading:
                return const Center(child: CircularProgressIndicator());
              case TripPrivacyExportStatus.error:
                return _ErrorView(
                  message: state.error ?? 'Export non disponibile',
                  onRetry: () =>
                      context.read<TripPrivacyExportCubit>().load(tripId),
                );
              case TripPrivacyExportStatus.ready:
                return _ReadyView(export: state.export!);
            }
          },
        ),
      ),
    );
  }
}

class _ReadyView extends StatelessWidget {
  final TripPrivacyExport export;

  const _ReadyView({required this.export});

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(Icons.ios_share, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: Dimensions.paddingSmall),
            Expanded(
              child: Text(
                'Export diario',
                style:
                    textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _ProtectionChip(isProtected: export.isProtected),
            IconButton(
              tooltip: 'Chiudi',
              onPressed: () => Navigator.of(context).maybePop(),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
        const SizedBox(height: Dimensions.paddingSmall),
        Text(
          'Livello privacy: ${export.level.label}',
          style: textTheme.bodyMedium,
        ),
        const SizedBox(height: Dimensions.paddingMedium),
        Expanded(
          child: DecoratedBox(
            decoration: BoxDecoration(
              color:
                  Theme.of(context).extension<SemanticColors>()!.surfaceSofter,
              borderRadius:
                  BorderRadius.circular(Dimensions.borderRadiusMedium),
              border: Border.all(
                  color:
                      Theme.of(context).extension<SemanticColors>()!.hairline),
            ),
            child: Scrollbar(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Dimensions.paddingMedium),
                child: SelectableText(
                  export.text,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    height: 1.4,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: Dimensions.paddingMedium),
        _CopyButton(text: export.text),
      ],
    );
  }
}

class _CopyButton extends StatefulWidget {
  final String text;

  const _CopyButton({required this.text});

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleCopy() async {
    await Clipboard.setData(ClipboardData(text: widget.text));
    if (!mounted) return;
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton(
      onPressed: _copied ? null : _handleCopy,
      child: _copied
          ? const Icon(Icons.check)
          : const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.copy),
                SizedBox(width: Dimensions.paddingSmall),
                Text('Copia'),
              ],
            ),
    );
  }
}

class _ProtectionChip extends StatelessWidget {
  final bool isProtected;

  const _ProtectionChip({required this.isProtected});

  @override
  Widget build(BuildContext context) {
    final sem = Theme.of(context).extension<SemanticColors>()!;
    final color = isProtected ? sem.success : sem.warning;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: Dimensions.paddingSmall,
        vertical: Dimensions.paddingXSmall,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusPill),
      ),
      child: Text(
        isProtected ? 'Protetto' : 'Non protetto',
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline,
              color: Theme.of(context).colorScheme.onSurfaceVariant, size: 40),
          const SizedBox(height: Dimensions.paddingSmall),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: Dimensions.paddingMedium),
          FilledButton(onPressed: onRetry, child: const Text('Riprova')),
        ],
      ),
    );
  }
}

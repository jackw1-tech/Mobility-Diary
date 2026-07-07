import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

Future<void> showPrivacyOnboardingDialog(BuildContext context) {
  // showDialog builds in the root overlay, outside the provider subtree, so we
  // forward the existing cubit explicitly.
  final cubit = context.read<PrivacySettingsCubit>();
  return showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => BlocProvider.value(
      value: cubit,
      child: const PrivacyOnboardingDialog(),
    ),
  );
}

class PrivacyOnboardingDialog extends StatefulWidget {
  const PrivacyOnboardingDialog({super.key});

  @override
  State<PrivacyOnboardingDialog> createState() =>
      _PrivacyOnboardingDialogState();
}

class _PrivacyOnboardingDialogState extends State<PrivacyOnboardingDialog> {
  late PrivacyLevel _selected =
      context.read<PrivacySettingsCubit>().state.level;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<PrivacySettingsCubit, PrivacySettingsState>(
      listenWhen: (previous, current) =>
          previous.isFirstLogin && !current.isFirstLogin,
      listener: (context, _) => Navigator.of(context).pop(),
      builder: (context, state) {
        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Imposta la tua privacy'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Scegli quanto precisi devono essere i tuoi dati di mobilita '
                  'nelle viste condivisibili. Potrai cambiarlo dal Profilo.',
                ),
                const SizedBox(height: Dimensions.paddingMedium),
                SegmentedButton<PrivacyLevel>(
                  showSelectedIcon: false,
                  segments: [
                    for (final level in PrivacyLevel.values)
                      ButtonSegment(
                        value: level,
                        icon: Icon(level.icon),
                        label: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(level.label),
                        ),
                      ),
                  ],
                  selected: {_selected},
                  onSelectionChanged: state.isSaving
                      ? null
                      : (selection) =>
                          setState(() => _selected = selection.first),
                ),
                if (state.isSaving) ...[
                  const SizedBox(height: Dimensions.paddingMedium),
                  const LinearProgressIndicator(),
                ],
                if (state.status == PrivacySettingsStatus.error)
                  Padding(
                    padding:
                        const EdgeInsets.only(top: Dimensions.paddingMedium),
                    child: Text(
                      state.error ?? 'Salvataggio non riuscito, riprova.',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
              ],
            ),
            actions: [
              FilledButton(
                onPressed: state.isSaving
                    ? null
                    : () =>
                        context.read<PrivacySettingsCubit>().save(_selected),
                child: const Text('Conferma'),
              ),
            ],
          ),
        );
      },
    );
  }
}

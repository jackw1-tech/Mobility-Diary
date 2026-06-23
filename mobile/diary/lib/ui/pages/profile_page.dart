import 'package:auto_route/auto_route.dart';
import 'package:diary/features/auth/domain/auth_user.dart';
import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit.dart';
import 'package:diary/state_management/cubits/auth_cubit/auth_cubit_state.dart';
import 'package:diary/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

@RoutePage()
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          PrivacySettingsCubit(context.read<PrivacySettingsService>())..load(),
      child: Scaffold(
        backgroundColor: ColorPalette.background,
        appBar: AppBar(title: const Text('Profilo')),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(Dimensions.paddingMedium),
            children: const [
              _UserSection(),
              SizedBox(height: Dimensions.paddingMedium),
              _PrivacySection(),
              SizedBox(height: Dimensions.paddingMedium),
              _LogoutButton(),
            ],
          ),
        ),
      ),
    );
  }
}

class _UserSection extends StatelessWidget {
  const _UserSection();

  @override
  Widget build(BuildContext context) {
    final user = context.select((AuthCubit cubit) => cubit.state.user);
    return _Section(
      children: [
        ListTile(
          leading: const Icon(Icons.person_outline),
          title: Text(_nameFor(user)),
          subtitle: const Text('Nome'),
        ),
        const Divider(height: 1),
        ListTile(
          leading: const Icon(Icons.mail_outline),
          title: Text(user?.email ?? ''),
          subtitle: const Text('Email'),
        ),
      ],
    );
  }

  String _nameFor(AuthUser? user) {
    final name = user?.displayName ?? '';
    return name.isEmpty ? 'Utente' : name;
  }
}

class _PrivacySection extends StatelessWidget {
  const _PrivacySection();

  @override
  Widget build(BuildContext context) {
    return _Section(
      padding: const EdgeInsets.all(Dimensions.paddingMedium),
      children: [
        Row(
          children: [
            const Icon(Icons.shield_outlined),
            const SizedBox(width: Dimensions.paddingSmall),
            Text(
              'Privacy',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ],
        ),
        const SizedBox(height: Dimensions.paddingMedium),
        BlocBuilder<PrivacySettingsCubit, PrivacySettingsState>(
          builder: (context, state) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (state.isLoading) const LinearProgressIndicator(),
                if (state.isLoading)
                  const SizedBox(height: Dimensions.paddingMedium),
                SegmentedButton<PrivacyLevel>(
                  showSelectedIcon: false,
                  segments: PrivacyLevel.values
                      .map(
                        (level) => ButtonSegment(
                          value: level,
                          icon: Icon(level.icon),
                          label: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(level.label),
                          ),
                        ),
                      )
                      .toList(growable: false),
                  selected: {state.level},
                  onSelectionChanged: state.canSelect
                      ? (selection) => context
                          .read<PrivacySettingsCubit>()
                          .save(selection.first)
                      : null,
                ),
                if (state.isSaving) ...[
                  const SizedBox(height: Dimensions.paddingMedium),
                  const LinearProgressIndicator(),
                ],
                if (state.error != null) ...[
                  const SizedBox(height: Dimensions.paddingMedium),
                  _InlineError(
                    message: state.error!,
                    onRetry: () => context.read<PrivacySettingsCubit>().load(),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}

class _InlineError extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _InlineError({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorPalette.error.withValues(alpha: 0.08),
        border: Border.all(color: ColorPalette.error.withValues(alpha: 0.3)),
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingSmall),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: ColorPalette.error),
            const SizedBox(width: Dimensions.paddingSmall),
            Expanded(child: Text(message)),
            IconButton(
              tooltip: 'Riprova',
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  const _LogoutButton();

  @override
  Widget build(BuildContext context) {
    final isBusy = context.select(
      (AuthCubit cubit) => cubit.state.status == AuthStatus.submitting,
    );
    return OutlinedButton.icon(
      onPressed: isBusy
          ? null
          : () async {
              await context.read<AuthCubit>().logout();
              if (context.mounted) {
                context.router.popUntilRoot();
              }
            },
      icon: isBusy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.logout),
      label: const Text('Logout'),
    );
  }
}

class _Section extends StatelessWidget {
  final List<Widget> children;
  final EdgeInsetsGeometry? padding;

  const _Section({
    required this.children,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: ColorPalette.surface,
      elevation: Dimensions.cardElevation,
      borderRadius: BorderRadius.circular(Dimensions.borderRadiusSmall),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

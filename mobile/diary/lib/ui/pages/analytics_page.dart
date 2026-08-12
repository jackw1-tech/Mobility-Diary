import 'package:auto_route/auto_route.dart';
import 'package:diary/repositories/analytics_repository.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit_state.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/widgets/analytics/analytics_atoms.dart';
import 'package:diary/ui/widgets/analytics/analytics_habits_content.dart';
import 'package:diary/ui/widgets/analytics/analytics_trend_section.dart';
import 'package:diary/ui/widgets/analytics/analytics_weekly_heatmaps.dart';
import 'package:diary/ui/widgets/state_message.dart';
import 'package:diary/ui/widgets/surface_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Analitiche Personali: andamento recente e abitudini di sempre dell'utente.
/// I dati arrivano aggregati da GET /mobility/analytics (user-scoped, ADR 0030).
@RoutePage()
class AnalyticsPage extends StatelessWidget {
  const AnalyticsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) =>
          AnalyticsCubit(context.read<AnalyticsRepository>())..load(),
      child: Scaffold(
        appBar: AppBar(centerTitle: true, title: const Text('Statistiche')),
        body: const SafeArea(child: _AnalyticsBody()),
      ),
    );
  }
}

class _AnalyticsBody extends StatelessWidget {
  const _AnalyticsBody();

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AnalyticsCubit, AnalyticsCubitState>(
      builder: (context, state) {
        switch (state.status) {
          case AnalyticsStatus.initial:
          case AnalyticsStatus.loading:
            return const Center(child: CircularProgressIndicator());
          case AnalyticsStatus.empty:
            return const StateMessage(
              icon: Icons.insights_outlined,
              text: 'Servono piu\' viaggi per calcolare le tue statistiche',
            );
          case AnalyticsStatus.error:
            return StateMessage(
              icon: Icons.error_outline,
              text: state.error ?? 'Errore nel caricamento',
              onRetry: () => context.read<AnalyticsCubit>().load(),
            );
          case AnalyticsStatus.ready:
            final weeklyHeatmaps = buildWeeklyHeatmaps(state.data!);
            final habits = buildAnalyticsHabits(state.data!);
            return RefreshIndicator(
              onRefresh: () => context.read<AnalyticsCubit>().load(),
              child: ListView(
                padding: const EdgeInsets.all(Dimensions.paddingMedium),
                children: [
                  _GranularityToggle(
                    value: state.granularity,
                    onChanged: (value) =>
                        context.read<AnalyticsCubit>().setGranularity(value),
                  ),
                  const SizedBox(height: Dimensions.paddingMedium),
                  AnalyticsTrendSection(
                    key: ValueKey(state.granularity),
                    data: state.data!,
                  ),
                  if (state.granularity == 'week') ...[
                    const SizedBox(height: Dimensions.paddingMedium),
                    SurfaceCard(
                      title: 'Luoghi piu\' frequentati',
                      child: weeklyHeatmaps.isEmpty
                          ? const AnalyticsSectionEmpty(
                              text:
                                  'Nessun luogo significativo ancora riconosciuto',
                            )
                          : AnalyticsWeeklyHeatmaps(weeks: weeklyHeatmaps),
                    ),
                  ],
                  const SizedBox(height: Dimensions.paddingMedium),
                  SurfaceCard(
                    title: 'Abitudini di sempre',
                    child: habits.isEmpty
                        ? const AnalyticsSectionEmpty(
                            text: 'Servono piu\' viaggi tra luoghi noti '
                                'per riconoscere le tue abitudini',
                          )
                        : AnalyticsHabitsContent(habits: habits),
                  ),
                ],
              ),
            );
        }
      },
    );
  }
}

class _GranularityToggle extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _GranularityToggle({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<String>(
      segments: const [
        ButtonSegment(value: 'day', label: Text('Giorno')),
        ButtonSegment(value: 'week', label: Text('Settimana')),
      ],
      selected: {value},
      showSelectedIcon: false,
      onSelectionChanged: (selected) => onChanged(selected.first),
    );
  }
}

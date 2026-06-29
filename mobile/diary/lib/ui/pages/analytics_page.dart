import 'package:auto_route/auto_route.dart';
import 'package:diary/network/service/analytics_service.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart'
    show formatDistance, formatDuration;
import 'package:diary/ui/widgets/analytics_heatmap_map.dart';
import 'package:fl_chart/fl_chart.dart';
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
          AnalyticsCubit(context.read<AnalyticsService>())..load(),
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
            return const _AnalyticsMessage(
              icon: Icons.insights_outlined,
              text: 'Servono piu\' viaggi per calcolare le tue statistiche',
            );
          case AnalyticsStatus.error:
            return _AnalyticsMessage(
              icon: Icons.error_outline,
              text: state.error ?? 'Errore nel caricamento',
              onRetry: () => context.read<AnalyticsCubit>().load(),
            );
          case AnalyticsStatus.ready:
            final trend = buildAnalyticsTrend(state.data!);
            final heatmap = buildAnalyticsHeatmap(state.data!);
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
                  _Section(
                    title: 'Tempo per attivita\'',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _TimeByCategoryChart(bars: trend.bars),
                        const SizedBox(height: Dimensions.paddingMedium),
                        const _CategoryLegend(),
                      ],
                    ),
                  ),
                  const SizedBox(height: Dimensions.paddingMedium),
                  _Section(
                    title: 'Distanze',
                    child: _DistancesContent(trend: trend),
                  ),
                  const SizedBox(height: Dimensions.paddingMedium),
                  _Section(
                    title: 'Luoghi piu\' frequentati',
                    child: heatmap.isEmpty
                        ? const _SectionEmpty(
                            text:
                                'Nessun luogo significativo ancora riconosciuto',
                          )
                        : SizedBox(
                            height: 220,
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(
                                Dimensions.borderRadiusMedium,
                              ),
                              child: AnalyticsHeatmapMap(heatmap: heatmap),
                            ),
                          ),
                  ),
                  const SizedBox(height: Dimensions.paddingMedium),
                  _Section(
                    title: 'Abitudini di sempre',
                    child: habits.isEmpty
                        ? const _SectionEmpty(
                            text: 'Servono piu\' viaggi tra luoghi noti '
                                'per riconoscere le tue abitudini',
                          )
                        : _HabitsContent(habits: habits),
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

class _TimeByCategoryChart extends StatelessWidget {
  final List<AnalyticsBar> bars;

  const _TimeByCategoryChart({required this.bars});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(),
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (value, _) => Padding(
                  padding: const EdgeInsets.only(top: Dimensions.paddingXSmall),
                  child: Text(
                    _labelAt(value.toInt()),
                    style: const TextStyle(
                      fontSize: 10,
                      color: ColorPalette.textSecondary,
                    ),
                  ),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(x: i, barRods: [_rod(bars[i])]),
          ],
        ),
      ),
    );
  }

  String _labelAt(int index) =>
      index >= 0 && index < bars.length ? bars[index].label : '';

  BarChartRodData _rod(AnalyticsBar bar) {
    final stack = <BarChartRodStackItem>[];
    var from = 0.0;
    for (var c = 0; c < kMobilityCategories.length; c++) {
      final minutes = bar.secondsByCategory[c] / 60.0;
      if (minutes <= 0) continue;
      stack.add(
        BarChartRodStackItem(from, from + minutes, kMobilityCategories[c].color),
      );
      from += minutes;
    }
    return BarChartRodData(
      toY: from,
      width: 14,
      color: Colors.transparent,
      rodStackItems: stack,
      borderRadius: BorderRadius.circular(2),
    );
  }
}

class _CategoryLegend extends StatelessWidget {
  const _CategoryLegend();

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: Dimensions.paddingMedium,
      runSpacing: Dimensions.paddingSmall,
      children: [
        for (final category in kMobilityCategories)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Dot(color: category.color),
              const SizedBox(width: Dimensions.paddingXSmall),
              Text(category.label, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  final Color color;

  const _Dot({required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }
}

class _DistancesContent extends StatelessWidget {
  final AnalyticsTrend trend;

  const _DistancesContent({required this.trend});

  @override
  Widget build(BuildContext context) {
    final withDistance =
        trend.categoryTotals.where((total) => total.distanceMeters > 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _DistanceRow(
          label: 'In movimento',
          value: trend.movementTime == Duration.zero
              ? '0 min'
              : formatDuration(trend.movementTime),
        ),
        _DistanceRow(
          label: 'Distanza totale',
          value: formatDistance(trend.totalDistanceMeters),
        ),
        if (withDistance.isNotEmpty) const Divider(height: Dimensions.paddingLarge),
        for (final total in withDistance)
          _DistanceRow(
            label: total.category.label,
            value: formatDistance(total.distanceMeters),
          ),
      ],
    );
  }
}

class _DistanceRow extends StatelessWidget {
  final String label;
  final String value;

  const _DistanceRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingXSmall),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HabitsContent extends StatelessWidget {
  final AnalyticsHabits habits;

  const _HabitsContent({required this.habits});

  @override
  Widget build(BuildContext context) {
    final prevalent = habits.prevalentMode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (prevalent != null)
          Padding(
            padding:
                const EdgeInsets.symmetric(vertical: Dimensions.paddingXSmall),
            child: Row(
              children: [
                _Dot(color: prevalent.color),
                const SizedBox(width: Dimensions.paddingSmall),
                Expanded(
                  child: Text(
                    'Modalita\' prevalente',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                Text(
                  prevalent.label,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        if (prevalent != null && habits.routes.isNotEmpty)
          const Divider(height: Dimensions.paddingLarge),
        for (final route in habits.routes)
          _DistanceRow(
            label: '${route.originLabel} → ${route.destinationLabel}',
            value: '×${route.tripCount}',
          ),
      ],
    );
  }
}

class _SectionEmpty extends StatelessWidget {
  final String text;

  const _SectionEmpty({required this.text});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context)
          .textTheme
          .bodyMedium
          ?.copyWith(color: ColorPalette.textSecondary),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final Widget child;

  const _Section({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: ColorPalette.surface,
        borderRadius: BorderRadius.circular(Dimensions.borderRadiusLarge),
        border: Border.all(color: ColorPalette.hairline),
      ),
      child: Padding(
        padding: const EdgeInsets.all(Dimensions.paddingMedium),
        child: Column(
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

class _AnalyticsMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final VoidCallback? onRetry;

  const _AnalyticsMessage({
    required this.icon,
    required this.text,
    this.onRetry,
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

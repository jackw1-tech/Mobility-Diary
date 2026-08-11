import 'package:auto_route/auto_route.dart';
import 'package:diary/model/entities/analytics/analytics.dart';
import 'package:diary/repositories/analytics_repository.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit.dart';
import 'package:diary/state_management/cubits/analytics_cubit/analytics_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart'
    show formatDistance, formatDuration;
import 'package:diary/ui/widgets/analytics_heatmap_map.dart';
import 'package:diary/ui/widgets/state_message.dart';
import 'package:diary/ui/widgets/surface_card.dart';
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
                  _TrendSection(
                    key: ValueKey(state.granularity),
                    data: state.data!,
                  ),
                  if (state.granularity == 'week') ...[
                    const SizedBox(height: Dimensions.paddingMedium),
                    SurfaceCard(
                      title: 'Luoghi piu\' frequentati',
                      child: weeklyHeatmaps.isEmpty
                          ? const _SectionEmpty(
                              text:
                                  'Nessun luogo significativo ancora riconosciuto',
                            )
                          : _WeeklyHeatmapsContent(weeks: weeklyHeatmaps),
                    ),
                  ],
                  const SizedBox(height: Dimensions.paddingMedium),
                  SurfaceCard(
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

/// Sezione "Tempo per attivita'": grafico selezionabile + legenda + dettaglio
/// del giorno/settimana selezionato (preselezionato sull'ultimo bucket = oggi
/// / settimana corrente). La selezione e' solo stato di UI: i dati di ogni
/// bucket sono gia' nel DTO, non serve richiamare il backend.
class _TrendSection extends StatefulWidget {
  final Analytics data;

  const _TrendSection({required this.data, super.key});

  @override
  State<_TrendSection> createState() => _TrendSectionState();
}

class _TrendSectionState extends State<_TrendSection> {
  late int _selected;
  late int _windowStart;

  @override
  void initState() {
    super.initState();
    _resetWindow();
  }

  @override
  void didUpdateWidget(covariant _TrendSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.data != widget.data) {
      _resetWindow();
    }
  }

  @override
  Widget build(BuildContext context) {
    final allBars = analyticsBars(widget.data);
    if (allBars.isEmpty) {
      return const SurfaceCard(
        title: 'Tempo per attivita\'',
        child: _SectionEmpty(text: 'Nessun dato in questa finestra'),
      );
    }
    final maxWindowStart = analyticsWindowMaxStart(allBars.length);
    final safeWindowStart = _windowStart.clamp(0, maxWindowStart);
    final visibleBars = analyticsWindow(allBars, safeWindowStart);
    final visibleBuckets =
        analyticsWindow(widget.data.buckets, safeWindowStart);
    final visibleEnd = safeWindowStart + visibleBars.length;
    final safeSelected = _selected.clamp(0, allBars.length - 1);
    final selected =
        safeSelected < safeWindowStart || safeSelected >= visibleEnd
            ? visibleEnd - 1
            : safeSelected;
    final bucket = widget.data.buckets[selected];
    final isCurrent = selected == allBars.length - 1;
    final showWindowSlider = analyticsNeedsWindowSlider(allBars.length);

    return SurfaceCard(
      title: 'Tempo per attivita\'',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _TimeByCategoryChart(
            bars: visibleBars,
            selectedIndex: selected - safeWindowStart,
            onSelect: (index) =>
                setState(() => _selected = safeWindowStart + index),
          ),
          if (showWindowSlider) ...[
            const SizedBox(height: Dimensions.paddingSmall),
            _BucketWindowSlider(
              granularity: widget.data.granularity,
              windowStart: safeWindowStart,
              maxWindowStart: maxWindowStart,
              firstLabel: visibleBuckets.first.label,
              lastLabel: visibleBuckets.last.label,
              onChanged: (start) {
                setState(() {
                  _windowStart = start;
                  final nextVisibleBars = analyticsWindow(allBars, start);
                  final nextVisibleEnd = start + nextVisibleBars.length;
                  if (_selected < start || _selected >= nextVisibleEnd) {
                    _selected = nextVisibleEnd - 1;
                  }
                });
              },
            ),
          ],
          const SizedBox(height: Dimensions.paddingMedium),
          const _CategoryLegend(),
          const Divider(height: Dimensions.paddingLarge),
          _BucketDetail(
            title:
                _detailTitle(widget.data.granularity, bucket.label, isCurrent),
            summary: summarizeBuckets([bucket]),
          ),
        ],
      ),
    );
  }

  String _detailTitle(String granularity, String label, bool isCurrent) {
    if (granularity == 'week') {
      return isCurrent ? 'Questa settimana' : 'Settimana del $label';
    }
    return isCurrent ? 'Oggi' : label;
  }

  void _resetWindow() {
    _selected =
        widget.data.buckets.isEmpty ? 0 : widget.data.buckets.length - 1;
    _windowStart = analyticsDefaultWindowStart(widget.data.buckets.length);
  }
}

class _BucketWindowSlider extends StatelessWidget {
  final String granularity;
  final int windowStart;
  final int maxWindowStart;
  final String firstLabel;
  final String lastLabel;
  final ValueChanged<int> onChanged;

  const _BucketWindowSlider({
    required this.granularity,
    required this.windowStart,
    required this.maxWindowStart,
    required this.firstLabel,
    required this.lastLabel,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final periodLabel =
        granularity == 'week' ? 'Settimane visibili' : 'Giorni visibili';
    final rangeLabel =
        firstLabel == lastLabel ? firstLabel : '$firstLabel - $lastLabel';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                periodLabel,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            const SizedBox(width: Dimensions.paddingSmall),
            Flexible(
              child: Text(
                rangeLabel,
                textAlign: TextAlign.end,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: ColorPalette.textSecondary,
                    ),
              ),
            ),
          ],
        ),
        Slider(
          value: windowStart.toDouble(),
          min: 0,
          max: maxWindowStart.toDouble(),
          divisions: maxWindowStart,
          label: rangeLabel,
          onChanged: (value) => onChanged(value.round()),
        ),
      ],
    );
  }
}

class _TimeByCategoryChart extends StatelessWidget {
  final List<AnalyticsBar> bars;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const _TimeByCategoryChart({
    required this.bars,
    required this.selectedIndex,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final trackTop = _trackTop();
    return SizedBox(
      height: 200,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          borderData: FlBorderData(show: false),
          gridData: const FlGridData(show: false),
          barTouchData: BarTouchData(
            enabled: true,
            handleBuiltInTouches: false,
            // La traccia di sfondo a piena altezza rende l'intera colonna
            // toccabile, anche i giorni senza attivita'.
            allowTouchBarBackDraw: true,
            touchExtraThreshold:
                const EdgeInsets.symmetric(horizontal: Dimensions.paddingSmall),
            touchCallback: (event, response) {
              if (event is FlTapUpEvent && response?.spot != null) {
                onSelect(response!.spot!.touchedBarGroupIndex);
              }
            },
          ),
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
                    style: TextStyle(
                      fontSize: 10,
                      color: value.toInt() == selectedIndex
                          ? ColorPalette.textPrimary
                          : ColorPalette.textSecondary,
                      fontWeight: value.toInt() == selectedIndex
                          ? FontWeight.w700
                          : FontWeight.normal,
                    ),
                  ),
                ),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < bars.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  _rod(bars[i], dimmed: i != selectedIndex, trackTop: trackTop),
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _labelAt(int index) =>
      index >= 0 && index < bars.length ? bars[index].label : '';

  double _barMinutes(AnalyticsBar bar) =>
      bar.secondsByCategory.fold<double>(0, (sum, s) => sum + s) / 60.0;

  double _trackTop() {
    final maxMinutes = bars.fold<double>(0, (m, b) {
      final total = _barMinutes(b);
      return total > m ? total : m;
    });
    return maxMinutes <= 0 ? 1.0 : maxMinutes;
  }

  BarChartRodData _rod(
    AnalyticsBar bar, {
    required bool dimmed,
    required double trackTop,
  }) {
    final stack = <BarChartRodStackItem>[];
    var from = 0.0;
    for (var c = 0; c < kMobilityCategories.length; c++) {
      final minutes = bar.secondsByCategory[c] / 60.0;
      if (minutes <= 0) continue;
      final color = kMobilityCategories[c].color;
      stack.add(BarChartRodStackItem(
        from,
        from + minutes,
        dimmed ? color.withValues(alpha: 0.30) : color,
      ));
      from += minutes;
    }
    return BarChartRodData(
      toY: from,
      width: 14,
      color: Colors.transparent,
      rodStackItems: stack,
      borderRadius: BorderRadius.circular(2),
      backDrawRodData: BackgroundBarChartRodData(
        show: true,
        toY: trackTop,
        color:
            dimmed ? ColorPalette.surfaceSofter : ColorPalette.surfacePressed,
      ),
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
              Text(category.label,
                  style: Theme.of(context).textTheme.bodySmall),
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

/// Statistiche del singolo giorno/settimana selezionato nel grafico.
class _BucketDetail extends StatelessWidget {
  final String title;
  final AnalyticsSummary summary;

  const _BucketDetail({required this.title, required this.summary});

  @override
  Widget build(BuildContext context) {
    final active =
        summary.categoryTotals.where((total) => total.time > Duration.zero);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: Dimensions.paddingXSmall),
        _DistanceRow(
          label: 'In movimento',
          value: summary.movementTime == Duration.zero
              ? '0 min'
              : formatDuration(summary.movementTime),
        ),
        _DistanceRow(
          label: 'Distanza',
          value: formatDistance(summary.totalDistanceMeters),
        ),
        if (active.isNotEmpty) const Divider(height: Dimensions.paddingLarge),
        for (final total in active)
          _DotStatRow(
            color: total.category.color,
            label: total.category.label,
            value: formatDuration(total.time),
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

/// Riga con pallino di categoria a sinistra e valore in grassetto a destra.
class _DotStatRow extends StatelessWidget {
  final Color color;
  final String label;
  final String value;

  const _DotStatRow({
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Dimensions.paddingXSmall),
      child: Row(
        children: [
          _Dot(color: color),
          const SizedBox(width: Dimensions.paddingSmall),
          Expanded(
            child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
          ),
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

class _WeeklyHeatmapsContent extends StatelessWidget {
  final List<AnalyticsWeeklyHeatmapViewModel> weeks;

  const _WeeklyHeatmapsContent({required this.weeks});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (var i = 0; i < weeks.length; i++) ...[
          _WeeklyHeatmapCard(week: weeks[i]),
          if (i != weeks.length - 1)
            const Divider(height: Dimensions.paddingLarge),
        ],
      ],
    );
  }
}

class _WeeklyHeatmapCard extends StatelessWidget {
  final AnalyticsWeeklyHeatmapViewModel week;

  const _WeeklyHeatmapCard({required this.week});

  @override
  Widget build(BuildContext context) {
    final heatmap = week.heatmap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Settimana del ${week.label}',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: Dimensions.paddingXSmall),
        const SizedBox(height: Dimensions.paddingSmall),
        if (heatmap.isEmpty)
          const _SectionEmpty(
            text:
                'Nessun habitual place associato ai viaggi di questa settimana',
          )
        else
          SizedBox(
            height: 220,
            child: ClipRRect(
              borderRadius:
                  BorderRadius.circular(Dimensions.borderRadiusMedium),
              child: AnalyticsHeatmapMap(
                heatmap: heatmap,
                onTap: () => _openHeatmap(context),
              ),
            ),
          ),
      ],
    );
  }

  void _openHeatmap(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => AnalyticsHeatmapMapPage(
          title: 'Settimana del ${week.label}',
          heatmap: week.heatmap,
        ),
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
          _DotStatRow(
            color: prevalent.color,
            label: 'Modalita\' prevalente',
            value: prevalent.label,
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


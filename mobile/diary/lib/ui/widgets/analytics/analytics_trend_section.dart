import 'package:diary/model/entities/analytics/analytics.dart';

import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/analytics_presenter.dart';
import 'package:diary/ui/widgets/analytics/analytics_atoms.dart';
import 'package:diary/ui/widgets/analytics/analytics_bucket_detail.dart';
import 'package:diary/ui/widgets/analytics/time_by_category_chart.dart';
import 'package:diary/ui/widgets/surface_card.dart';
import 'package:flutter/material.dart';

class AnalyticsTrendSection extends StatefulWidget {
  final Analytics data;

  const AnalyticsTrendSection({required this.data, super.key});

  @override
  State<AnalyticsTrendSection> createState() => _AnalyticsTrendSectionState();
}

class _AnalyticsTrendSectionState extends State<AnalyticsTrendSection> {
  late int _selected;
  late int _windowStart;

  @override
  void initState() {
    super.initState();
    _resetWindow();
  }

  @override
  void didUpdateWidget(covariant AnalyticsTrendSection oldWidget) {
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
        child: AnalyticsSectionEmpty(text: 'Nessun dato in questa finestra'),
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
          TimeByCategoryChart(
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
          const AnalyticsCategoryLegend(),
          const Divider(height: Dimensions.paddingLarge),
          AnalyticsBucketDetail(
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
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
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

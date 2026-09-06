import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/widgets/surface_card.dart';
import 'package:flutter/material.dart';

/// Riga di metriche live (sigma e velocita') mostrata sotto l'intestazione del
/// bottom sheet della home.
class CoreMetrics extends StatefulWidget {
  final AcquisitionCubitState state;

  const CoreMetrics({required this.state, super.key});

  @override
  State<CoreMetrics> createState() => _CoreMetricsState();
}

class _CoreMetricsState extends State<CoreMetrics> {
  DateTime? _sigmaAt;
  DateTime? _speedAt;
  DateTime? _rawAccelerometerAt;
  Duration? _sigmaInterval;
  Duration? _speedInterval;
  Duration? _rawAccelerometerInterval;

  @override
  void initState() {
    super.initState();
    _registerUpdates(widget.state);
  }

  @override
  void didUpdateWidget(CoreMetrics oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.state.isTracking) {
      _resetCounters();
    } else {
      _registerUpdates(widget.state);
    }
  }

  void _registerUpdates(AcquisitionCubitState state) {
    final sigmaAt = state.snapshot.latestSigmaAt;
    if (sigmaAt != null && sigmaAt != _sigmaAt) {
      _sigmaInterval = _intervalBetween(_sigmaAt, sigmaAt);
      _sigmaAt = sigmaAt;
    }

    final speedAt = state.snapshot.latestSpeedAt;
    if (speedAt != null && speedAt != _speedAt) {
      _speedInterval = _intervalBetween(_speedAt, speedAt);
      _speedAt = speedAt;
    }

    final rawAt = state.snapshot.latestRawAccelerometerEventAt;
    if (rawAt != null && rawAt != _rawAccelerometerAt) {
      _rawAccelerometerInterval = _intervalBetween(_rawAccelerometerAt, rawAt);
      _rawAccelerometerAt = rawAt;
    }
  }

  Duration? _intervalBetween(DateTime? previous, DateTime current) {
    if (previous == null) return null;
    final interval = current.difference(previous);
    return interval.isNegative ? Duration.zero : interval;
  }

  void _resetCounters() {
    _sigmaAt = null;
    _speedAt = null;
    _rawAccelerometerAt = null;
    _sigmaInterval = null;
    _speedInterval = null;
    _rawAccelerometerInterval = null;
  }

  @override
  Widget build(BuildContext context) {
    final state = widget.state;
    final speedKmh = state.latestSpeedMetersPerSecond * 3.6;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Row(
      children: [
        Expanded(
          child: _MetricColumn(
            metric: _MetricTile(
              icon: Icons.speed,
              label: 'Sigma',
              value: state.latestSigma.toStringAsFixed(2),
              color: primaryColor,
              updatedAt: state.snapshot.latestSigmaAt,
            ),
            interval: _sigmaInterval,
            count: state.snapshot.completedSigmaWindowCount,
            countLabel: 'finestre',
          ),
        ),
        const SizedBox(width: Dimensions.paddingSmall),
        Expanded(
          child: _MetricColumn(
            metric: _MetricTile(
              icon: Icons.explore,
              label: 'Velocita',
              value: '${speedKmh.toStringAsFixed(1)} km/h',
              color: primaryColor,
              updatedAt: state.snapshot.latestSpeedAt,
            ),
            interval: _speedInterval,
            count: state.snapshot.gpsFixCount,
            countLabel: 'valori',
          ),
        ),
        const SizedBox(width: Dimensions.paddingSmall),
        Expanded(
          child: _MetricColumn(
            metric: _MetricTile(
              icon: Icons.vibration,
              label: 'Accel. grezzo',
              value: '${state.snapshot.rawAccelerometerEventCount}',
              color: primaryColor,
              updatedAt: state.snapshot.latestRawAccelerometerEventAt,
            ),
            interval: _rawAccelerometerInterval,
            count: state.snapshot.rawAccelerometerEventCount,
            countLabel: 'campioni',
          ),
        ),
      ],
    );
  }
}

class _MetricColumn extends StatelessWidget {
  final Widget metric;
  final Duration? interval;
  final int count;
  final String countLabel;

  const _MetricColumn({
    required this.metric,
    required this.interval,
    required this.count,
    required this.countLabel,
  });

  @override
  Widget build(BuildContext context) {
    final seconds = interval == null
        ? '--'
        : (interval!.inMilliseconds / 1000).toStringAsFixed(1);
    return Column(
      children: [
        metric,
        const SizedBox(height: Dimensions.paddingSmall),
        SurfaceCard(
          child: Row(
            children: [
              Expanded(
                  child: Text('Δ ${seconds}s', textAlign: TextAlign.center)),
              Expanded(
                child: Tooltip(
                  message: countLabel,
                  child: Text('# $count', textAlign: TextAlign.center),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final DateTime? updatedAt;

  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.updatedAt,
  });

  @override
  Widget build(BuildContext context) {
    return SurfaceCard(
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: Dimensions.paddingSmall),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                TweenAnimationBuilder<double>(
                  key: ValueKey(updatedAt),
                  tween: Tween(begin: updatedAt == null ? 1 : 0, end: 1),
                  duration: const Duration(milliseconds: 650),
                  builder: (context, progress, child) => Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Color.lerp(
                            Theme.of(context).colorScheme.tertiary,
                            Theme.of(context).colorScheme.onSurface,
                            progress,
                          ),
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

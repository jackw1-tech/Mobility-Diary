import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/color_palette.dart';
import 'package:diary/theme/dimensions.dart';
import 'package:diary/ui/pages/trip_diary_presenter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripDiaryTab extends StatelessWidget {
  const TripDiaryTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripTrackCubit, TripTrackCubitState>(
      builder: (context, state) {
        final message = _stateMessage(state, pending: 'Diario in analisi');
        if (message != null) return message;
        final segments = presentableDiarySegments(state.diarySegments);
        if (segments.isEmpty) {
          return _message(Icons.timeline, 'Nessun segmento');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(Dimensions.paddingMedium),
          itemBuilder: (context, index) => _segmentTile(segments[index]),
          separatorBuilder: (_, __) =>
              const SizedBox(height: Dimensions.paddingSmall),
          itemCount: segments.length,
        );
      },
    );
  }
}

class TripStatsTab extends StatelessWidget {
  const TripStatsTab({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<TripTrackCubit, TripTrackCubitState>(
      builder: (context, state) {
        final message = _stateMessage(state, pending: 'Statistiche in analisi');
        if (message != null) return message;
        final stats = TripStats.fromSegments(state.diarySegments);
        if (stats.isEmpty) {
          return _message(Icons.bar_chart, 'Nessuna statistica');
        }
        return ListView(
          padding: const EdgeInsets.all(Dimensions.paddingMedium),
          children: [
            GridView.count(
              crossAxisCount: 2,
              childAspectRatio: 1.55,
              crossAxisSpacing: Dimensions.paddingSmall,
              mainAxisSpacing: Dimensions.paddingSmall,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _metricCard(context, Icons.timer, 'Durata',
                    formatDuration(stats.duration)),
                _metricCard(context, Icons.route, 'Distanza',
                    formatDistance(stats.distanceMeters)),
                _metricCard(context, Icons.directions_walk, 'Movimento',
                    formatDuration(stats.moving)),
                _metricCard(
                  context,
                  Icons.place,
                  'Soste',
                  stopSummaryText(stats),
                ),
              ],
            ),
            const SizedBox(height: Dimensions.paddingMedium),
            for (final activity in stats.activities)
              _activityBar(activity, stats.activities.first.duration),
          ],
        );
      },
    );
  }
}

Widget? _stateMessage(TripTrackCubitState state, {required String pending}) {
  switch (state.status) {
    case TripTrackStatus.initial:
    case TripTrackStatus.loading:
      return const Center(child: CircularProgressIndicator());
    case TripTrackStatus.error:
      return _message(Icons.error_outline, state.error ?? 'Errore');
    case TripTrackStatus.empty:
    case TripTrackStatus.loaded:
      if (state.enrichmentFailed) {
        return _message(
          Icons.error_outline,
          state.enrichmentErrorMessage ??
              'Diario non disponibile per questo viaggio.',
        );
      }
      return state.enrichmentPending
          ? _message(Icons.auto_awesome, pending)
          : null;
  }
}

Widget _segmentTile(TripDiarySegmentDto segment) {
  final isMove = !isStopLikeSegment(segment);
  final details = [
    formatTimeRange(segment),
    formatDuration(segmentDuration(segment)),
    if (isMove && segment.distanceMeters > 0)
      formatDistance(segment.distanceMeters),
  ].join(' · ');

  return DecoratedBox(
    decoration: _boxDecoration(),
    child: ListTile(
      leading: Icon(isMove ? Icons.directions : Icons.pause_circle_outline),
      title: Text(segmentTitle(segment)),
      subtitle: Text(details),
    ),
  );
}

Widget _metricCard(
  BuildContext context,
  IconData icon,
  String label,
  String value,
) {
  return DecoratedBox(
    decoration: _boxDecoration(),
    child: Padding(
      padding: const EdgeInsets.all(Dimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: ColorPalette.primary),
          const Spacer(),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

Widget _activityBar(
    ({String label, Duration duration}) activity, Duration max) {
  final value =
      max.inSeconds == 0 ? 0.0 : activity.duration.inSeconds / max.inSeconds;
  return Padding(
    padding: const EdgeInsets.only(bottom: Dimensions.paddingSmall),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(activityLabelText(activity.label))),
            Text(formatDuration(activity.duration)),
          ],
        ),
        const SizedBox(height: 4),
        LinearProgressIndicator(value: value.clamp(0, 1).toDouble()),
      ],
    ),
  );
}

Widget _message(IconData icon, String text) {
  return Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: ColorPalette.textSecondary, size: 40),
        const SizedBox(height: Dimensions.paddingSmall),
        Text(text, textAlign: TextAlign.center),
      ],
    ),
  );
}

BoxDecoration _boxDecoration() {
  return BoxDecoration(
    color: ColorPalette.surface,
    borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
    border: Border.all(color: ColorPalette.hairline),
  );
}

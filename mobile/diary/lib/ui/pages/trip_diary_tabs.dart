import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:diary/theme/semantic_colors.dart';
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
        final message = _stateMessage(
          context,
          state,
          pending: 'Diario in analisi',
        );
        if (message != null) return message;
        final segments = state.diarySegments;
        if (segments.isEmpty) {
          return _message(context, Icons.timeline, 'Nessun segmento');
        }
        return ListView.separated(
          padding: const EdgeInsets.all(Dimensions.paddingMedium),
          itemBuilder: (context, index) =>
              _segmentTile(context, segments[index]),
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
        final message = _stateMessage(
          context,
          state,
          pending: 'Statistiche in analisi',
        );
        if (message != null) return message;
        final stats = TripStats.fromSegments(state.diarySegments);
        if (stats.isEmpty) {
          return _message(context, Icons.bar_chart, 'Nessuna statistica');
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
                _metricCard(
                  context,
                  Icons.timer,
                  'Durata',
                  formatDuration(stats.duration),
                ),
                _metricCard(
                  context,
                  Icons.route,
                  'Distanza',
                  formatDistance(stats.distanceMeters),
                ),
                _metricCard(
                  context,
                  Icons.directions_walk,
                  'Movimento',
                  formatDuration(stats.moving),
                ),
                _metricCard(
                  context,
                  Icons.place,
                  'Soste',
                  stopStatsText(stats),
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

Widget? _stateMessage(
  BuildContext context,
  TripTrackCubitState state, {
  required String pending,
}) {
  switch (state.diaryStatus) {
    case DiaryLoadStatus.initial:
    case DiaryLoadStatus.loading:
      return const Center(child: CircularProgressIndicator());
    case DiaryLoadStatus.pending:
      return _message(context, Icons.auto_awesome, pending);
    case DiaryLoadStatus.failed:
      // Solo l'arricchimento fallito e' definitivo: un errore di trasporto
      // viene gia' ritentato da solo, e l'utente puo' forzarlo subito.
      if (state.processingFailed) {
        return _message(
          context,
          Icons.error_outline,
          state.processingErrorMessage ??
              'Diario non disponibile per questo viaggio.',
        );
      }
      return _message(
        context,
        Icons.wifi_off_outlined,
        state.diaryError ?? 'Diario non raggiungibile.',
        action: TextButton.icon(
          onPressed: () => context.read<TripTrackCubit>().retryDiaryNow(),
          icon: const Icon(Icons.refresh),
          label: const Text('Riprova'),
        ),
        hint: state.diaryRetryPending ? 'Nuovo tentativo in corso...' : null,
      );
    case DiaryLoadStatus.loaded:
      return null;
  }
}

Widget _segmentTile(BuildContext context, TripDiarySegment segment) {
  final isMove = !isStopSegment(segment);
  final details = [
    formatTimeRange(segment),
    formatDuration(segmentDuration(segment)),
    if (isMove && segment.distanceMeters > 0)
      formatDistance(segment.distanceMeters),
  ].join(' · ');

  return DecoratedBox(
    decoration: _boxDecoration(context),
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
    decoration: _boxDecoration(context),
    child: Padding(
      padding: const EdgeInsets.all(Dimensions.paddingMedium),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Theme.of(context).colorScheme.primary),
          const Spacer(),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    ),
  );
}

Widget _activityBar(
  ({String label, Duration duration}) activity,
  Duration max,
) {
  final value = max.inSeconds == 0
      ? 0.0
      : activity.duration.inSeconds / max.inSeconds;
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

Widget _message(
  BuildContext context,
  IconData icon,
  String text, {
  Widget? action,
  String? hint,
}) {
  final onSurfaceVariant = Theme.of(context).colorScheme.onSurfaceVariant;
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(Dimensions.paddingMedium),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: onSurfaceVariant, size: 40),
          const SizedBox(height: Dimensions.paddingSmall),
          Text(text, textAlign: TextAlign.center),
          if (hint != null) ...[
            const SizedBox(height: Dimensions.paddingSmall),
            Text(
              hint,
              textAlign: TextAlign.center,
              style: TextStyle(color: onSurfaceVariant),
            ),
          ],
          if (action != null) ...[
            const SizedBox(height: Dimensions.paddingSmall),
            action,
          ],
        ],
      ),
    ),
  );
}

BoxDecoration _boxDecoration(BuildContext context) {
  final sem = Theme.of(context).extension<SemanticColors>()!;
  return BoxDecoration(
    color: Theme.of(context).colorScheme.surface,
    borderRadius: BorderRadius.circular(Dimensions.borderRadiusMedium),
    border: Border.all(color: sem.hairline),
  );
}

import 'package:diary/network/dto/trip_track_dto.dart';

class TripStats {
  final Duration duration;
  final Duration moving;
  final Duration stopped;
  final double distanceMeters;
  final int places;
  final List<({String label, Duration duration})> activities;

  const TripStats(
    this.duration,
    this.moving,
    this.stopped,
    this.distanceMeters,
    this.places,
    this.activities,
  );

  factory TripStats.fromSegments(List<TripDiarySegmentDto> segments) {
    if (segments.isEmpty) {
      return const TripStats(
        Duration.zero,
        Duration.zero,
        Duration.zero,
        0,
        0,
        [],
      );
    }

    final ordered = [...segments]
      ..sort((a, b) => a.startTimestamp.compareTo(b.startTimestamp));
    final activitySeconds = <String, int>{};
    final placeIds = <int>{};
    var movingSeconds = 0;
    var stoppedSeconds = 0;
    var distance = 0.0;

    for (final segment in ordered) {
      final seconds = segmentDuration(segment).inSeconds;
      if (segment.kind == 'MOVE') {
        movingSeconds += seconds;
        distance += segment.distanceMeters;
        activitySeconds.update(
          segment.activityLabel,
          (value) => value + seconds,
          ifAbsent: () => seconds,
        );
      } else {
        stoppedSeconds += seconds;
        final place = segment.place;
        if (place != null) placeIds.add(place.id);
      }
    }

    final activities = activitySeconds.entries
        .map((entry) =>
            (label: entry.key, duration: Duration(seconds: entry.value)))
        .toList()
      ..sort((a, b) => b.duration.compareTo(a.duration));

    return TripStats(
      ordered.last.endTimestamp.difference(ordered.first.startTimestamp),
      Duration(seconds: movingSeconds),
      Duration(seconds: stoppedSeconds),
      distance,
      placeIds.length,
      activities,
    );
  }

  bool get isEmpty => duration == Duration.zero && activities.isEmpty;
}

const _activityLabels = {
  'WALKING': 'A piedi',
  'RUNNING': 'Corsa',
  'BIKING': 'Bici',
  'MOVING_VEHICLE': 'Veicolo',
  'IDLE': 'Sosta',
};

String activityLabelText(String label) => _activityLabels[label] ?? label;

String segmentTitle(TripDiarySegmentDto segment) {
  if (segment.kind == 'STOP') {
    final label = segment.place?.label;
    return label == null || label.isEmpty ? 'Sosta rilevata' : label;
  }
  return activityLabelText(segment.activityLabel);
}

Duration segmentDuration(TripDiarySegmentDto segment) {
  final duration = segment.endTimestamp.difference(segment.startTimestamp);
  return duration.isNegative ? Duration.zero : duration;
}

String formatDistance(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(2)} km';
  return '${meters.round()} m';
}

String formatDuration(Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes < 60) return '${minutes == 0 ? 1 : minutes} min';
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  return rest == 0
      ? '$hours h'
      : '$hours h ${rest.toString().padLeft(2, '0')} min';
}

String formatTimeRange(TripDiarySegmentDto segment) {
  return '${_clock(segment.startTimestamp)} - ${_clock(segment.endTimestamp)}';
}

String _clock(DateTime time) {
  final local = time.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

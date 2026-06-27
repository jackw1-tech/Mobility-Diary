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
    final presentable = presentableDiarySegments(segments);
    if (presentable.isEmpty) {
      return const TripStats(
        Duration.zero,
        Duration.zero,
        Duration.zero,
        0,
        0,
        [],
      );
    }

    final activitySeconds = <String, int>{};
    final placeIds = <int>{};
    var movingSeconds = 0;
    var stoppedSeconds = 0;
    var distance = 0.0;

    for (final segment in presentable) {
      final seconds = segmentDuration(segment).inSeconds;
      if (!isStopLikeSegment(segment)) {
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
      presentable.last.endTimestamp
          .difference(presentable.first.startTimestamp),
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

bool isStopLikeSegment(TripDiarySegmentDto segment) {
  return segment.kind == 'STOP' || segment.activityLabel == 'IDLE';
}

List<TripDiarySegmentDto> presentableDiarySegments(
  List<TripDiarySegmentDto> segments,
) {
  final ordered = [...segments]
    ..sort((a, b) => a.startTimestamp.compareTo(b.startTimestamp));
  final projected = <TripDiarySegmentDto>[];
  TripDiarySegmentDto? pendingStop;

  for (final segment in ordered) {
    if (isStopLikeSegment(segment)) {
      final stopProjection = _asStopSegment(segment);
      if (pendingStop == null) {
        pendingStop = stopProjection;
        continue;
      }
      if (!stopProjection.startTimestamp.isAfter(pendingStop.endTimestamp)) {
        pendingStop = TripDiarySegmentDto(
          kind: 'STOP',
          startTimestamp: pendingStop.startTimestamp,
          endTimestamp:
              stopProjection.endTimestamp.isAfter(pendingStop.endTimestamp)
                  ? stopProjection.endTimestamp
                  : pendingStop.endTimestamp,
          activityLabel: 'IDLE',
          distanceMeters: 0,
          pathGeojson: null,
          place: _mergePlace(pendingStop.place, stopProjection.place),
        );
        continue;
      }
      projected.add(pendingStop);
      pendingStop = stopProjection;
      continue;
    }

    if (pendingStop != null) {
      projected.add(pendingStop);
      pendingStop = null;
    }
    projected.add(segment);
  }

  if (pendingStop != null) {
    projected.add(pendingStop);
  }

  return projected;
}

String segmentTitle(TripDiarySegmentDto segment) {
  if (isStopLikeSegment(segment)) {
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

TripDiarySegmentDto _asStopSegment(TripDiarySegmentDto segment) {
  return TripDiarySegmentDto(
    kind: 'STOP',
    startTimestamp: segment.startTimestamp,
    endTimestamp: segment.endTimestamp,
    activityLabel: 'IDLE',
    distanceMeters: 0,
    pathGeojson: null,
    place: segment.place,
  );
}

TripDiaryPlaceDto? _mergePlace(
  TripDiaryPlaceDto? current,
  TripDiaryPlaceDto? incoming,
) {
  if (current == null) return incoming;
  if (incoming == null) return current;
  if (current.id == incoming.id) return current;
  return null;
}

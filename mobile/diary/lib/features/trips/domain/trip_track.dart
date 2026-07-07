import 'package:latlong2/latlong.dart';
import 'package:diary/features/trips/domain/trip_enums.dart';

class TripTrack {
  final int tripId;
  final int pointCount;
  final double distanceMeters;
  final Map<String, dynamic>? geojson;
  final List<double>? bbox;

  const TripTrack({
    required this.tripId,
    required this.pointCount,
    required this.distanceMeters,
    required this.geojson,
    this.bbox,
  });

  List<LatLng> get points {
    final geometry = geojson;
    if (geometry == null || geometry['type'] != 'LineString') {
      return const [];
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const [];

    return [
      for (final coordinate in coordinates)
        if (coordinate is List && coordinate.length >= 2)
          LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          ),
    ];
  }
}

class TripDiary {
  final int tripId;
  final TripDiaryStatus diaryStatus;
  final bool processed;
  final List<TripDiarySegment> segments;
  final List<TripDiaryPlace> places;

  const TripDiary({
    required this.tripId,
    required TripDiaryStatus status,
    required this.processed,
    required this.segments,
    required this.places,
  }) : diaryStatus = status;

  String get status => diaryStatus.wireName;

  List<TripDiarySegment> get drawableSegments {
    return segments
        .where((segment) => segment.isMove && segment.points.length >= 2)
        .toList(growable: false);
  }

  double get movementDistanceMeters {
    return segments.fold<double>(
      0,
      (total, segment) => total + segment.distanceMeters,
    );
  }
}

class TripDiarySegment {
  final TripDiarySegmentKind segmentKind;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final MobilityActivity activity;
  final double distanceMeters;
  final Map<String, dynamic>? pathGeojson;
  final TripDiaryPlace? place;

  const TripDiarySegment({
    required TripDiarySegmentKind kind,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.activity,
    required this.distanceMeters,
    required this.pathGeojson,
    this.place,
  }) : segmentKind = kind;

  String get kind => segmentKind.wireName;

  bool get isMove => segmentKind == TripDiarySegmentKind.move;

  bool get isStop => segmentKind == TripDiarySegmentKind.stop;

  String get activityLabel => activity.wireName;

  List<LatLng> get points {
    final geometry = pathGeojson;
    if (geometry == null || geometry['type'] != 'LineString') {
      return const [];
    }

    final coordinates = geometry['coordinates'];
    if (coordinates is! List) return const [];

    return [
      for (final coordinate in coordinates)
        if (coordinate is List && coordinate.length >= 2)
          LatLng(
            (coordinate[1] as num).toDouble(),
            (coordinate[0] as num).toDouble(),
          ),
    ];
  }
}

class TripDiaryPlace {
  final int id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final int dwellSeconds;
  final String label;

  const TripDiaryPlace({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.dwellSeconds,
    required this.label,
  });
}

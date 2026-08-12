class TripTrackDto {
  final int tripId;
  final int pointCount;
  final double distanceMeters;
  final Map<String, dynamic>? geojson;
  final List<double>? bbox;

  const TripTrackDto({
    required this.tripId,
    required this.pointCount,
    required this.distanceMeters,
    required this.geojson,
    this.bbox,
  });

  factory TripTrackDto.fromJson(Map<String, dynamic> json) {
    return TripTrackDto(
      tripId: json['trip_id'] as int,
      pointCount: json['point_count'] as int? ?? 0,
      distanceMeters: (json['distance_meters'] as num? ?? 0).toDouble(),
      geojson: json['geojson'] == null
          ? null
          : Map<String, dynamic>.from(json['geojson'] as Map<dynamic, dynamic>),
      bbox: (json['bbox'] as List<dynamic>?)
          ?.map((value) => (value as num).toDouble())
          .toList(growable: false),
    );
  }
}

class TripDiaryDto {
  final int tripId;
  final String status;
  final bool processed;
  final bool enrichmentFailed;
  final String? enrichmentFailureReason;
  final List<TripDiarySegmentDto> segments;
  final List<TripDiaryPlaceDto> places;

  const TripDiaryDto({
    required this.tripId,
    required this.status,
    required this.processed,
    required this.enrichmentFailed,
    this.enrichmentFailureReason,
    required this.segments,
    required this.places,
  });

  factory TripDiaryDto.fromJson(Map<String, dynamic> json) {
    return TripDiaryDto(
      tripId: json['trip_id'] as int,
      status: json['status'] as String? ?? '',
      processed: json['processed'] as bool? ?? false,
      enrichmentFailed: json['enrichment_failed'] as bool? ?? false,
      enrichmentFailureReason: json['enrichment_failure_reason'] as String?,
      segments: (json['segments'] as List<dynamic>? ?? const [])
          .map((value) => TripDiarySegmentDto.fromJson(
                Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
              ))
          .toList(growable: false),
      places: (json['places'] as List<dynamic>? ?? const [])
          .map((value) => TripDiaryPlaceDto.fromJson(
                Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
              ))
          .toList(growable: false),
    );
  }
}

class TripDiarySegmentDto {
  final String kind;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final String activityLabel;
  final double distanceMeters;
  final Map<String, dynamic>? pathGeojson;
  final TripDiaryPlaceDto? place;

  const TripDiarySegmentDto({
    required this.kind,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.activityLabel,
    required this.distanceMeters,
    required this.pathGeojson,
    this.place,
  });

  factory TripDiarySegmentDto.fromJson(Map<String, dynamic> json) {
    return TripDiarySegmentDto(
      kind: json['kind'] as String? ?? '',
      startTimestamp: DateTime.parse(json['start_timestamp'] as String),
      endTimestamp: DateTime.parse(json['end_timestamp'] as String),
      activityLabel: json['activity_label'] as String? ?? '',
      distanceMeters: (json['distance_meters'] as num? ?? 0).toDouble(),
      pathGeojson: json['path_geojson'] == null
          ? null
          : Map<String, dynamic>.from(
              json['path_geojson'] as Map<dynamic, dynamic>,
            ),
      place: json['place'] == null
          ? null
          : TripDiaryPlaceDto.fromJson(
              Map<String, dynamic>.from(json['place'] as Map<dynamic, dynamic>),
            ),
    );
  }
}

class TripDiaryPlaceDto {
  final int id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final int dwellSeconds;
  final String label;

  const TripDiaryPlaceDto({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required this.dwellSeconds,
    required this.label,
  });

  factory TripDiaryPlaceDto.fromJson(Map<String, dynamic> json) {
    return TripDiaryPlaceDto(
      id: json['id'] as int,
      latitude: (json['lat'] as num).toDouble(),
      longitude: (json['lon'] as num).toDouble(),
      radiusMeters: (json['radius_meters'] as num? ?? 0).toDouble(),
      dwellSeconds: json['dwell_seconds'] as int? ?? 0,
      label: json['label'] as String? ?? '',
    );
  }
}

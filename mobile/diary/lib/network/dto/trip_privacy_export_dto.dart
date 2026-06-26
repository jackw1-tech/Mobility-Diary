import 'package:diary/features/privacy/domain/privacy_level.dart';

/// Vista Privacy-Aware testuale del diario, pronta per l'export mobile.
///
/// Le coordinate dei MOVE sono gia' cloaked dal backend per i livelli non
/// precisi, quindi il preview puo' mostrarle come "approssimate" senza mai
/// esporre la geometria GPS reale.
class TripPrivacyExportDto {
  final int tripId;
  final PrivacyLevel level;
  final bool isProtected;
  final bool approximatedCoordinates;
  final int? cellSizeMeters;
  final String text;
  final List<TripPrivacyExportSegmentDto> segments;

  const TripPrivacyExportDto({
    required this.tripId,
    required this.level,
    required this.isProtected,
    required this.approximatedCoordinates,
    required this.cellSizeMeters,
    required this.text,
    required this.segments,
  });

  factory TripPrivacyExportDto.fromJson(Map<String, dynamic> json) {
    return TripPrivacyExportDto(
      tripId: json['trip_id'] as int,
      level: PrivacyLevel.fromWire(json['level'] as String? ?? ''),
      isProtected: json['protected'] as bool? ?? true,
      approximatedCoordinates:
          json['approximated_coordinates'] as bool? ?? false,
      cellSizeMeters: json['cell_size_meters'] as int?,
      text: json['text'] as String? ?? '',
      segments: (json['segments'] as List<dynamic>? ?? const [])
          .map((value) => TripPrivacyExportSegmentDto.fromJson(
                Map<String, dynamic>.from(value as Map<dynamic, dynamic>),
              ))
          .toList(growable: false),
    );
  }
}

class TripPrivacyExportSegmentDto {
  final String kind;
  final String startLabel;
  final String endLabel;
  final String activityLabel;
  final String title;
  final int pointCount;
  final List<List<double>> coordinates;

  const TripPrivacyExportSegmentDto({
    required this.kind,
    required this.startLabel,
    required this.endLabel,
    required this.activityLabel,
    required this.title,
    required this.pointCount,
    required this.coordinates,
  });

  factory TripPrivacyExportSegmentDto.fromJson(Map<String, dynamic> json) {
    return TripPrivacyExportSegmentDto(
      kind: json['kind'] as String? ?? '',
      startLabel: json['start_label'] as String? ?? '',
      endLabel: json['end_label'] as String? ?? '',
      activityLabel: json['activity_label'] as String? ?? '',
      title: json['title'] as String? ?? '',
      pointCount: json['point_count'] as int? ?? 0,
      coordinates: (json['coordinates'] as List<dynamic>? ?? const [])
          .map((coordinate) => [
                for (final value in (coordinate as List<dynamic>))
                  (value as num).toDouble(),
              ])
          .toList(growable: false),
    );
  }
}

import 'package:diary/model/entities/privacy/privacy_level.dart';

class TripPrivacyExport {
  final int tripId;
  final PrivacyLevel level;
  final bool isProtected;
  final bool approximatedCoordinates;
  final int? cellSizeMeters;
  final String text;
  final List<TripPrivacyExportSegment> segments;

  const TripPrivacyExport({
    required this.tripId,
    required this.level,
    required this.isProtected,
    required this.approximatedCoordinates,
    required this.cellSizeMeters,
    required this.text,
    required this.segments,
  });
}

class TripPrivacyExportSegment {
  final String kind;
  final String startLabel;
  final String endLabel;
  final String activityLabel;
  final String title;
  final int pointCount;
  final List<List<double>> coordinates;

  const TripPrivacyExportSegment({
    required this.kind,
    required this.startLabel,
    required this.endLabel,
    required this.activityLabel,
    required this.title,
    required this.pointCount,
    required this.coordinates,
  });
}

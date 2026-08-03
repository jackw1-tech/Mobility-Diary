import 'package:diary/model/entities/privacy/trip_privacy_export.dart';
import 'package:diary/network/dto/trip_privacy_export_dto.dart';

class TripPrivacyExportMapper {
  TripPrivacyExport mapExport(TripPrivacyExportDto dto) => TripPrivacyExport(
        tripId: dto.tripId,
        level: dto.level,
        isProtected: dto.isProtected,
        approximatedCoordinates: dto.approximatedCoordinates,
        cellSizeMeters: dto.cellSizeMeters,
        text: dto.text,
        segments: dto.segments.map(mapSegment).toList(growable: false),
      );

  TripPrivacyExportSegment mapSegment(TripPrivacyExportSegmentDto dto) {
    return TripPrivacyExportSegment(
      kind: dto.kind,
      startLabel: dto.startLabel,
      endLabel: dto.endLabel,
      activityLabel: dto.activityLabel,
      title: dto.title,
      pointCount: dto.pointCount,
      coordinates: dto.coordinates,
    );
  }
}

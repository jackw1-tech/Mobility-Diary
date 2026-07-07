import 'package:diary/features/places/domain/place_enums.dart';
import 'package:diary/features/places/domain/place_mining_status.dart';
import 'package:diary/features/places/domain/place_review.dart';
import 'package:diary/network/dto/place_mining_status_dto.dart';
import 'package:diary/network/dto/place_review_dto.dart';

class PlacesMapper {
  PlaceMiningStatus mapStatus(PlaceMiningStatusDto dto) => PlaceMiningStatus(
        status: PlaceMiningState.fromWire(dto.status),
        requestedAt: dto.requestedAt,
        startedAt: dto.startedAt,
        finishedAt: dto.finishedAt,
        errorMessage: dto.errorMessage,
        rerunRequested: dto.rerunRequested,
      );

  PlaceReview mapPlace(PlaceReviewDto dto) => PlaceReview(
        id: dto.id,
        latitude: dto.latitude,
        longitude: dto.longitude,
        radiusMeters: dto.radiusMeters,
        state: PlaceReviewState.fromWire(dto.state),
        label: dto.label,
        category: dto.category,
        customName: dto.customName,
        visitCount: dto.visitCount,
        distinctDays: dto.distinctDays,
        visits: dto.visits.map(mapVisit).toList(growable: false),
      );

  PlaceVisit mapVisit(PlaceVisitDto dto) => PlaceVisit(
        latitude: dto.latitude,
        longitude: dto.longitude,
        startedAt: dto.startedAt,
        endedAt: dto.endedAt,
        pointCount: dto.pointCount,
      );

  List<PlaceReview> mapPlaces(List<PlaceReviewDto> dtos) {
    return dtos.map(mapPlace).toList(growable: false);
  }
}

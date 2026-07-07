import 'package:latlong2/latlong.dart';
import 'package:diary/features/places/domain/place_enums.dart';

class PlaceReview {
  final int id;
  final double latitude;
  final double longitude;
  final double radiusMeters;
  final PlaceReviewState reviewState;
  final String label;
  final String category;
  final String customName;
  final int visitCount;
  final int distinctDays;
  final List<PlaceVisit> visits;

  const PlaceReview({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radiusMeters,
    required PlaceReviewState state,
    required this.label,
    required this.category,
    required this.customName,
    required this.visitCount,
    required this.distinctDays,
    required this.visits,
  }) : reviewState = state;

  String get state => reviewState.wireName;

  bool get isConfirmed => reviewState == PlaceReviewState.confirmed;
  bool get isCandidate => reviewState == PlaceReviewState.candidate;
  bool get isRejected => reviewState == PlaceReviewState.rejected;

  LatLng get center => LatLng(latitude, longitude);
}

class PlaceVisit {
  final double latitude;
  final double longitude;
  final DateTime startedAt;
  final DateTime endedAt;
  final int pointCount;

  const PlaceVisit({
    required this.latitude,
    required this.longitude,
    required this.startedAt,
    required this.endedAt,
    required this.pointCount,
  });

  LatLng get center => LatLng(latitude, longitude);
}

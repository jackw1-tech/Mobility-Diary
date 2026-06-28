import 'package:diary/network/dto/place_review_dto.dart';

class PlaceDetailState {
  final PlaceReviewDto place;
  final bool busy;
  final bool canReview;
  final String? error;

  const PlaceDetailState({
    required this.place,
    this.busy = false,
    this.canReview = true,
    this.error,
  });
}

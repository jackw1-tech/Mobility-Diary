import 'package:diary/model/entities/places/place_review.dart';

class PlaceDetailState {
  final PlaceReview place;
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

import 'package:diary/features/places/domain/place_review.dart';

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

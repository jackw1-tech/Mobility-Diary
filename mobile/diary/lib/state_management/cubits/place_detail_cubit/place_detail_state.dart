import 'package:diary/model/entities/places/place_review.dart';

enum PlaceDetailStatus {
  initial,
  loading,
  loaded,
  error,
}

class PlaceDetailState {
  final PlaceDetailStatus status;
  final PlaceReview place;
  final bool canReview;
  final String? error;

  const PlaceDetailState({
    required this.status,
    required this.place,
    this.canReview = true,
    this.error,
  });

  const PlaceDetailState.initial(this.place)
      : status = PlaceDetailStatus.initial,
        canReview = true,
        error = null;

  bool get isLoading => status == PlaceDetailStatus.loading;

  PlaceDetailState copyWith({
    PlaceDetailStatus? status,
    PlaceReview? place,
    bool? canReview,
    String? error,
    bool clearError = false,
  }) {
    return PlaceDetailState(
      status: status ?? this.status,
      place: place ?? this.place,
      canReview: canReview ?? this.canReview,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

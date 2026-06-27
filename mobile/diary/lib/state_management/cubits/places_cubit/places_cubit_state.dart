import 'package:diary/network/dto/place_review_dto.dart';

enum PlacesStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
}

class PlacesCubitState {
  final PlacesStatus status;
  final List<PlaceReviewDto> places;
  final String? error;

  const PlacesCubitState({
    required this.status,
    this.places = const [],
    this.error,
  });

  const PlacesCubitState.initial()
      : status = PlacesStatus.initial,
        places = const [],
        error = null;

  bool get isLoading => status == PlacesStatus.loading;

  List<PlaceReviewDto> get confirmed =>
      places.where((place) => place.isConfirmed).toList(growable: false);
  List<PlaceReviewDto> get candidates =>
      places.where((place) => place.isCandidate).toList(growable: false);
  List<PlaceReviewDto> get rejected =>
      places.where((place) => place.isRejected).toList(growable: false);
}

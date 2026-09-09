import 'package:diary/model/entities/places/place_mining_status.dart';
import 'package:diary/model/entities/places/place_review.dart';

enum PlacesStatus {
  initial,
  loading,
  loaded,
  empty,
  error,
  miningInProgress,
}

class PlacesCubitState {
  final PlacesStatus status;
  final List<PlaceReview> places;
  final PlaceMiningStatus? placeStatus;
  final String? error;

  const PlacesCubitState({
    required this.status,
    this.places = const [],
    this.placeStatus,
    this.error,
  });

  const PlacesCubitState.initial()
      : status = PlacesStatus.initial,
        places = const [],
        placeStatus = null,
        error = null;

  bool get isLoading => status == PlacesStatus.loading;
  bool get canReview => placeStatus?.isActionable ?? true;

  List<PlaceReview> get confirmed =>
      places.where((place) => place.isConfirmed).toList(growable: false);
  List<PlaceReview> get candidates =>
      places.where((place) => place.isCandidate).toList(growable: false);
  List<PlaceReview> get rejected =>
      places.where((place) => place.isRejected).toList(growable: false);
}

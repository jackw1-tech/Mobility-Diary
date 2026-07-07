import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/places/domain/place_mining_status.dart';
import 'package:diary/features/places/domain/place_review.dart';

abstract class PlacesRepository {
  Future<AppResult<PlaceMiningStatus>> fetchPlacesStatus();
  Future<AppResult<List<PlaceReview>>> fetchPlaces();
  Future<AppResult<PlaceReview>> confirmPlace(int id);
  Future<AppResult<PlaceReview>> rejectPlace(int id);
  Future<AppResult<PlaceReview>> reactivatePlace(int id);
  Future<AppResult<PlaceReview>> labelPlace(
    int id, {
    required String category,
    required String customName,
  });
}

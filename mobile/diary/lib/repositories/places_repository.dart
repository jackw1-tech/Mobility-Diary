import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/places/place_mining_status.dart';
import 'package:diary/model/entities/places/place_review.dart';

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

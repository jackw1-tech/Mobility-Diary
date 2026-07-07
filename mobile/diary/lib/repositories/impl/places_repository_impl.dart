import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/places/domain/place_mining_status.dart';
import 'package:diary/features/places/domain/place_review.dart';
import 'package:diary/mappers/places_mapper.dart';
import 'package:diary/network/service/places_service.dart';
import 'package:diary/repositories/places_repository.dart';

class PlacesRepositoryImpl implements PlacesRepository {
  final PlacesService _service;
  final PlacesMapper _mapper;

  const PlacesRepositoryImpl({
    required PlacesService service,
    required PlacesMapper mapper,
  })  : _service = service,
        _mapper = mapper;

  @override
  Future<AppResult<PlaceMiningStatus>> fetchPlacesStatus() => appResultOf(
        () async => _mapper.mapStatus(await _service.fetchPlacesStatus()),
      );

  @override
  Future<AppResult<List<PlaceReview>>> fetchPlaces() => appResultOf(
        () async => _mapper.mapPlaces(await _service.fetchPlaces()),
      );

  @override
  Future<AppResult<PlaceReview>> confirmPlace(int id) => _action(
        () => _service.confirmPlace(id),
      );

  @override
  Future<AppResult<PlaceReview>> rejectPlace(int id) => _action(
        () => _service.rejectPlace(id),
      );

  @override
  Future<AppResult<PlaceReview>> reactivatePlace(int id) => _action(
        () => _service.reactivatePlace(id),
      );

  @override
  Future<AppResult<PlaceReview>> labelPlace(
    int id, {
    required String category,
    required String customName,
  }) {
    return _action(
      () => _service.labelPlace(
        id,
        category: category,
        customName: customName,
      ),
    );
  }

  Future<AppResult<PlaceReview>> _action(Future<dynamic> Function() run) async {
    try {
      return AppResult.success(_mapper.mapPlace(await run()));
    } on PlaceMutationBlockedException catch (error) {
      return AppResult.failure(
        ValidationFailure(
          error.message,
          cause: PlaceReviewBlockedException(
            error.message,
            placeStatus: _mapper.mapStatus(error.placeStatus),
          ),
        ),
      );
    } catch (error) {
      return AppResult.failure(toAppFailure(error));
    }
  }
}

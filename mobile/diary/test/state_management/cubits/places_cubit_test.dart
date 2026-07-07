import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/places/domain/place_enums.dart';
import 'package:diary/features/places/domain/place_mining_status.dart';
import 'package:diary/features/places/domain/place_review.dart';
import 'package:diary/repositories/places_repository.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlacesService implements PlacesRepository {
  PlaceMiningStatus statusResult =
      const PlaceMiningStatus(status: PlaceMiningState.succeeded);
  List<PlaceReview>? result;
  Object? error;

  @override
  Future<AppResult<PlaceMiningStatus>> fetchPlacesStatus() async =>
      AppResult.success(statusResult);

  @override
  Future<AppResult<List<PlaceReview>>> fetchPlaces() async {
    final failure = error;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(result!);
  }

  @override
  Future<AppResult<PlaceReview>> confirmPlace(int id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<PlaceReview>> rejectPlace(int id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<PlaceReview>> reactivatePlace(int id) =>
      throw UnimplementedError();

  @override
  Future<AppResult<PlaceReview>> labelPlace(
    int id, {
    required String category,
    required String customName,
  }) =>
      throw UnimplementedError();
}

PlaceReview _place(int id, String state) => PlaceReview(
      id: id,
      latitude: 45.46,
      longitude: 9.19,
      radiusMeters: 0,
      state: PlaceReviewState.fromWire(state),
      label: 'luogo',
      category: '',
      customName: '',
      visitCount: 2,
      distinctDays: 2,
      visits: const [],
    );

void main() {
  group('PlacesCubit', () {
    test('emits loaded and groups places by state', () async {
      final service = FakePlacesService()
        ..result = [
          _place(1, 'CONFIRMED'),
          _place(2, 'CANDIDATE'),
          _place(3, 'CONFIRMED'),
        ];
      final cubit = PlacesCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, PlacesStatus.loaded);
      expect(cubit.state.confirmed, hasLength(2));
      expect(cubit.state.candidates, hasLength(1));
    });

    test('emits empty when service returns no places', () async {
      final service = FakePlacesService()..result = const [];
      final cubit = PlacesCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, PlacesStatus.empty);
    });

    test('keeps the screen loaded when mining is still pending', () async {
      final service = FakePlacesService()
        ..statusResult =
            const PlaceMiningStatus(status: PlaceMiningState.pending)
        ..result = const [];
      final cubit = PlacesCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, PlacesStatus.loaded);
      expect(cubit.state.canReview, isFalse);
      expect(cubit.state.placeStatus?.status, 'PENDING');
    });

    test('emits error when service fails', () async {
      final service = FakePlacesService()..error = Exception('boom');
      final cubit = PlacesCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, PlacesStatus.error);
      expect(cubit.state.error, contains('boom'));
    });
  });
}

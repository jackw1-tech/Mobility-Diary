import 'package:diary/network/dto/place_mining_status_dto.dart';
import 'package:diary/network/dto/place_review_dto.dart';
import 'package:diary/network/service/places_service.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit.dart';
import 'package:diary/state_management/cubits/places_cubit/places_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlacesService implements PlacesService {
  PlaceMiningStatusDto statusResult =
      const PlaceMiningStatusDto(status: 'SUCCEEDED');
  List<PlaceReviewDto>? result;
  Object? error;

  @override
  Future<PlaceMiningStatusDto> fetchPlacesStatus() async => statusResult;

  @override
  Future<List<PlaceReviewDto>> fetchPlaces() async {
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }

  @override
  Future<PlaceReviewDto> confirmPlace(int id) => throw UnimplementedError();

  @override
  Future<PlaceReviewDto> rejectPlace(int id) => throw UnimplementedError();

  @override
  Future<PlaceReviewDto> reactivatePlace(int id) => throw UnimplementedError();

  @override
  Future<PlaceReviewDto> labelPlace(
    int id, {
    required String category,
    required String customName,
  }) =>
      throw UnimplementedError();
}

PlaceReviewDto _place(int id, String state) => PlaceReviewDto(
      id: id,
      latitude: 45.46,
      longitude: 9.19,
      radiusMeters: 0,
      state: state,
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
        ..statusResult = const PlaceMiningStatusDto(status: 'PENDING')
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

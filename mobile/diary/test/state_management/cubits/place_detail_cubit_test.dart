import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/places/domain/place_enums.dart';
import 'package:diary/features/places/domain/place_mining_status.dart';
import 'package:diary/features/places/domain/place_review.dart';
import 'package:diary/repositories/places_repository.dart';
import 'package:diary/state_management/cubits/place_detail_cubit/place_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlacesService implements PlacesRepository {
  PlaceMiningStatus statusResult =
      const PlaceMiningStatus(status: PlaceMiningState.succeeded);
  PlaceReview? actionResult;
  Object? error;
  final calls = <String>[];

  @override
  Future<AppResult<PlaceMiningStatus>> fetchPlacesStatus() async =>
      AppResult.success(statusResult);

  @override
  Future<AppResult<List<PlaceReview>>> fetchPlaces() async =>
      const AppResult.success([]);

  @override
  Future<AppResult<PlaceReview>> confirmPlace(int id) => _result('confirm:$id');

  @override
  Future<AppResult<PlaceReview>> rejectPlace(int id) => _result('reject:$id');

  @override
  Future<AppResult<PlaceReview>> reactivatePlace(int id) =>
      _result('reactivate:$id');

  @override
  Future<AppResult<PlaceReview>> labelPlace(
    int id, {
    required String category,
    required String customName,
  }) =>
      _result('label:$id:$category:$customName');

  Future<AppResult<PlaceReview>> _result(String call) async {
    calls.add(call);
    final failure = error;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(actionResult!);
  }
}

PlaceReview _place(String state, {String label = 'luogo'}) => PlaceReview(
      id: 5,
      latitude: 45.46,
      longitude: 9.19,
      radiusMeters: 0,
      state: PlaceReviewState.fromWire(state),
      label: label,
      category: '',
      customName: '',
      visitCount: 2,
      distinctDays: 2,
      visits: const [],
    );

void main() {
  group('PlaceDetailCubit', () {
    test('confirm updates place with backend result', () async {
      final service = FakePlacesService()..actionResult = _place('CONFIRMED');
      final cubit = PlaceDetailCubit(service, _place('CANDIDATE'));
      addTearDown(cubit.close);

      await cubit.loadReviewStatus();
      await cubit.confirm();

      expect(service.calls, ['confirm:5']);
      expect(cubit.state.place.state, 'CONFIRMED');
      expect(cubit.state.busy, isFalse);
    });

    test('label forwards category and custom name', () async {
      final service = FakePlacesService()
        ..actionResult = _place('CONFIRMED', label: 'Bicocca');
      final cubit = PlaceDetailCubit(service, _place('CONFIRMED'));
      addTearDown(cubit.close);

      await cubit.loadReviewStatus();
      await cubit.label('universita', 'Bicocca');

      expect(service.calls, ['label:5:universita:Bicocca']);
      expect(cubit.state.place.label, 'Bicocca');
    });

    test('keeps current place and surfaces error on failure', () async {
      final service = FakePlacesService()..error = Exception('boom');
      final cubit = PlaceDetailCubit(service, _place('CANDIDATE'));
      addTearDown(cubit.close);

      await cubit.loadReviewStatus();
      await cubit.reject();

      expect(cubit.state.place.state, 'CANDIDATE');
      expect(cubit.state.error, contains('boom'));
    });

    test('preserves canReview while an action is running', () async {
      final service = FakePlacesService()..actionResult = _place('CONFIRMED');
      final cubit = PlaceDetailCubit(service, _place('CANDIDATE'));
      addTearDown(cubit.close);

      await cubit.loadReviewStatus();
      final future = cubit.confirm();

      expect(cubit.state.canReview, isTrue);
      await future;
      expect(cubit.state.canReview, isTrue);
    });

    test('blocks actions while review is not actionable', () async {
      final service = FakePlacesService()
        ..statusResult =
            const PlaceMiningStatus(status: PlaceMiningState.pending)
        ..actionResult = _place('CONFIRMED');
      final cubit = PlaceDetailCubit(service, _place('CANDIDATE'));
      addTearDown(cubit.close);

      await cubit.loadReviewStatus();
      await cubit.confirm();

      expect(service.calls, isEmpty);
      expect(cubit.state.canReview, isFalse);
      expect(cubit.state.error, contains('Analisi dei luoghi abituali'));
    });

    test(
        'switches to blocked state when backend returns place-mutation-blocked',
        () async {
      final service = FakePlacesService()
        ..error = const PlaceReviewBlockedException(
          'Analisi dei luoghi abituali non completata',
          placeStatus: PlaceMiningStatus(status: PlaceMiningState.running),
        );
      final cubit = PlaceDetailCubit(service, _place('CANDIDATE'));
      addTearDown(cubit.close);

      await cubit.loadReviewStatus();
      await cubit.confirm();

      expect(cubit.state.canReview, isFalse);
      expect(cubit.state.error, contains('Analisi dei luoghi abituali'));
    });
  });
}

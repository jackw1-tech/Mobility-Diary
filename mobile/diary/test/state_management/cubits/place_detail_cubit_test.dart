import 'package:diary/network/dto/place_mining_status_dto.dart';
import 'package:diary/network/dto/place_review_dto.dart';
import 'package:diary/network/service/places_service.dart';
import 'package:diary/state_management/cubits/place_detail_cubit/place_detail_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePlacesService implements PlacesService {
  PlaceMiningStatusDto statusResult =
      const PlaceMiningStatusDto(status: 'SUCCEEDED');
  PlaceReviewDto? actionResult;
  Object? error;
  final calls = <String>[];

  @override
  Future<PlaceMiningStatusDto> fetchPlacesStatus() async => statusResult;

  @override
  Future<List<PlaceReviewDto>> fetchPlaces() async => const [];

  @override
  Future<PlaceReviewDto> confirmPlace(int id) => _result('confirm:$id');

  @override
  Future<PlaceReviewDto> rejectPlace(int id) => _result('reject:$id');

  @override
  Future<PlaceReviewDto> reactivatePlace(int id) => _result('reactivate:$id');

  @override
  Future<PlaceReviewDto> labelPlace(
    int id, {
    required String category,
    required String customName,
  }) =>
      _result('label:$id:$category:$customName');

  Future<PlaceReviewDto> _result(String call) async {
    calls.add(call);
    final failure = error;
    if (failure != null) throw failure;
    return actionResult!;
  }
}

PlaceReviewDto _place(String state, {String label = 'luogo'}) => PlaceReviewDto(
      id: 5,
      latitude: 45.46,
      longitude: 9.19,
      radiusMeters: 0,
      state: state,
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
        ..statusResult = const PlaceMiningStatusDto(status: 'PENDING')
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
        ..error = const PlaceMutationBlockedException(
          'Analisi dei luoghi abituali non completata',
          placeStatus: PlaceMiningStatusDto(status: 'RUNNING'),
          statusCode: 409,
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

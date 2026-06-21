import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTripsService implements TripsService {
  List<TripListItemDto>? result;
  Object? error;

  @override
  Future<List<TripListItemDto>> fetchTrips() async {
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }
}

TripListItemDto _trip(int id) => TripListItemDto(
      id: id,
      startedAt: DateTime.utc(2026, 6, 12, 10),
      endedAt: DateTime.utc(2026, 6, 12, 10, 30),
      status: 'PROCESSED',
      distanceMeters: 1000,
      hasTrack: true,
    );

void main() {
  group('TripsListCubit', () {
    test('emits loaded when service returns trips', () async {
      final service = FakeTripsService()..result = [_trip(1), _trip(2)];
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, TripsListStatus.loaded);
      expect(cubit.state.trips, hasLength(2));
    });

    test('emits empty when service returns no trips', () async {
      final service = FakeTripsService()..result = const [];
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, TripsListStatus.empty);
      expect(cubit.state.trips, isEmpty);
    });

    test('emits error when service fails', () async {
      final service = FakeTripsService()..error = Exception('boom');
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, TripsListStatus.error);
      expect(cubit.state.error, contains('boom'));
    });
  });
}

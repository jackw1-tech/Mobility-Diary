import 'package:diary/mappers/trips_mapper.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:diary/network/dto/trip_reload_slots_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/impl/trips_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripsRepositoryImpl', () {
    test('purges local acquisition data after remote delete succeeds',
        () async {
      final service = _FakeTripsService();
      final purger = _FakeLocalTripPurger();
      final repository = TripsRepositoryImpl(
        service: service,
        mapper: TripsMapper(),
        localTripPurger: purger,
      );

      final result = await repository.deleteTrip(7);

      expect(result.isSuccess, isTrue);
      expect(service.deletedTripIds, [7]);
      expect(purger.purgedTripIds, [7]);
    });

    test('delete still succeeds when local purge fails', () async {
      final service = _FakeTripsService();
      final purger = _FakeLocalTripPurger()..error = Exception('drift error');
      final repository = TripsRepositoryImpl(
        service: service,
        mapper: TripsMapper(),
        localTripPurger: purger,
      );

      final result = await repository.deleteTrip(7);

      expect(result.isSuccess, isTrue);
      expect(service.deletedTripIds, [7]);
      expect(purger.purgedTripIds, [7]);
    });

    test('reuses reload request id until reload succeeds', () async {
      var generated = 0;
      final service = _FakeTripsService()
        ..reloadFailuresBeforeSuccess = 1
        ..reloadError = Exception('timeout');
      final repository = TripsRepositoryImpl(
        service: service,
        mapper: TripsMapper(),
        reloadRequestIdFactory: () => 'request-${++generated}',
      );

      final first = await repository.reloadTrip(sourceTripId: 3);
      final second = await repository.reloadTrip(sourceTripId: 3);

      expect(first.isFailure, isTrue);
      expect(second.requireValue.tripId, 99);
      expect(service.reloadRequestIds, ['request-1', 'request-1']);
      expect(generated, 1);
    });

    test('passes selected scheduled start to reload service', () async {
      final selectedStart = DateTime.utc(2026, 6, 29, 12, 15);
      final service = _FakeTripsService();
      final repository = TripsRepositoryImpl(
        service: service,
        mapper: TripsMapper(),
        reloadRequestIdFactory: () => 'fixed-request',
      );

      final result = await repository.reloadTrip(
        sourceTripId: 3,
        scheduledStartAt: selectedStart,
      );

      expect(result.requireValue.tripId, 99);
      expect(service.reloadRequestIds, ['fixed-request']);
      expect(service.scheduledStartAt, selectedStart);
    });
  });
}

class _FakeLocalTripPurger implements AcquisitionLocalTripPurger {
  final List<int> purgedTripIds = [];
  Object? error;

  @override
  Future<void> purgeLocalDataForRemoteTrip(int tripId) async {
    purgedTripIds.add(tripId);
    final failure = error;
    if (failure != null) throw failure;
  }
}

class _FakeTripsService implements TripsService {
  final List<int> deletedTripIds = [];
  final List<String> reloadRequestIds = [];
  int reloadFailuresBeforeSuccess = 0;
  Object? reloadError;
  DateTime? scheduledStartAt;

  @override
  Future<void> deleteTrip(int tripId) async {
    deletedTripIds.add(tripId);
  }

  @override
  Future<TripReloadDto> reloadTrip({
    required int sourceTripId,
    required String reloadRequestId,
    DateTime? scheduledStartAt,
  }) async {
    reloadRequestIds.add(reloadRequestId);
    this.scheduledStartAt = scheduledStartAt;
    if (reloadFailuresBeforeSuccess > 0) {
      reloadFailuresBeforeSuccess -= 1;
      final failure = reloadError ?? Exception('timeout');
      if (reloadFailuresBeforeSuccess == 0) reloadError = null;
      throw failure;
    }
    final failure = reloadError;
    if (failure != null) throw failure;
    return const TripReloadDto(
      ingestionId: 10,
      tripId: 99,
      coreStatus: 'COMPLETED',
      rawStatus: 'QUEUED',
      gpsPoints: 2,
      stateTransitions: 2,
      pathPoints: 2,
      distanceMeters: 1000,
      mapAvailable: true,
    );
  }

  @override
  Future<List<TripListItemDto>> fetchTrips() async {
    return const [];
  }

  @override
  Future<List<TripListItemDto>> fetchReloadableTrips() async {
    return const [];
  }

  @override
  Future<TripReloadSlotsDto> fetchReloadSlots(int sourceTripId) async {
    return TripReloadSlotsDto(
      sourceTripId: sourceTripId,
      durationSeconds: 1200,
      slots: const [],
    );
  }

  @override
  Future<TripListItemDto> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  }) {
    throw UnimplementedError();
  }

  @override
  Future<TripListItemDto> updateTripNote({
    required int tripId,
    required String note,
  }) {
    throw UnimplementedError();
  }
}

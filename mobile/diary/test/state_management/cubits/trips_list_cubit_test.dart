import 'dart:async';

import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTripsService implements TripsService {
  List<TripListItemDto>? result;
  List<TripListItemDto>? reloadableResult;
  TripReloadDto? reloadResult;
  Completer<List<TripListItemDto>>? tripsCompleter;
  Completer<List<TripListItemDto>>? reloadableCompleter;
  Object? error;
  Object? reloadError;
  int reloadFailuresBeforeSuccess = 0;
  int? reloadedSourceTripId;
  String? reloadRequestId;
  final List<String> reloadRequestIds = [];

  @override
  Future<List<TripListItemDto>> fetchTrips() async {
    final completer = tripsCompleter;
    if (completer != null) return completer.future;
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }

  @override
  Future<List<TripListItemDto>> fetchReloadableTrips() async {
    final completer = reloadableCompleter;
    if (completer != null) return completer.future;
    final failure = error;
    if (failure != null) throw failure;
    return reloadableResult!;
  }

  @override
  Future<TripReloadDto> reloadTrip({
    required int sourceTripId,
    required String reloadRequestId,
  }) async {
    reloadedSourceTripId = sourceTripId;
    this.reloadRequestId = reloadRequestId;
    reloadRequestIds.add(reloadRequestId);
    if (reloadFailuresBeforeSuccess > 0) {
      reloadFailuresBeforeSuccess -= 1;
      final failure = reloadError ?? Exception('timeout');
      if (reloadFailuresBeforeSuccess == 0) reloadError = null;
      throw failure;
    }
    final failure = reloadError;
    if (failure != null) throw failure;
    return reloadResult!;
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

const _reload = TripReloadDto(
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

    test('loads reloadable trips', () async {
      final service = FakeTripsService()..reloadableResult = [_trip(7)];
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      await cubit.loadReloadable();

      expect(cubit.state.status, TripsListStatus.loaded);
      expect(cubit.state.trips.single.id, 7);
    });

    test('ignores stale trip loads after switching to reloadable trips',
        () async {
      final service = FakeTripsService()
        ..tripsCompleter = Completer<List<TripListItemDto>>()
        ..reloadableCompleter = Completer<List<TripListItemDto>>();
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      final tripsLoad = cubit.load();
      final reloadableLoad = cubit.loadReloadable();
      service.reloadableCompleter!.complete([_trip(7)]);
      await reloadableLoad;

      expect(cubit.state.trips.single.id, 7);

      service.tripsCompleter!.complete([_trip(1)]);
      await tripsLoad;

      expect(cubit.state.trips.single.id, 7);
    });

    test('reloads a trip with generated request id', () async {
      final service = FakeTripsService()..reloadResult = _reload;
      final cubit = TripsListCubit(
        service,
        reloadRequestIdFactory: () => 'fixed-request',
      );
      addTearDown(cubit.close);

      final tripId = await cubit.reloadTrip(7);

      expect(tripId, 99);
      expect(service.reloadedSourceTripId, 7);
      expect(service.reloadRequestId, 'fixed-request');
      expect(cubit.state.reloadingTripId, isNull);
      expect(cubit.state.reloadError, isNull);
    });

    test('reuses the same request id when retrying after a failure', () async {
      var generated = 0;
      final service = FakeTripsService()
        ..reloadResult = _reload
        ..reloadError = Exception('timeout')
        ..reloadFailuresBeforeSuccess = 1;
      final cubit = TripsListCubit(
        service,
        reloadRequestIdFactory: () => 'request-${++generated}',
      );
      addTearDown(cubit.close);

      final first = await cubit.reloadTrip(7);
      final second = await cubit.reloadTrip(7);

      expect(first, isNull);
      expect(second, 99);
      expect(service.reloadRequestIds, ['request-1', 'request-1']);
      expect(generated, 1);
    });

    test('keeps the drawer on reload failure', () async {
      final service = FakeTripsService()
        ..reloadError = Exception('telemetrie sorgente non disponibili');
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      final tripId = await cubit.reloadTrip(7);

      expect(tripId, isNull);
      expect(cubit.state.reloadingTripId, isNull);
      expect(
        cubit.state.reloadError,
        contains('telemetrie sorgente non disponibili'),
      );
    });
  });
}

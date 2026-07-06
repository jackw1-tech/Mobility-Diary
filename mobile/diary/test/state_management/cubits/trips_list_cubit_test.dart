import 'dart:async';

import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:diary/network/dto/trip_reload_slots_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeAcquisitionRepository implements AcquisitionRepository {
  int? purgedTripId;
  Object? purgeError;

  @override
  Future<void> purgeLocalDataForRemoteTrip(int tripId) async {
    purgedTripId = tripId;
    final failure = purgeError;
    if (failure != null) throw failure;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class FakeTripsService implements TripsService {
  List<TripListItemDto>? result;
  List<TripListItemDto>? reloadableResult;
  TripReloadDto? reloadResult;
  Completer<List<TripListItemDto>>? tripsCompleter;
  Completer<List<TripListItemDto>>? reloadableCompleter;
  Object? error;
  Object? reloadError;
  Object? mutationError;
  int reloadFailuresBeforeSuccess = 0;
  int? reloadedSourceTripId;
  int? deletedTripId;
  int? reloadableTripId;
  bool? requestedReloadableValue;
  TripListItemDto? reloadableUpdateResult;
  int? noteTripId;
  String? requestedNote;
  TripListItemDto? noteUpdateResult;
  String? reloadRequestId;
  DateTime? scheduledStartAt;
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
  Future<TripReloadSlotsDto> fetchReloadSlots(int sourceTripId) async {
    return TripReloadSlotsDto(
      sourceTripId: sourceTripId,
      durationSeconds: 1200,
      slots: const [],
    );
  }

  @override
  Future<void> deleteTrip(int tripId) async {
    deletedTripId = tripId;
    final failure = mutationError;
    if (failure != null) throw failure;
  }

  @override
  Future<TripListItemDto> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  }) async {
    reloadableTripId = tripId;
    requestedReloadableValue = isReloadable;
    final failure = mutationError;
    if (failure != null) throw failure;
    return reloadableUpdateResult!;
  }

  @override
  Future<TripListItemDto> updateTripNote({
    required int tripId,
    required String note,
  }) async {
    noteTripId = tripId;
    requestedNote = note;
    final failure = mutationError;
    if (failure != null) throw failure;
    return noteUpdateResult!;
  }

  @override
  Future<TripReloadDto> reloadTrip({
    required int sourceTripId,
    required String reloadRequestId,
    DateTime? scheduledStartAt,
  }) async {
    reloadedSourceTripId = sourceTripId;
    this.reloadRequestId = reloadRequestId;
    this.scheduledStartAt = scheduledStartAt;
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

TripListItemDto _trip(
  int id, {
  bool isReloadable = false,
  String note = '',
}) =>
    TripListItemDto(
      id: id,
      startedAt: DateTime.utc(2026, 6, 12, 10),
      endedAt: DateTime.utc(2026, 6, 12, 10, 30),
      status: 'PROCESSED',
      distanceMeters: 1000,
      note: note,
      hasTrack: true,
      isReloadable: isReloadable,
      canDelete: true,
      canToggleReloadable: true,
      canEditNote: true,
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

    test('deletes a trip from the loaded list', () async {
      final service = FakeTripsService();
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);
      cubit.emit(
        TripsListCubitState(
          status: TripsListStatus.loaded,
          trips: [_trip(1), _trip(2)],
        ),
      );

      final deleted = await cubit.deleteTrip(1);

      expect(deleted, isTrue);
      expect(service.deletedTripId, 1);
      expect(cubit.state.trips.map((trip) => trip.id), [2]);
      expect(cubit.state.mutationError, isNull);
    });

    test(
        'purges leftover local data for the deleted trip via the '
        'acquisition repository', () async {
      final service = FakeTripsService();
      final acquisitionRepository = _FakeAcquisitionRepository();
      final cubit = TripsListCubit(
        service,
        acquisitionRepository: acquisitionRepository,
      );
      addTearDown(cubit.close);
      cubit.emit(
        TripsListCubitState(
          status: TripsListStatus.loaded,
          trips: [_trip(1), _trip(2)],
        ),
      );

      await cubit.deleteTrip(1);
      // La pulizia locale e' fire-and-forget (best-effort): lascia respirare
      // l'event loop prima di verificarla.
      await Future<void>.delayed(Duration.zero);

      expect(acquisitionRepository.purgedTripId, 1);
    });

    test('delete still succeeds even if purging local data fails', () async {
      final service = FakeTripsService();
      final acquisitionRepository = _FakeAcquisitionRepository()
        ..purgeError = Exception('drift error');
      final cubit = TripsListCubit(
        service,
        acquisitionRepository: acquisitionRepository,
      );
      addTearDown(cubit.close);
      cubit.emit(
        TripsListCubitState(
          status: TripsListStatus.loaded,
          trips: [_trip(1)],
        ),
      );

      final deleted = await cubit.deleteTrip(1);
      await Future<void>.delayed(Duration.zero);

      expect(deleted, isTrue);
      expect(cubit.state.mutationError, isNull);
    });

    test('updates a trip after changing reloadable flag', () async {
      final service = FakeTripsService()
        ..reloadableUpdateResult = _trip(1, isReloadable: true);
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);
      cubit.emit(
        TripsListCubitState(
          status: TripsListStatus.loaded,
          trips: [_trip(1), _trip(2)],
        ),
      );

      final updated = await cubit.setTripReloadable(1, true);

      expect(updated, isTrue);
      expect(service.reloadableTripId, 1);
      expect(service.requestedReloadableValue, isTrue);
      expect(cubit.state.trips.first.isReloadable, isTrue);
    });

    test('updates a trip after changing note', () async {
      final service = FakeTripsService()
        ..noteUpdateResult = _trip(1, note: 'Casa universita');
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);
      cubit.emit(
        TripsListCubitState(
          status: TripsListStatus.loaded,
          trips: [_trip(1), _trip(2)],
        ),
      );

      final updated = await cubit.updateTripNote(1, 'Casa universita');

      expect(updated, isTrue);
      expect(service.noteTripId, 1);
      expect(service.requestedNote, 'Casa universita');
      expect(cubit.state.trips.first.note, 'Casa universita');
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

    test('passes the selected start when reloading a trip', () async {
      final selectedStart = DateTime.utc(2026, 6, 29, 12, 15);
      final service = FakeTripsService()..reloadResult = _reload;
      final cubit = TripsListCubit(
        service,
        reloadRequestIdFactory: () => 'fixed-request',
      );
      addTearDown(cubit.close);

      final tripId = await cubit.reloadTrip(
        7,
        scheduledStartAt: selectedStart,
      );

      expect(tripId, 99);
      expect(service.scheduledStartAt, selectedStart);
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

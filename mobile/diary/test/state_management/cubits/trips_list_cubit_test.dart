import 'dart:async';

import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/trips/domain/trip_enums.dart';
import 'package:diary/features/trips/domain/trip_list_item.dart';
import 'package:diary/features/trips/domain/trip_reload.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTripsService implements TripsRepository {
  List<TripListItem>? result;
  List<TripListItem>? reloadableResult;
  TripReload? reloadResult;
  Completer<List<TripListItem>>? tripsCompleter;
  Completer<List<TripListItem>>? reloadableCompleter;
  Object? error;
  Object? reloadError;
  Object? mutationError;
  int reloadFailuresBeforeSuccess = 0;
  int? reloadedSourceTripId;
  int? deletedTripId;
  int? reloadableTripId;
  bool? requestedReloadableValue;
  TripListItem? reloadableUpdateResult;
  int? noteTripId;
  String? requestedNote;
  TripListItem? noteUpdateResult;
  DateTime? scheduledStartAt;

  @override
  Future<AppResult<List<TripListItem>>> fetchTrips() async {
    final completer = tripsCompleter;
    if (completer != null) return AppResult.success(await completer.future);
    final failure = error;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(result!);
  }

  @override
  Future<AppResult<List<TripListItem>>> fetchReloadableTrips() async {
    final completer = reloadableCompleter;
    if (completer != null) return AppResult.success(await completer.future);
    final failure = error;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(reloadableResult!);
  }

  @override
  Future<AppResult<TripReloadSlots>> fetchReloadSlots(int sourceTripId) async {
    return AppResult.success(
      TripReloadSlots(
        sourceTripId: sourceTripId,
        durationSeconds: 1200,
        slots: const [],
      ),
    );
  }

  @override
  Future<AppResult<void>> deleteTrip(int tripId) async {
    deletedTripId = tripId;
    final failure = mutationError;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return const AppResult.success(null);
  }

  @override
  Future<AppResult<TripListItem>> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  }) async {
    reloadableTripId = tripId;
    requestedReloadableValue = isReloadable;
    final failure = mutationError;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(reloadableUpdateResult!);
  }

  @override
  Future<AppResult<TripListItem>> updateTripNote({
    required int tripId,
    required String note,
  }) async {
    noteTripId = tripId;
    requestedNote = note;
    final failure = mutationError;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(noteUpdateResult!);
  }

  @override
  Future<AppResult<TripReload>> reloadTrip({
    required int sourceTripId,
    DateTime? scheduledStartAt,
  }) async {
    reloadedSourceTripId = sourceTripId;
    this.scheduledStartAt = scheduledStartAt;
    if (reloadFailuresBeforeSuccess > 0) {
      reloadFailuresBeforeSuccess -= 1;
      final failure = reloadError ?? Exception('timeout');
      if (reloadFailuresBeforeSuccess == 0) reloadError = null;
      return AppResult.failure(toAppFailure(failure));
    }
    final failure = reloadError;
    if (failure != null) return AppResult.failure(toAppFailure(failure));
    return AppResult.success(reloadResult!);
  }
}

TripListItem _trip(
  int id, {
  bool isReloadable = false,
  String note = '',
}) =>
    TripListItem(
      id: id,
      startedAt: DateTime.utc(2026, 6, 12, 10),
      endedAt: DateTime.utc(2026, 6, 12, 10, 30),
      status: TripStatus.processed,
      distanceMeters: 1000,
      note: note,
      hasTrack: true,
      isReloadable: isReloadable,
      canDelete: true,
      canToggleReloadable: true,
      canEditNote: true,
    );

const _reload = TripReload(
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
        ..tripsCompleter = Completer<List<TripListItem>>()
        ..reloadableCompleter = Completer<List<TripListItem>>();
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
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      final tripId = await cubit.reloadTrip(7);

      expect(tripId, 99);
      expect(service.reloadedSourceTripId, 7);
      expect(cubit.state.reloadingTripId, isNull);
      expect(cubit.state.reloadError, isNull);
    });

    test('passes the selected start when reloading a trip', () async {
      final selectedStart = DateTime.utc(2026, 6, 29, 12, 15);
      final service = FakeTripsService()..reloadResult = _reload;
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      final tripId = await cubit.reloadTrip(
        7,
        scheduledStartAt: selectedStart,
      );

      expect(tripId, 99);
      expect(service.scheduledStartAt, selectedStart);
    });

    test('keeps reload loading state clear after retry succeeds', () async {
      final service = FakeTripsService()
        ..reloadResult = _reload
        ..reloadError = Exception('timeout')
        ..reloadFailuresBeforeSuccess = 1;
      final cubit = TripsListCubit(service);
      addTearDown(cubit.close);

      final first = await cubit.reloadTrip(7);
      final second = await cubit.reloadTrip(7);

      expect(first, isNull);
      expect(second, 99);
      expect(cubit.state.reloadingTripId, isNull);
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

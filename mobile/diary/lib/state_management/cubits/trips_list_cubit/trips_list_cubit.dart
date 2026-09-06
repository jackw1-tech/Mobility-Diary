import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/model/entities/trips/trip_reload.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:diary/utils/trip_detail_diagnostics.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripsListCubit extends Cubit<TripsListCubitState> {
  final TripsRepository _repository;
  final String? diagnosticsTraceId;
  int _loadGeneration = 0;

  TripsListCubit(this._repository, {this.diagnosticsTraceId})
      : super(const TripsListCubitState.initial());

  Future<void> load() => _load(_repository.fetchTrips);

  Future<void> loadReloadable() => _load(_repository.fetchReloadableTrips);

  Future<String?> deleteTrip(int tripId) async {
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadingTripId: state.reloadingTripId,
        mutatingTripId: tripId,
      ),
    );
    final result = await _repository.deleteTrip(tripId);
    final failure = result.failure;
    if (failure != null) {
      emit(
        TripsListCubitState(
          status: state.status,
          trips: state.trips,
          error: state.error,
          reloadingTripId: state.reloadingTripId,
        ),
      );
      return failure.message;
    }
    final trips = state.trips.where((trip) => trip.id != tripId).toList();
    emit(
      TripsListCubitState(
        status: trips.isEmpty ? TripsListStatus.empty : state.status,
        trips: trips,
        error: state.error,
        reloadingTripId: state.reloadingTripId,
      ),
    );
    return null;
  }

  Future<String?> setTripReloadable(int tripId, bool isReloadable) async {
    return _updateTrip(
      tripId,
      () => _repository.setTripReloadable(
        tripId: tripId,
        isReloadable: isReloadable,
      ),
    );
  }

  Future<String?> updateTripNote(int tripId, String note) async {
    return _updateTrip(
      tripId,
      () => _repository.updateTripNote(tripId: tripId, note: note),
    );
  }

  Future<String?> _updateTrip(
    int tripId,
    Future<AppResult<TripListItem>> Function() update,
  ) async {
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadingTripId: state.reloadingTripId,
        mutatingTripId: tripId,
      ),
    );
    final result = await update();
    final failure = result.failure;
    if (failure == null) {
      final updated = result.requireValue;
      emit(
        TripsListCubitState(
          status: state.status,
          trips: [
            for (final trip in state.trips)
              if (trip.id == tripId) updated else trip,
          ],
          error: state.error,
          reloadingTripId: state.reloadingTripId,
        ),
      );
      return null;
    }
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadingTripId: state.reloadingTripId,
      ),
    );
    return failure.message;
  }

  /// Slot liberi in cui e' possibile inserire un viaggio da replay o caricamento diretto
  Future<TripReloadSlots?> loadReloadSlots(int sourceTripId) async {
    final result = await _repository.fetchReloadSlots(sourceTripId);
    final failure = result.failure;
    if (failure == null) {
      return result.requireValue;
    }
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadingTripId: state.reloadingTripId,
        reloadError: failure.message,
        mutatingTripId: state.mutatingTripId,
      ),
    );
    return null;
  }

  Future<int?> reloadTrip(int sourceTripId,
      {DateTime? scheduledStartAt}) async {
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadingTripId: sourceTripId,
        mutatingTripId: state.mutatingTripId,
      ),
    );
    final result = await _repository.reloadTrip(
      sourceTripId: sourceTripId,
      scheduledStartAt: scheduledStartAt,
    );
    final failure = result.failure;
    if (failure == null) {
      final reload = result.requireValue;
      emit(
        TripsListCubitState(
          status: state.status,
          trips: state.trips,
          error: state.error,
          mutatingTripId: state.mutatingTripId,
        ),
      );
      return reload.tripId;
    }
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadError: failure.message,
        mutatingTripId: state.mutatingTripId,
      ),
    );
    return null;
  }

  Future<void> _load(
      Future<AppResult<List<TripListItem>>> Function() fetch) async {
    final stopwatch = Stopwatch()..start();
    final generation = ++_loadGeneration;
    TripDetailDiagnostics.event(
      diagnosticsTraceId,
      'trips_list_load_start',
      fields: {'generation': generation},
    );
    emit(const TripsListCubitState(status: TripsListStatus.loading));
    try {
      final result = await fetch();
      if (isClosed || generation != _loadGeneration) return;
      final failure = result.failure;
      if (failure != null) {
        TripDetailDiagnostics.event(
          diagnosticsTraceId,
          'trips_list_load_failure',
          fields: {
            'duration_ms': stopwatch.elapsedMilliseconds,
            'failure_type': failure.runtimeType,
          },
        );
        emit(
          TripsListCubitState(
            status: TripsListStatus.error,
            error: failure.message,
          ),
        );
        return;
      }
      final trips = result.requireValue;
      TripDetailDiagnostics.event(
        diagnosticsTraceId,
        'trips_list_load_complete',
        fields: {
          'duration_ms': stopwatch.elapsedMilliseconds,
          'trip_count': trips.length,
        },
      );
      emit(
        TripsListCubitState(
          status:
              trips.isEmpty ? TripsListStatus.empty : TripsListStatus.loaded,
          trips: trips,
        ),
      );
    } catch (error) {
      TripDetailDiagnostics.event(
        diagnosticsTraceId,
        'trips_list_load_exception',
        fields: {
          'duration_ms': stopwatch.elapsedMilliseconds,
          'error_type': error.runtimeType,
        },
      );
      if (isClosed || generation != _loadGeneration) return;
      emit(
        TripsListCubitState(
          status: TripsListStatus.error,
          error: error.toString(),
        ),
      );
    }
  }
}

import 'dart:async';

import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripsListCubit extends Cubit<TripsListCubitState> {
  final TripsService _service;
  final AcquisitionRepository? _acquisitionRepository;
  final String Function() _reloadRequestIdFactory;
  final Map<int, String> _reloadRequestIdsBySource = {};
  int _loadGeneration = 0;

  TripsListCubit(
    this._service, {
    AcquisitionRepository? acquisitionRepository,
    String Function()? reloadRequestIdFactory,
  })  : _acquisitionRepository = acquisitionRepository,
        _reloadRequestIdFactory =
            reloadRequestIdFactory ?? _defaultReloadRequestId,
        super(const TripsListCubitState.initial());

  Future<void> load() => _load(_service.fetchTrips);

  Future<void> loadReloadable() => _load(_service.fetchReloadableTrips);

  Future<bool> deleteTrip(int tripId) async {
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadingTripId: state.reloadingTripId,
        mutatingTripId: tripId,
      ),
    );
    try {
      await _service.deleteTrip(tripId);
      // Best-effort: la cancellazione remota e' gia' andata a buon fine, un
      // eventuale residuo locale (raw fallito in modo definitivo prima della
      // cancellazione) non deve far fallire l'operazione per l'utente.
      unawaited(_purgeLocalDataIfAny(tripId));
      final trips = state.trips.where((trip) => trip.id != tripId).toList();
      emit(
        TripsListCubitState(
          status: trips.isEmpty ? TripsListStatus.empty : state.status,
          trips: trips,
          error: state.error,
          reloadingTripId: state.reloadingTripId,
        ),
      );
      return true;
    } catch (error) {
      emit(
        TripsListCubitState(
          status: state.status,
          trips: state.trips,
          error: state.error,
          reloadingTripId: state.reloadingTripId,
          mutationError: error.toString(),
        ),
      );
      return false;
    }
  }

  Future<void> _purgeLocalDataIfAny(int tripId) async {
    try {
      await _acquisitionRepository?.purgeLocalDataForRemoteTrip(tripId);
    } catch (_) {
      // Best-effort: vedi commento in deleteTrip.
    }
  }

  Future<bool> setTripReloadable(int tripId, bool isReloadable) async {
    return _updateTrip(
      tripId,
      () => _service.setTripReloadable(
        tripId: tripId,
        isReloadable: isReloadable,
      ),
    );
  }

  Future<bool> updateTripNote(int tripId, String note) async {
    return _updateTrip(
      tripId,
      () => _service.updateTripNote(tripId: tripId, note: note),
    );
  }

  Future<bool> _updateTrip(
    int tripId,
    Future<TripListItemDto> Function() update,
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
    try {
      final updated = await update();
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
      return true;
    } catch (error) {
      emit(
        TripsListCubitState(
          status: state.status,
          trips: state.trips,
          error: state.error,
          reloadingTripId: state.reloadingTripId,
          mutationError: error.toString(),
        ),
      );
      return false;
    }
  }

  Future<int?> reloadTrip(int sourceTripId,
      {DateTime? scheduledStartAt}) async {
    final reloadRequestId = _reloadRequestIdsBySource.putIfAbsent(
      sourceTripId,
      _reloadRequestIdFactory,
    );
    emit(
      TripsListCubitState(
        status: state.status,
        trips: state.trips,
        error: state.error,
        reloadingTripId: sourceTripId,
        mutatingTripId: state.mutatingTripId,
        mutationError: state.mutationError,
      ),
    );
    try {
      final result = await _service.reloadTrip(
        sourceTripId: sourceTripId,
        reloadRequestId: reloadRequestId,
        scheduledStartAt: scheduledStartAt,
      );
      _reloadRequestIdsBySource.remove(sourceTripId);
      emit(
        TripsListCubitState(
          status: state.status,
          trips: state.trips,
          error: state.error,
          mutatingTripId: state.mutatingTripId,
          mutationError: state.mutationError,
        ),
      );
      return result.tripId;
    } catch (error) {
      emit(
        TripsListCubitState(
          status: state.status,
          trips: state.trips,
          error: state.error,
          reloadError: error.toString(),
          mutatingTripId: state.mutatingTripId,
          mutationError: state.mutationError,
        ),
      );
      return null;
    }
  }

  Future<void> _load(Future<List<TripListItemDto>> Function() fetch) async {
    final generation = ++_loadGeneration;
    emit(const TripsListCubitState(status: TripsListStatus.loading));
    try {
      final trips = await fetch();
      if (isClosed || generation != _loadGeneration) return;
      emit(
        TripsListCubitState(
          status:
              trips.isEmpty ? TripsListStatus.empty : TripsListStatus.loaded,
          trips: trips,
        ),
      );
    } catch (error) {
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

String _defaultReloadRequestId() =>
    'mobile-${DateTime.now().microsecondsSinceEpoch}';

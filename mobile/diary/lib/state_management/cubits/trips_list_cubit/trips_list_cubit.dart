import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/state_management/cubits/trips_list_cubit/trips_list_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripsListCubit extends Cubit<TripsListCubitState> {
  final TripsService _service;
  final String Function() _reloadRequestIdFactory;
  final Map<int, String> _reloadRequestIdsBySource = {};
  int _loadGeneration = 0;

  TripsListCubit(
    this._service, {
    String Function()? reloadRequestIdFactory,
  })  : _reloadRequestIdFactory =
            reloadRequestIdFactory ?? _defaultReloadRequestId,
        super(const TripsListCubitState.initial());

  Future<void> load() => _load(_service.fetchTrips);

  Future<void> loadReloadable() => _load(_service.fetchReloadableTrips);

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

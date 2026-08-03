import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/model/entities/trips/trip_reload.dart';
import 'package:diary/mappers/trips_mapper.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/trips_repository.dart';

class TripsRepositoryImpl implements TripsRepository {
  final TripsService _service;
  final TripsMapper _mapper;
  final AcquisitionLocalTripPurger? _localTripPurger;
  final String Function() _reloadRequestIdFactory;
  final Map<int, String> _reloadRequestIdsBySource = {};

  TripsRepositoryImpl({
    required TripsService service,
    required TripsMapper mapper,
    AcquisitionLocalTripPurger? localTripPurger,
    String Function()? reloadRequestIdFactory,
  })  : _service = service,
        _mapper = mapper,
        _localTripPurger = localTripPurger,
        _reloadRequestIdFactory =
            reloadRequestIdFactory ?? _defaultReloadRequestId;

  @override
  Future<AppResult<List<TripListItem>>> fetchTrips() => appResultOf(
        () async => _mapper.mapTripListItems(await _service.fetchTrips()),
      );

  @override
  Future<AppResult<List<TripListItem>>> fetchReloadableTrips() => appResultOf(
        () async =>
            _mapper.mapTripListItems(await _service.fetchReloadableTrips()),
      );

  @override
  Future<AppResult<TripReloadSlots>> fetchReloadSlots(int sourceTripId) =>
      appResultOf(
        () async => _mapper.mapTripReloadSlots(
          await _service.fetchReloadSlots(sourceTripId),
        ),
      );

  @override
  Future<AppResult<void>> deleteTrip(int tripId) => appVoidResultOf(() async {
        await _service.deleteTrip(tripId);
        try {
          await _localTripPurger?.purgeLocalDataForRemoteTrip(tripId);
        } catch (_) {
          // Best-effort: la cancellazione remota e' gia' riuscita.
        }
      });

  @override
  Future<AppResult<TripListItem>> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  }) =>
      appResultOf(
        () async => _mapper.mapTripListItem(
          await _service.setTripReloadable(
            tripId: tripId,
            isReloadable: isReloadable,
          ),
        ),
      );

  @override
  Future<AppResult<TripListItem>> updateTripNote({
    required int tripId,
    required String note,
  }) =>
      appResultOf(
        () async => _mapper.mapTripListItem(
          await _service.updateTripNote(tripId: tripId, note: note),
        ),
      );

  @override
  Future<AppResult<TripReload>> reloadTrip({
    required int sourceTripId,
    DateTime? scheduledStartAt,
  }) async {
    final reloadRequestId = _reloadRequestIdsBySource.putIfAbsent(
      sourceTripId,
      _reloadRequestIdFactory,
    );
    final result = await appResultOf(
      () async => _mapper.mapTripReload(
        await _service.reloadTrip(
          sourceTripId: sourceTripId,
          reloadRequestId: reloadRequestId,
          scheduledStartAt: scheduledStartAt,
        ),
      ),
    );
    if (result.isSuccess) {
      _reloadRequestIdsBySource.remove(sourceTripId);
    }
    return result;
  }
}

String _defaultReloadRequestId() =>
    'mobile-${DateTime.now().microsecondsSinceEpoch}';

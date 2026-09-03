import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/trips/trip_list_item.dart';
import 'package:diary/model/entities/trips/trip_reload.dart';
import 'package:diary/mappers/trips_mapper.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/trips_repository.dart';
import 'package:diary/utils/trip_reload_diagnostics.dart';

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
        () async {
          final dto = await _service.fetchReloadSlots(sourceTripId);
          final stopwatch = Stopwatch()..start();
          final slots = _mapper.mapTripReloadSlots(dto);
          TripReloadDiagnostics.eventForTrip(
            sourceTripId,
            'slots_mapped',
            fields: {
              'duration_ms': stopwatch.elapsedMilliseconds,
              'slot_count': slots.slots.length,
            },
          );
          return slots;
        },
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
    final isRetry = _reloadRequestIdsBySource.containsKey(sourceTripId);
    final reloadRequestId = _reloadRequestIdsBySource.putIfAbsent(
      sourceTripId,
      _reloadRequestIdFactory,
    );
    TripReloadDiagnostics.eventForTrip(
      sourceTripId,
      'reload_request_id_ready',
      fields: {'reused_request_id': isRetry},
    );
    final result = await appResultOf(
      () async {
        final dto = await _service.reloadTrip(
          sourceTripId: sourceTripId,
          reloadRequestId: reloadRequestId,
          scheduledStartAt: scheduledStartAt,
        );
        final stopwatch = Stopwatch()..start();
        final reload = _mapper.mapTripReload(dto);
        TripReloadDiagnostics.eventForTrip(
          sourceTripId,
          'reload_mapped',
          fields: {
            'duration_ms': stopwatch.elapsedMilliseconds,
            'derived_trip': reload.tripId,
          },
        );
        return reload;
      },
    );
    if (result.isSuccess) {
      _reloadRequestIdsBySource.remove(sourceTripId);
    }
    return result;
  }
}

String _defaultReloadRequestId() =>
    'mobile-${DateTime.now().microsecondsSinceEpoch}';

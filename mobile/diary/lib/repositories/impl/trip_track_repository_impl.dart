import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/mappers/trips_mapper.dart';
import 'package:diary/network/service/trip_track_service.dart' as service;
import 'package:diary/repositories/trip_track_repository.dart';
import 'package:diary/utils/trip_detail_diagnostics.dart';

class TripTrackRepositoryImpl implements TripTrackRepository {
  final service.TripTrackService _service;
  final TripsMapper _mapper;

  const TripTrackRepositoryImpl({
    required service.TripTrackService service,
    required TripsMapper mapper,
  })  : _service = service,
        _mapper = mapper;

  @override
  Future<AppResult<TripTrack>> fetchTrack(int tripId) => appResultOf(() async {
        final serviceWatch = Stopwatch()..start();
        try {
          final dto = await _service.fetchTrack(tripId);
          TripDetailDiagnostics.eventForTrip(
            tripId,
            'track_service_returned_dto',
            fields: {
              'duration_ms': serviceWatch.elapsedMilliseconds,
              'declared_point_count': dto.pointCount,
              'has_geojson': dto.geojson != null,
            },
          );
          final mapperWatch = Stopwatch()..start();
          final result = _mapper.mapTripTrack(dto);
          TripDetailDiagnostics.eventForTrip(
            tripId,
            'track_repository_mapping_complete',
            fields: {'duration_ms': mapperWatch.elapsedMilliseconds},
          );
          return result;
        } catch (error) {
          TripDetailDiagnostics.eventForTrip(
            tripId,
            'track_repository_error',
            fields: {
              'duration_ms': serviceWatch.elapsedMilliseconds,
              'error_type': error.runtimeType,
            },
          );
          rethrow;
        }
      });

  @override
  Future<AppResult<TripDiary>> fetchDiary(int tripId) => appResultOf(() async {
        final serviceWatch = Stopwatch()..start();
        try {
          final dto = await _service.fetchDiary(tripId);
          TripDetailDiagnostics.eventForTrip(
            tripId,
            'diary_service_returned_dto',
            fields: {
              'duration_ms': serviceWatch.elapsedMilliseconds,
              'processing_completed': dto.processed,
              'segment_count': dto.segments.length,
              'place_count': dto.places.length,
            },
          );
          final mapperWatch = Stopwatch()..start();
          final result = _mapper.mapTripDiary(dto);
          TripDetailDiagnostics.eventForTrip(
            tripId,
            'diary_repository_mapping_complete',
            fields: {'duration_ms': mapperWatch.elapsedMilliseconds},
          );
          return result;
        } catch (error) {
          TripDetailDiagnostics.eventForTrip(
            tripId,
            'diary_repository_error',
            fields: {
              'duration_ms': serviceWatch.elapsedMilliseconds,
              'error_type': error.runtimeType,
            },
          );
          rethrow;
        }
      });
}

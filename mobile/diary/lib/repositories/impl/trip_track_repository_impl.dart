import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/trips/domain/diary_event.dart' as domain;
import 'package:diary/features/trips/domain/trip_track.dart';
import 'package:diary/mappers/trips_mapper.dart';
import 'package:diary/network/service/trip_track_service.dart' as service;
import 'package:diary/repositories/trip_track_repository.dart';

class TripTrackRepositoryImpl implements TripTrackRepository {
  final service.TripTrackService _service;
  final TripsMapper _mapper;

  const TripTrackRepositoryImpl({
    required service.TripTrackService service,
    required TripsMapper mapper,
  })  : _service = service,
        _mapper = mapper;

  @override
  Future<AppResult<TripTrack>> fetchTrack(int tripId) => appResultOf(
        () async => _mapper.mapTripTrack(await _service.fetchTrack(tripId)),
      );

  @override
  Future<AppResult<TripDiary>> fetchDiary(int tripId) => appResultOf(
        () async => _mapper.mapTripDiary(await _service.fetchDiary(tripId)),
      );

  @override
  Stream<domain.DiaryEvent> watchDiaryEvents(int tripId) {
    return _service.watchDiaryEvents(tripId).map(_mapEvent);
  }

  domain.DiaryEvent _mapEvent(service.DiaryEvent event) => domain.DiaryEvent(
        status: switch (event.status) {
          service.DiaryEventStatus.enriched => domain.DiaryEventStatus.enriched,
          service.DiaryEventStatus.failed => domain.DiaryEventStatus.failed,
          service.DiaryEventStatus.unknown => domain.DiaryEventStatus.unknown,
        },
        tripId: event.tripId,
        reasonCode: event.reasonCode,
      );
}

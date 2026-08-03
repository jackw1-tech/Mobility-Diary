import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/trips/trip_track.dart';
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
}

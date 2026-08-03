import 'package:diary/model/entities/trips/trip_track.dart';
import 'package:diary/utils/app_result.dart';

abstract class TripTrackRepository {
  Future<AppResult<TripTrack>> fetchTrack(int tripId);
  Future<AppResult<TripDiary>> fetchDiary(int tripId);
}

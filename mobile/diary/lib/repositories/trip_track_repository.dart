import 'package:diary/features/trips/domain/trip_track.dart';
import 'package:diary/features/common/domain/app_result.dart';

abstract class TripTrackRepository {
  Future<AppResult<TripTrack>> fetchTrack(int tripId);
  Future<AppResult<TripDiary>> fetchDiary(int tripId);
}

import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class TripTrackCubit extends Cubit<TripTrackCubitState> {
  final TripTrackService _service;

  TripTrackCubit(this._service) : super(const TripTrackCubitState.initial());

  Future<void> load(int tripId) async {
    emit(const TripTrackCubitState(status: TripTrackStatus.loading));
    try {
      final track = await _service.fetchTrack(tripId);
      final points = track.points;
      if (points.isEmpty) {
        emit(
          TripTrackCubitState(
            status: TripTrackStatus.empty,
            distanceMeters: track.distanceMeters,
          ),
        );
        return;
      }

      emit(
        TripTrackCubitState(
          status: TripTrackStatus.loaded,
          points: points,
          distanceMeters: track.distanceMeters,
        ),
      );
    } catch (error) {
      emit(
        TripTrackCubitState(
          status: TripTrackStatus.error,
          error: error.toString(),
        ),
      );
    }
  }
}

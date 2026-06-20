import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/network/service/trip_track_service.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit.dart';
import 'package:diary/state_management/cubits/trip_track_cubit/trip_track_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeTripTrackService implements TripTrackService {
  TripTrackDto? result;
  Object? error;

  @override
  Future<TripTrackDto> fetchTrack(int tripId) async {
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }
}

void main() {
  group('TripTrackCubit', () {
    test('emits loaded when service returns points', () async {
      final service = FakeTripTrackService()
        ..result = TripTrackDto.fromJson({
          'trip_id': 1,
          'point_count': 2,
          'distance_meters': 900,
          'geojson': {
            'type': 'LineString',
            'coordinates': [
              [9.10, 45.46],
              [9.20, 45.47],
            ],
          },
        });
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.loaded);
      expect(cubit.state.points, hasLength(2));
      expect(cubit.state.distanceMeters, 900);
    });

    test('emits empty when service returns no GeoJSON', () async {
      final service = FakeTripTrackService()
        ..result = TripTrackDto.fromJson({
          'trip_id': 1,
          'point_count': 1,
          'distance_meters': 0,
          'geojson': null,
        });
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.empty);
      expect(cubit.state.points, isEmpty);
      expect(cubit.state.distanceMeters, 0);
    });

    test('emits error when service fails', () async {
      final service = FakeTripTrackService()..error = Exception('boom');
      final cubit = TripTrackCubit(service);
      addTearDown(cubit.close);

      await cubit.load(1);

      expect(cubit.state.status, TripTrackStatus.error);
      expect(cubit.state.error, contains('boom'));
    });
  });
}

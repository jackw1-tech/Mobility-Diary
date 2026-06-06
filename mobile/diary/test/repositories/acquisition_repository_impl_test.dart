import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionRepositoryImpl', () {
    test('starts and stops tracking with stationary profile', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);

      await repository.startTracking();

      expect(repository.currentSnapshot.isTracking, isTrue);
      expect(
          repository.currentSnapshot.trackingState, TrackingState.stationary);
      expect(repository.currentSnapshot.samplingProfile.gpsEnabled, isFalse);
      expect(await database.acquisitionDao.countSessions(), 1);

      await repository.stopTracking();

      expect(repository.currentSnapshot.isTracking, isFalse);
      expect(
          repository.currentSnapshot.trackingState, TrackingState.stationary);
      final sessions = await database.acquisitionDao.allSessions();
      expect(sessions.single.endedAt, isNotNull);
    });

    test('ingests FSM events and exposes transition snapshots', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      await _enterPotentialMotion(repository, now);

      expect(
        repository.currentSnapshot.trackingState,
        TrackingState.potentialMotion,
      );
      expect(
        repository.currentSnapshot.lastTransition?.reason,
        'movement_sigma_above_threshold',
      );
      expect(repository.currentSnapshot.samplingProfile.gpsEnabled, isTrue);

      final sessions = await database.acquisitionDao.allSessions();
      final transitions = await database.acquisitionDao.transitionsForSession(
        sessions.single.id,
      );
      expect(transitions.single.fromState, 'STATIONARY');
      expect(transitions.single.toState, 'POTENTIAL_MOTION');
      expect(transitions.single.sigma, 1.2);
    });

    test('stores GPS points when active tracking is confirmed', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      await _enterPotentialMotion(repository, now);
      await repository.ingestEvent(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 5)),
          latitude: 44.49491,
          longitude: 11.34261,
          speedMetersPerSecond: 0.9,
          accuracyMeters: 12,
        ),
      );

      final sessions = await database.acquisitionDao.allSessions();

      expect(repository.currentSnapshot.trackingState,
          TrackingState.activeTracking);
      expect(
        await database.acquisitionDao.countGpsPointsForSession(
          sessions.single.id,
        ),
        1,
      );
    });
  });
}

Future<void> _enterPotentialMotion(
  AcquisitionRepositoryImpl repository,
  DateTime timestamp,
) async {
  for (var index = 0; index < 4; index += 1) {
    await repository.ingestEvent(
      MotionWindowEvaluated(
        timestamp: timestamp.add(Duration(seconds: index * 2)),
        sigma: 1.2,
        sampleCount: 20,
      ),
    );
  }
}

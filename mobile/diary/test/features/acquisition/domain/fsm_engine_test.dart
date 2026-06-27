import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionFsm', () {
    test('starts in stationary with the recent sampling profile', () {
      final decision = AcquisitionFsm().apply(
        MotionWindowEvaluated(
          timestamp: DateTime.utc(2026, 1, 1),
          sigma: 0.1,
          sampleCount: 20,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.samplingProfile.accelerometerHz, 10);
      expect(decision.samplingProfile.gpsEnabled, isTrue);
      expect(decision.samplingProfile.gpsInterval, const Duration(seconds: 20));
      expect(decision.samplingProfile.gpsDistanceFilterMeters, 30);
      expect(decision.samplingProfile.gpsAccuracy,
          GpsAccuracyProfile.highAccuracy);
      expect(decision.samplingProfile.harWindowEnabled, isFalse);
      expect(decision.didTransition, isFalse);
    });

    test('switches stationary to deep low-power sampling after ten minutes',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(minutes: 10, seconds: 1)),
          sigma: 0.1,
          sampleCount: 20,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.samplingProfile.gpsInterval, const Duration(minutes: 3));
      expect(decision.samplingProfile.gpsDistanceFilterMeters, 100);
      expect(decision.samplingProfile.gpsAccuracy, GpsAccuracyProfile.lowPower);
    });

    test('moves to movement after four consecutive motion windows', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      final decision = _enterMovement(fsm, now);

      expect(decision.state, TrackingState.movement);
      expect(decision.samplingProfile.accelerometerHz, 100);
      expect(decision.samplingProfile.gyroscopeHz, 100);
      expect(decision.samplingProfile.magnetometerHz, 100);
      expect(decision.samplingProfile.gpsInterval, const Duration(seconds: 2));
      expect(decision.samplingProfile.gpsDistanceFilterMeters, 3);
      expect(decision.samplingProfile.persistSensorWindows, isTrue);
      expect(decision.samplingProfile.persistGpsPoints, isTrue);
      expect(
        decision.transition?.reason,
        'movement_sigma_above_threshold',
      );
    });

    test('moves to movement after two reliable GPS motion fixes', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.8,
          accuracyMeters: 12,
        ),
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 20)),
          speedMetersPerSecond: 0.8,
          accuracyMeters: 12,
        ),
      );

      expect(decision.state, TrackingState.movement);
      expect(
        decision.transition?.reason,
        'gps_reliable_motion_confirmed_in_stationary',
      );
    });

    test('moves to movement after three unreliable GPS motion fixes', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.8,
          accuracyMeters: 60,
        ),
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 20)),
          speedMetersPerSecond: 0.8,
          accuracyMeters: 60,
        ),
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 40)),
          speedMetersPerSecond: 0.8,
          accuracyMeters: 60,
        ),
      );

      expect(decision.state, TrackingState.movement);
      expect(
        decision.transition?.reason,
        'gps_unreliable_motion_confirmed_in_stationary',
      );
    });

    test('keeps movement while speed stays above the movement threshold', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 3,
          accuracyMeters: 12,
        ),
      );

      expect(decision.state, TrackingState.movement);
      expect(decision.didTransition, isFalse);
    });

    test('returns to stationary after the movement grace period', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0,
          accuracyMeters: 10,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 0.05,
          sampleCount: 500,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(minutes: 2, seconds: 1)),
          sigma: 0.04,
          sampleCount: 500,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(
        decision.transition?.reason,
        'gps_and_motion_stationary_for_grace_period',
      );
    });

    test('does not return to stationary before the grace period expires', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0,
          accuracyMeters: 10,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(minutes: 1)),
          sigma: 0.04,
          sampleCount: 500,
        ),
      );

      expect(decision.state, TrackingState.movement);
      expect(decision.didTransition, isFalse);
    });
  });
}

FsmDecision _enterMovement(AcquisitionFsm fsm, DateTime timestamp) {
  late FsmDecision decision;
  for (var index = 0; index < 4; index += 1) {
    decision = fsm.apply(
      MotionWindowEvaluated(
        timestamp: timestamp.add(Duration(seconds: index * 2)),
        sigma: 1.2,
        sampleCount: 20,
      ),
    );
  }
  return decision;
}

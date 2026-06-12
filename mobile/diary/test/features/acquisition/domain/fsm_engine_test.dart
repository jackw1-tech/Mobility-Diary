import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionFsm', () {
    test('starts in stationary with the recent high-accuracy sampling profile',
        () {
      final fsm = AcquisitionFsm();

      final decision = fsm.apply(
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
      expect(decision.samplingProfile.persistGpsPoints, isTrue);
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
      expect(decision.didTransition, isFalse);
    });

    test('moves to potential motion after four consecutive movement windows',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      final firstDecision = _applyMotionWindow(fsm, now);
      _applyMotionWindow(fsm, now.add(const Duration(seconds: 2)));
      _applyMotionWindow(fsm, now.add(const Duration(seconds: 4)));
      final fourthDecision = _applyMotionWindow(
        fsm,
        now.add(const Duration(seconds: 6)),
      );

      expect(firstDecision.state, TrackingState.stationary);
      expect(fourthDecision.state, TrackingState.potentialMotion);
      expect(fourthDecision.samplingProfile.accelerometerHz, 100);
      expect(fourthDecision.samplingProfile.gyroscopeHz, 100);
      expect(fourthDecision.samplingProfile.magnetometerHz, 100);
      expect(fourthDecision.samplingProfile.gpsEnabled, isTrue);
      expect(fourthDecision.samplingProfile.harWindowEnabled, isTrue);
      expect(fourthDecision.samplingProfile.persistSensorWindows, isFalse);
      expect(
        fourthDecision.transition?.reason,
        'movement_sigma_above_threshold',
      );
    });

    test(
        'moves from stationary to potential motion after two reliable GPS motion fixes',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      final firstDecision = fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.8,
          accuracyMeters: 12,
        ),
      );
      final secondDecision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 20)),
          speedMetersPerSecond: 0.8,
          accuracyMeters: 12,
        ),
      );

      expect(firstDecision.state, TrackingState.stationary);
      expect(firstDecision.didTransition, isFalse);
      expect(secondDecision.state, TrackingState.potentialMotion);
      expect(
        secondDecision.transition?.reason,
        'gps_reliable_motion_confirmed_in_stationary',
      );
      expect(
        secondDecision.samplingProfile.gpsInterval,
        const Duration(seconds: 5),
      );
    });

    test('moves reliable fast GPS from stationary to potential after two fixes',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      final firstDecision = fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 3,
          accuracyMeters: 12,
        ),
      );
      final secondDecision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 20)),
          speedMetersPerSecond: 3,
          accuracyMeters: 12,
        ),
      );

      expect(firstDecision.state, TrackingState.stationary);
      expect(firstDecision.didTransition, isFalse);
      expect(secondDecision.state, TrackingState.potentialMotion);
      expect(
        secondDecision.transition?.reason,
        'gps_reliable_motion_confirmed_in_stationary',
      );
      expect(
        secondDecision.samplingProfile.gpsInterval,
        const Duration(seconds: 5),
      );
    });

    test(
        'moves from stationary to potential motion after three unreliable GPS motion fixes',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      FsmDecision decision = fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.8,
          accuracyMeters: 60,
        ),
      );
      expect(decision.state, TrackingState.stationary);

      decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 20)),
          speedMetersPerSecond: 0.8,
          accuracyMeters: 60,
        ),
      );
      expect(decision.state, TrackingState.stationary);

      decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 40)),
          speedMetersPerSecond: 0.8,
          accuracyMeters: 60,
        ),
      );

      expect(decision.state, TrackingState.potentialMotion);
      expect(
        decision.transition?.reason,
        'gps_unreliable_motion_confirmed_in_stationary',
      );
    });

    test(
        'moves from stationary directly to active after three unreliable fast GPS fixes',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      FsmDecision decision = fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 3,
          accuracyMeters: 60,
        ),
      );
      expect(decision.state, TrackingState.stationary);

      decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 20)),
          speedMetersPerSecond: 3,
          accuracyMeters: 60,
        ),
      );
      expect(decision.state, TrackingState.stationary);

      decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 40)),
          speedMetersPerSecond: 3,
          accuracyMeters: 60,
        ),
      );

      expect(decision.state, TrackingState.activeTracking);
      expect(
        decision.transition?.reason,
        'gps_unreliable_fast_speed_confirmed_in_stationary',
      );
    });

    test('moves to active tracking when GPS speed confirms movement', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      _enterPotentialMotion(fsm, now);
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 10)),
          speedMetersPerSecond: 0.8,
          accuracyMeters: 12,
        ),
      );

      expect(decision.state, TrackingState.activeTracking);
      expect(decision.samplingProfile.persistSensorWindows, isTrue);
      expect(decision.samplingProfile.persistGpsPoints, isTrue);
      expect(decision.samplingProfile.gpsInterval, const Duration(seconds: 2));
      expect(decision.samplingProfile.gpsDistanceFilterMeters, 3);
      expect(decision.transition?.reason, 'gps_speed_above_active_threshold');
    });

    test(
        'keeps potential motion when reliable GPS says stationary despite motion',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      _enterPotentialMotion(fsm, now);
      FsmDecision decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 8)),
          speedMetersPerSecond: 0,
          accuracyMeters: 30,
        ),
      );

      for (var index = 0; index < 8; index += 1) {
        decision = _applyMotionWindow(
          fsm,
          now.add(Duration(seconds: 13 + (index * 5))),
          sampleCount: 500,
        );
      }

      expect(decision.state, TrackingState.potentialMotion);
      expect(decision.didTransition, isFalse);
    });

    test('returns to stationary when reliable GPS rejects potential motion',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      _enterPotentialMotion(fsm, now);
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 8)),
          speedMetersPerSecond: 0,
          accuracyMeters: 12,
        ),
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 13)),
          speedMetersPerSecond: 0,
          accuracyMeters: 12,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(
        decision.transition?.reason,
        'gps_stationary_in_potential_motion',
      );
    });

    test('moves to active tracking after sustained motion without reliable GPS',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      _enterPotentialMotion(fsm, now);
      FsmDecision decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 8)),
          speedMetersPerSecond: 0,
          accuracyMeters: 80,
        ),
      );

      for (var index = 0; index < 8; index += 1) {
        decision = _applyMotionWindow(
          fsm,
          now.add(Duration(seconds: 13 + (index * 5))),
          sampleCount: 500,
        );
      }

      expect(decision.state, TrackingState.activeTracking);
      expect(
        decision.transition?.reason,
        'sustained_motion_without_reliable_gps',
      );
    });

    test('returns to stationary when potential motion times out unconfirmed',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      _enterPotentialMotion(fsm, now);
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 5)),
          speedMetersPerSecond: 0,
          accuracyMeters: 8,
        ),
      );

      final decision = fsm.apply(
        PotentialMotionTimeoutElapsed(
          timestamp: now.add(const Duration(seconds: 60)),
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(
        decision.transition?.reason,
        'potential_motion_timeout_without_confirmed_trip',
      );
    });

    test('ignores unreliable stale speed when potential motion times out', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      _enterPotentialMotion(fsm, now);
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 5)),
          speedMetersPerSecond: 0,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 25)),
          speedMetersPerSecond: 3,
          accuracyMeters: 80,
        ),
      );

      final decision = fsm.apply(
        PotentialMotionTimeoutElapsed(
          timestamp: now.add(const Duration(seconds: 60)),
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(
        decision.transition?.reason,
        'potential_motion_timeout_without_confirmed_trip',
      );
    });

    test('returns to stationary after still windows in potential motion', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      _enterPotentialMotion(fsm, now);
      FsmDecision decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 11)),
          sigma: 0.05,
          sampleCount: 500,
        ),
      );

      for (var index = 1; index < 4; index += 1) {
        decision = fsm.apply(
          MotionWindowEvaluated(
            timestamp: now.add(Duration(seconds: 11 + (index * 5))),
            sigma: 0.04,
            sampleCount: 500,
          ),
        );
      }

      expect(decision.state, TrackingState.stationary);
      expect(
        decision.transition?.reason,
        'potential_motion_stationary_windows',
      );
    });

    test('keeps active tracking when speed is moving and sigma is low', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.activeTracking);
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 22,
          accuracyMeters: 15,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(minutes: 10)),
          sigma: 0.05,
          sampleCount: 500,
        ),
      );

      expect(decision.state, TrackingState.activeTracking);
      expect(decision.didTransition, isFalse);
    });

    test('returns to stationary after two minutes of zero speed and low sigma',
        () {
      final fsm = AcquisitionFsm(initialState: TrackingState.activeTracking);
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
  });
}

void _enterPotentialMotion(AcquisitionFsm fsm, DateTime timestamp) {
  _applyMotionWindow(fsm, timestamp);
  _applyMotionWindow(fsm, timestamp.add(const Duration(seconds: 2)));
  _applyMotionWindow(fsm, timestamp.add(const Duration(seconds: 4)));
  _applyMotionWindow(fsm, timestamp.add(const Duration(seconds: 6)));
}

FsmDecision _applyMotionWindow(
  AcquisitionFsm fsm,
  DateTime timestamp, {
  int sampleCount = 20,
}) {
  return fsm.apply(
    MotionWindowEvaluated(
      timestamp: timestamp,
      sigma: 1.2,
      sampleCount: sampleCount,
    ),
  );
}

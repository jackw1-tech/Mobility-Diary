import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionFsm', () {
    test('starts in stationary with the lightweight GPS profile', () {
      final decision = AcquisitionFsm().apply(
        MotionWindowEvaluated(
          timestamp: DateTime.utc(2026, 1, 1),
          sigma: 0.1,
          sampleCount: 20,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.samplingProfile.accelerometerHz, 10);
      expect(decision.samplingProfile.gyroscopeHz, 0);
      expect(decision.samplingProfile.gpsEnabled, isTrue);
      expect(decision.samplingProfile.gpsInterval, const Duration(seconds: 5));
      expect(decision.samplingProfile.gpsDistanceFilterMeters, 5);
      expect(decision.samplingProfile.gpsAccuracy,
          GpsAccuracyProfile.highAccuracy);
      expect(decision.samplingProfile.harWindowEnabled, isFalse);
      expect(decision.didTransition, isFalse);
    });

    test('requires fresh GPS speed and sigma to enter movement', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      final gpsOnly = fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
      );
      final sigmaOnly = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 1)),
          sigma: 1.4,
          sampleCount: 20,
        ),
      );

      expect(gpsOnly.state, TrackingState.stationary);
      expect(sigmaOnly.state, TrackingState.stationary);
      expect(sigmaOnly.didTransition, isFalse);
    });

    test('enters movement after fifteen seconds of concordant moving evidence',
        () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 1.4,
          sampleCount: 20,
        ),
      );
      final before = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 14)),
          sigma: 1.4,
          sampleCount: 20,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 15)),
          sigma: 1.4,
          sampleCount: 20,
        ),
      );

      expect(before.state, TrackingState.stationary);
      expect(before.didTransition, isFalse);
      expect(decision.state, TrackingState.movement);
      expect(decision.transition?.reason, 'moving_evidence_confirmed');
      expect(decision.samplingProfile.accelerometerHz, 100);
      expect(decision.samplingProfile.gyroscopeHz, 100);
      expect(decision.samplingProfile.gpsInterval, const Duration(seconds: 2));
      expect(decision.samplingProfile.gpsDistanceFilterMeters, 3);
      expect(decision.samplingProfile.persistSensorWindows, isTrue);
      expect(decision.samplingProfile.persistGpsPoints, isTrue);
    });

    test('does not enter movement when GPS speed becomes stale', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 21)),
          sigma: 1.4,
          sampleCount: 20,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.didTransition, isFalse);
    });

    test('stationary evidence resets the moving countdown', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 1.4,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 5)),
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 5)),
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 6)),
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 20)),
          sigma: 1.4,
          sampleCount: 20,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.didTransition, isFalse);
    });

    test('uncertain evidence resets the moving countdown', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 1.4,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 5)),
          sigma: 1,
          sampleCount: 20,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 20)),
          sigma: 1.4,
          sampleCount: 20,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.didTransition, isFalse);
    });

    test('requires fresh GPS speed and sigma to leave movement', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      final sigmaOnly = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      final gpsOnly = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 11)),
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );

      expect(sigmaOnly.state, TrackingState.movement);
      expect(gpsOnly.state, TrackingState.movement);
      expect(gpsOnly.didTransition, isFalse);
    });

    test(
        'returns to stationary after one hundred twenty seconds of concordant '
        'stationary evidence', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      final before = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 119)),
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 120)),
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );

      expect(before.state, TrackingState.movement);
      expect(before.didTransition, isFalse);
      expect(decision.state, TrackingState.stationary);
      expect(decision.transition?.reason, 'stationary_evidence_confirmed');
      expect(decision.samplingProfile.accelerometerHz, 10);
      expect(decision.samplingProfile.gyroscopeHz, 0);
      expect(decision.samplingProfile.gpsInterval, const Duration(seconds: 5));
    });

    test('moving evidence resets the stationary countdown', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 60)),
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 60)),
          sigma: 1.4,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 61)),
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );
      final decision = fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 180)),
          sigma: 0.1,
          sampleCount: 20,
        ),
      );

      expect(decision.state, TrackingState.movement);
      expect(decision.didTransition, isFalse);
    });

    test('brief uncertain evidence freezes the stationary countdown', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 100)),
          sigma: 1,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 115)),
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 120)),
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.transition?.reason, 'stationary_evidence_confirmed');
    });

    test('long uncertain evidence resets the stationary countdown', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now,
          sigma: 0.1,
          sampleCount: 20,
        ),
      );
      fsm.apply(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 30)),
          sigma: 1,
          sampleCount: 20,
        ),
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 120)),
          speedMetersPerSecond: 0.1,
          accuracyMeters: 8,
        ),
      );

      expect(decision.state, TrackingState.movement);
      expect(decision.didTransition, isFalse);
    });

    test('force-stationary mode closes movement immediately', () {
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);
      final now = DateTime.utc(2026, 1, 1);

      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 8,
          accuracyMeters: 8,
        ),
        evidenceMode: FsmEvidenceMode.forceStationary,
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.transition?.reason, 'background_inertial_stale');
    });

    test('force-stationary mode does not open movement from stationary', () {
      final fsm = AcquisitionFsm();
      final now = DateTime.utc(2026, 1, 1);

      fsm.apply(
        GpsFixReceived(
          timestamp: now,
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
        evidenceMode: FsmEvidenceMode.forceStationary,
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 20)),
          speedMetersPerSecond: 1.2,
          accuracyMeters: 8,
        ),
        evidenceMode: FsmEvidenceMode.forceStationary,
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.didTransition, isFalse);
    });
  });
}

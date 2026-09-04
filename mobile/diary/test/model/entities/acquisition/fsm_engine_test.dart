import 'package:diary/model/entities/acquisition/fsm_engine.dart';
import 'package:diary/model/entities/acquisition/tracking_event.dart';
import 'package:diary/model/entities/acquisition/tracking_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('an unavailable GPS speed does not become stationary speed zero', () {
    final startedAt = DateTime.utc(2026, 9, 4, 10);
    final fsm = AcquisitionFsm(
      config: const FsmConfig(gpsSpeedFreshness: Duration(seconds: 5)),
    );
    fsm.apply(
      GpsFixReceived(timestamp: startedAt, speedMetersPerSecond: 3),
    );
    final later = startedAt.add(const Duration(seconds: 6));
    fsm.apply(
      MotionWindowEvaluated(timestamp: later, sigma: 0.1),
    );

    final decision = fsm.apply(
      GpsFixReceived(
        timestamp: later,
        speedMetersPerSecond: null,
        platformSpeedMetersPerSecond: -1,
      ),
    );

    expect(decision.diagnostics.evidence, MotionEvidence.uncertain);
    expect(decision.diagnostics.gpsSpeedMetersPerSecond, 3);
    expect(decision.diagnostics.gpsSpeedAge, const Duration(seconds: 6));
  });

  group('AcquisitionFsm', () {
    test('starts movement from sustained vehicle GPS even with low motion', () {
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final fsm = AcquisitionFsm();

      fsm.apply(
        MotionWindowEvaluated(
          timestamp: startedAt,
          sigma: 0.3,
        ),
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: startedAt,
          speedMetersPerSecond: 8,
        ),
      );

      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 6)),
          speedMetersPerSecond: 8,
        ),
      );

      expect(decision.state, TrackingState.movement);
      expect(decision.transition?.from, TrackingState.stationary);
      expect(decision.transition?.to, TrackingState.movement);
    });

    test('stays in movement in background while GPS still reports speed', () {
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);

      // App in background: nessuna finestra inerziale, solo fix GPS da auto in
      // corsa. Un viaggio del genere non deve mai essere dichiarato fermo.
      var decision = fsm.apply(
        GpsFixReceived(timestamp: startedAt, speedMetersPerSecond: 25),
        evidenceMode: FsmEvidenceMode.gpsOnly,
      );
      expect(decision.state, TrackingState.movement);

      decision = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(minutes: 20)),
          speedMetersPerSecond: 25,
        ),
        evidenceMode: FsmEvidenceMode.gpsOnly,
      );

      expect(decision.state, TrackingState.movement);
      expect(decision.didTransition, isFalse);
    });

    test('settles to stationary in background when GPS speed drops', () {
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);

      fsm.apply(
        GpsFixReceived(timestamp: startedAt, speedMetersPerSecond: 0.1),
        evidenceMode: FsmEvidenceMode.gpsOnly,
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 121)),
          speedMetersPerSecond: 0.1,
        ),
        evidenceMode: FsmEvidenceMode.gpsOnly,
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.transition?.from, TrackingState.movement);
      expect(decision.transition?.to, TrackingState.stationary);
    });

    test('requires both motion and walking speed in strict sensor mode', () {
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final fsm = AcquisitionFsm();

      fsm.apply(
        MotionWindowEvaluated(
          timestamp: startedAt,
          sigma: 2,
        ),
      );
      final lowSpeed = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt,
          speedMetersPerSecond: 0.2,
        ),
      );
      final walkingStarted = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 1)),
          speedMetersPerSecond: 1.4,
        ),
      );
      final confirmed = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 7)),
          speedMetersPerSecond: 1.4,
        ),
      );

      expect(lowSpeed.state, TrackingState.stationary);
      expect(walkingStarted.didTransition, isFalse);
      expect(confirmed.state, TrackingState.movement);
    });

    test('does not stop when stationary evidence is interrupted by movement',
        () {
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);

      fsm.apply(
        GpsFixReceived(timestamp: startedAt, speedMetersPerSecond: 0.1),
        evidenceMode: FsmEvidenceMode.gpsOnly,
      );
      fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 60)),
          speedMetersPerSecond: 2,
        ),
        evidenceMode: FsmEvidenceMode.gpsOnly,
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 121)),
          speedMetersPerSecond: 0.1,
        ),
        evidenceMode: FsmEvidenceMode.gpsOnly,
      );

      expect(decision.state, TrackingState.movement);
      expect(decision.didTransition, isFalse);
    });

    test('stale signals cannot trigger a strict-sensor transition', () {
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final fsm = AcquisitionFsm();

      fsm.apply(
        MotionWindowEvaluated(
          timestamp: startedAt,
          sigma: 2,
        ),
      );
      final decision = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 11)),
          speedMetersPerSecond: 1.5,
        ),
      );

      expect(decision.state, TrackingState.stationary);
      expect(decision.didTransition, isFalse);
    });

    test('explains whether evidence or debounce blocks stationary', () {
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final fsm = AcquisitionFsm(initialState: TrackingState.movement);

      fsm.apply(
        MotionWindowEvaluated(
          timestamp: startedAt,
          sigma: 0.2,
        ),
      );
      final timerStarted = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt,
          speedMetersPerSecond: 0.1,
        ),
      );
      final staleGps = fsm.apply(
        MotionWindowEvaluated(
          timestamp: startedAt.add(const Duration(seconds: 30)),
          sigma: 0.2,
        ),
      );
      final reset = fsm.apply(
        GpsFixReceived(
          timestamp: startedAt.add(const Duration(seconds: 31)),
          speedMetersPerSecond: 3,
        ),
      );

      expect(timerStarted.diagnostics.evidence, MotionEvidence.stationary);
      expect(
        timerStarted.diagnostics.stationaryTimerAction,
        StationaryTimerAction.started,
      );
      expect(staleGps.diagnostics.evidence, MotionEvidence.uncertain);
      expect(
        staleGps.diagnostics.stationaryTimerAction,
        StationaryTimerAction.preserved,
      );
      expect(
        staleGps.diagnostics.stationaryEvidenceElapsed,
        const Duration(seconds: 30),
      );
      expect(reset.diagnostics.evidence, MotionEvidence.moving);
      expect(
        reset.diagnostics.stationaryTimerAction,
        StationaryTimerAction.reset,
      );
    });
  });
}

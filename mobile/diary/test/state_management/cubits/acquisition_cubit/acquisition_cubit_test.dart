import 'dart:async';

import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionCubit', () {
    late _FakeAcquisitionRepository repository;
    late AcquisitionCubit cubit;

    setUp(() {
      repository = _FakeAcquisitionRepository();
      cubit = AcquisitionCubit(
        trackingRepository: repository,
        syncRepository: repository,
      );
    });

    tearDown(() async {
      await cubit.close();
      repository.dispose();
    });

    test('resumes pending sync on startup', () async {
      await _pumpEventQueue();

      expect(repository.resumeSyncCount, 1);
    });

    test('forwards live snapshots and accumulates route points', () async {
      repository.emitSnapshot(
        _trackingSnapshot(latitude: 45.46, longitude: 9.19),
      );
      await _pumpEventQueue();

      expect(cubit.state.status, AcquisitionCubitStatus.tracking);
      expect(cubit.state.snapshot.latitude, 45.46);
      expect(cubit.state.routePoints, hasLength(1));
      expect(cubit.state.routePoints.single.latitude, 45.46);
    });

    test('startTracking delegates and resets transient replay completion',
        () async {
      repository.current = _trackingSnapshot(latitude: 45, longitude: 9);
      cubit.emit(
        AcquisitionCubitState.fromSnapshot(
          AcquisitionSnapshot.idle(),
          completedReplayTripId: 99,
          routePoints: const [],
        ),
      );

      await cubit.startTracking();

      expect(repository.startTrackingCount, 1);
      expect(cubit.state.isTracking, isTrue);
      expect(cubit.state.completedReplayTripId, isNull);
      expect(cubit.state.routePoints, isEmpty);
    });

    test('stopTracking delegates to stopReplay while replaying', () async {
      repository.current =
          _trackingSnapshot(isReplay: true, replaySecondsRemaining: 10);
      repository.replayStopResult = const ReplayStopResult(tripId: 123);
      repository.emitSnapshot(repository.current);
      await _pumpEventQueue();

      await cubit.stopTracking();

      expect(repository.stopTrackingCount, 0);
      expect(repository.stopReplayCount, 1);
      expect(cubit.state.completedReplayTripId, 123);
    });

    test('ingestEvent delegates to repository and refreshes current snapshot',
        () async {
      repository.current = _trackingSnapshot(
        latitude: 45.1,
        longitude: 9.2,
        speedMetersPerSecond: 3,
      );

      await cubit.ingestEvent(
        GpsFixReceived(
          timestamp: DateTime.utc(2026, 1, 1, 10),
          latitude: 45.1,
          longitude: 9.2,
          speedMetersPerSecond: 3,
        ),
      );

      expect(repository.ingestedEvents, hasLength(1));
      expect(cubit.state.latestSpeedMetersPerSecond, 3);
      expect(cubit.state.latestPosition?.longitude, 9.2);
    });

    test('dismissNonRecoverableSync clears only final failures', () async {
      cubit.emit(
        cubit.state.copyWith(
          syncSnapshot: const AcquisitionSyncSnapshot(
            status: AcquisitionSyncStatus.failedFinal,
            localSessionId: 'local-1',
          ),
        ),
      );

      cubit.dismissNonRecoverableSync();

      expect(cubit.state.syncSnapshot.status, AcquisitionSyncStatus.none);
    });
  });
}

AcquisitionSnapshot _trackingSnapshot({
  bool isReplay = false,
  int? replaySecondsRemaining,
  double? latitude,
  double? longitude,
  double speedMetersPerSecond = 1,
}) {
  return AcquisitionSnapshot(
    isTracking: true,
    trackingState: TrackingState.movement,
    samplingProfile: const SamplingProfile.movement(),
    latestSigma: 0.8,
    latestSpeedMetersPerSecond: speedMetersPerSecond,
    lastTransition: null,
    updatedAt: DateTime.utc(2026, 1, 1, 10),
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: latitude == null ? null : 5,
    replaySecondsRemaining: replaySecondsRemaining,
    isReplay: isReplay,
  );
}

Future<void> _pumpEventQueue() => Future<void>.delayed(Duration.zero);

class _FakeAcquisitionRepository implements AcquisitionRepository {
  final StreamController<AcquisitionSnapshot> _snapshots =
      StreamController<AcquisitionSnapshot>.broadcast();
  final StreamController<AcquisitionSyncSnapshot> _syncSnapshots =
      StreamController<AcquisitionSyncSnapshot>.broadcast();

  AcquisitionSnapshot current = AcquisitionSnapshot.idle(
    updatedAt: DateTime.utc(2026),
  );
  AcquisitionSyncSnapshot syncCurrent = const AcquisitionSyncSnapshot.none();
  ReplayStopResult replayStopResult = const ReplayStopResult(tripId: null);
  final List<TrackingEvent> ingestedEvents = [];
  int resumeSyncCount = 0;
  int startTrackingCount = 0;
  int stopTrackingCount = 0;
  int stopReplayCount = 0;

  @override
  Stream<AcquisitionSnapshot> get snapshots => _snapshots.stream;

  @override
  Stream<AcquisitionSyncSnapshot> get syncSnapshots => _syncSnapshots.stream;

  @override
  AcquisitionSnapshot get currentSnapshot => current;

  @override
  AcquisitionSyncSnapshot get currentSyncSnapshot => syncCurrent;

  void emitSnapshot(AcquisitionSnapshot snapshot) {
    current = snapshot;
    _snapshots.add(snapshot);
  }

  @override
  Future<void> startTracking() async {
    startTrackingCount += 1;
  }

  @override
  Future<void> stopTracking() async {
    stopTrackingCount += 1;
    current = AcquisitionSnapshot.idle(updatedAt: DateTime.utc(2026, 1, 1, 11));
  }

  @override
  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  }) async {}

  @override
  Future<ReplayStopResult> stopReplay() async {
    stopReplayCount += 1;
    current = AcquisitionSnapshot.idle(updatedAt: DateTime.utc(2026, 1, 1, 11));
    return replayStopResult;
  }

  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    ingestedEvents.add(event);
  }

  @override
  Future<void> resumeSync() async {
    resumeSyncCount += 1;
  }

  @override
  Future<void> purgeLocalDataForRemoteTrip(int tripId) async {}

  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async {
    return const [];
  }

  @override
  Future<List<List<double>>> currentSensorWindow() async {
    return const [];
  }

  @override
  void dispose() {
    unawaited(_snapshots.close());
    unawaited(_syncSnapshots.close());
  }
}

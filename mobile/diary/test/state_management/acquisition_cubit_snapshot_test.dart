import 'dart:async';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('one strategy snapshot is published once by the repository', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    final repository = AcquisitionRepositoryImpl(
      database: database,
      enableRuntime: false,
    );
    final snapshots = <AcquisitionSnapshot>[];
    final subscription = repository.snapshots.listen(snapshots.add);
    addTearDown(subscription.cancel);
    addTearDown(repository.dispose);

    await repository.startTracking();

    expect(snapshots, hasLength(1));
    expect(snapshots.single.isTracking, isTrue);
    expect(repository.currentSnapshot, same(snapshots.single));
  });

  test('one repository snapshot produces one cubit state', () async {
    final trackingRepository = _FakeTrackingRepository();
    final syncRepository = _FakeSyncRepository();
    final cubit = AcquisitionCubit(
      trackingRepository: trackingRepository,
      syncRepository: syncRepository,
    );
    addTearDown(() async {
      await cubit.close();
      await trackingRepository.close();
    });

    // Let the opportunistic restore started by the constructor settle before
    // observing the event under test.
    await Future<void>.delayed(Duration.zero);
    final emittedStates = <Object>[];
    final subscription = cubit.stream.listen(emittedStates.add);
    addTearDown(subscription.cancel);

    await cubit.ingestEvent(
      MotionWindowEvaluated(
        timestamp: DateTime.utc(2026, 9, 4, 10),
        sigma: 1.25,
      ),
    );

    expect(emittedStates, hasLength(1));
    expect(cubit.state.latestSigma, 1.25);
  });

  test('live tracking publishes GPS points for the map route', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    final repository = AcquisitionRepositoryImpl(
      database: database,
      enableRuntime: false,
    );
    final cubit = AcquisitionCubit(
      trackingRepository: repository,
      syncRepository: repository,
    );
    addTearDown(() async {
      await cubit.close();
      repository.dispose();
    });

    await cubit.restoreActiveTrip();
    await cubit.startTracking();
    await cubit.ingestEvent(
      GpsFixReceived(
        timestamp: DateTime.utc(2026, 9, 4, 10),
        latitude: 45.4642,
        longitude: 9.19,
        accuracyMeters: 5,
        speedMetersPerSecond: 1.5,
      ),
    );

    expect(cubit.state.isTracking, isTrue);
    expect(cubit.state.routePoints, hasLength(1));
    expect(cubit.state.routePoints.single.latitude, 45.4642);
    expect(cubit.state.routePoints.single.longitude, 9.19);
  });

  test('returns the finalized diagnostics report when live tracking stops',
      () async {
    final trackingRepository = _FakeTrackingRepository();
    final syncRepository = _FakeSyncRepository();
    final timestamp = DateTime.utc(2026, 9, 4, 10);
    final report = AcquisitionDiagnosticsReport(
      sessionId: 'session-id',
      filePath: '/tmp/fsm.jsonl',
      fileName: 'fsm.jsonl',
      content: '{}\n',
      sizeBytes: 3,
      decisionCount: 1,
      startedAt: timestamp,
      endedAt: timestamp.add(const Duration(minutes: 1)),
    );
    trackingRepository.stopReport = report;
    final cubit = AcquisitionCubit(
      trackingRepository: trackingRepository,
      syncRepository: syncRepository,
    );
    addTearDown(() async {
      await cubit.close();
      await trackingRepository.close();
    });

    expect(await cubit.stopTracking(), same(report));
  });

  test('coalesces concurrent live tracking starts', () async {
    final startCompleter = Completer<void>();
    final trackingRepository = _FakeTrackingRepository(
      startCompleter: startCompleter,
    );
    final cubit = AcquisitionCubit(
      trackingRepository: trackingRepository,
      syncRepository: _FakeSyncRepository(),
    );
    addTearDown(() async {
      await cubit.close();
      await trackingRepository.close();
    });
    await Future<void>.delayed(Duration.zero);

    final first = cubit.startTracking();
    final second = cubit.startTracking();
    await Future<void>.delayed(Duration.zero);

    expect(trackingRepository.startCalls, 1);

    startCompleter.complete();
    await Future.wait([first, second]);
  });

  test('coalesces concurrent live tracking stops', () async {
    final stopCompleter = Completer<AcquisitionDiagnosticsReport?>();
    final trackingRepository = _FakeTrackingRepository(
      initialSnapshot: _trackingSnapshot(),
      stopCompleter: stopCompleter,
    );
    final cubit = AcquisitionCubit(
      trackingRepository: trackingRepository,
      syncRepository: _FakeSyncRepository(),
    );
    addTearDown(() async {
      await cubit.close();
      await trackingRepository.close();
    });
    await Future<void>.delayed(Duration.zero);

    final first = cubit.stopTracking();
    final second = cubit.stopTracking();
    await Future<void>.delayed(Duration.zero);

    expect(trackingRepository.stopCalls, 1);

    stopCompleter.complete(null);
    await Future.wait([first, second]);
  });
}

class _FakeTrackingRepository implements AcquisitionTrackingRepository {
  final _snapshots =
      StreamController<AcquisitionSnapshot>.broadcast(sync: true);
  late AcquisitionSnapshot _currentSnapshot;
  final Completer<void>? startCompleter;
  final Completer<AcquisitionDiagnosticsReport?>? stopCompleter;
  AcquisitionDiagnosticsReport? stopReport;
  int startCalls = 0;
  int stopCalls = 0;

  _FakeTrackingRepository({
    AcquisitionSnapshot? initialSnapshot,
    this.startCompleter,
    this.stopCompleter,
  }) : _currentSnapshot = initialSnapshot ?? AcquisitionSnapshot.idle();

  @override
  Stream<AcquisitionSnapshot> get snapshots => _snapshots.stream;

  @override
  AcquisitionSnapshot get currentSnapshot => _currentSnapshot;

  @override
  Future<void> ingestEvent(TrackingEvent event) async {
    _currentSnapshot = AcquisitionSnapshot(
      isTracking: true,
      trackingState: TrackingState.stationary,
      latestSigma: (event as MotionWindowEvaluated).sigma,
      latestSpeedMetersPerSecond: 0,
      lastTransition: null,
      updatedAt: event.timestamp,
    );
    _snapshots.add(_currentSnapshot);
  }

  @override
  Future<void> startTracking() async {
    startCalls += 1;
    await startCompleter?.future;
  }

  @override
  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  }) async {}

  @override
  Future<AcquisitionDiagnosticsReport?> stopTracking() {
    stopCalls += 1;
    return stopCompleter?.future ?? Future.value(stopReport);
  }

  @override
  Future<ReplayStopResult> stopReplay() async {
    return const ReplayStopResult(tripId: null);
  }

  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async => const [];

  @override
  Future<List<List<double>>> currentSensorWindow() async => const [];

  @override
  void dispose() {}

  Future<void> close() => _snapshots.close();
}

AcquisitionSnapshot _trackingSnapshot() => AcquisitionSnapshot(
      isTracking: true,
      trackingState: TrackingState.stationary,
      latestSigma: 0,
      latestSpeedMetersPerSecond: 0,
      lastTransition: null,
      updatedAt: DateTime.utc(2026, 9, 4, 10),
    );

class _FakeSyncRepository implements AcquisitionSyncRepository {
  @override
  AcquisitionSyncSnapshot get currentSyncSnapshot =>
      const AcquisitionSyncSnapshot.none();

  @override
  Stream<AcquisitionSyncSnapshot> get syncSnapshots => const Stream.empty();

  @override
  Future<void> resumeSync() async {}
}

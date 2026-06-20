import 'dart:convert';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/runtime/acquisition_sensor_runtime.dart';
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
      expect(repository.currentSnapshot.samplingProfile.gpsEnabled, isTrue);
      expect(
        repository.currentSnapshot.samplingProfile.gpsInterval,
        const Duration(seconds: 20),
      );
      expect(
        repository.currentSnapshot.samplingProfile.gpsDistanceFilterMeters,
        30,
      );
      expect(
          repository.currentSnapshot.samplingProfile.persistGpsPoints, isTrue);
      expect(await database.acquisitionDao.countSessions(), 1);

      await repository.stopTracking();

      expect(repository.currentSnapshot.isTracking, isFalse);
      expect(
          repository.currentSnapshot.trackingState, TrackingState.stationary);
      final sessions = await database.acquisitionDao.allSessions();
      expect(sessions.single.endedAt, isNotNull);
    });

    test('stores sparse GPS points while stationary for stay detection',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      await repository.ingestEvent(
        GpsFixReceived(
          timestamp: now,
          latitude: 44.49491,
          longitude: 11.34261,
          speedMetersPerSecond: 0,
          accuracyMeters: 25,
        ),
      );

      final sessions = await database.acquisitionDao.allSessions();

      expect(
          repository.currentSnapshot.trackingState, TrackingState.stationary);
      expect(
        await database.acquisitionDao.countGpsPointsForSession(
          sessions.single.id,
        ),
        1,
      );
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
      expect(
          repository.currentSnapshot.samplingProfile.harWindowEnabled, isTrue);
      expect(
        repository.currentSnapshot.samplingProfile.persistSensorWindows,
        isFalse,
      );

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

    test('persists buffered HAR windows when active tracking is confirmed',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final runtime = _FakeAcquisitionSensorRuntime();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      await _enterPotentialMotion(repository, now);
      await runtime.completeWindow(_harWindow(startedAt: now));

      final sessions = await database.acquisitionDao.allSessions();
      expect(
        await database.acquisitionDao.countSensorWindowsForSession(
          sessions.single.id,
        ),
        0,
      );

      await repository.ingestEvent(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 15)),
          latitude: 44.49491,
          longitude: 11.34261,
          speedMetersPerSecond: 0.9,
          accuracyMeters: 12,
        ),
      );

      final windows = await database.acquisitionDao.sensorWindowsForSession(
        sessions.single.id,
      );
      final matrix = jsonDecode(windows.single.matrixJson) as List<dynamic>;

      expect(windows, hasLength(1));
      expect(windows.single.sampleCount, 500);
      expect(windows.single.frequencyHz, 100);
      expect(matrix, hasLength(500));
      expect(matrix.first as List<dynamic>, hasLength(9));
    });

    test('persists new HAR windows while active tracking is running', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final runtime = _FakeAcquisitionSensorRuntime();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      await _enterPotentialMotion(repository, now);
      await repository.ingestEvent(
        GpsFixReceived(
          timestamp: now.add(const Duration(seconds: 15)),
          latitude: 44.49491,
          longitude: 11.34261,
          speedMetersPerSecond: 0.9,
          accuracyMeters: 12,
        ),
      );
      await runtime.completeWindow(
        _harWindow(startedAt: now.add(const Duration(seconds: 20))),
      );

      final sessions = await database.acquisitionDao.allSessions();

      expect(
        await database.acquisitionDao.countSensorWindowsForSession(
          sessions.single.id,
        ),
        1,
      );
    });

    test('stop enqueues a persistent SyncJob without blocking on network',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);

      await repository.startTracking();
      final sessions = await database.acquisitionDao.allSessions();
      final sessionId = sessions.single.id;

      await repository.stopTracking();

      final job = await database.acquisitionDao.syncJobForSession(sessionId);
      expect(job, isNotNull);
      expect(job!.coreStatus, syncJobPending);
      expect(job.attempts, 0);
      expect(job.remoteIngestionId, isNull);

      // Claimable subito (nessun next_retry_at futuro).
      final claimable = await database.acquisitionDao
          .claimableSyncJobs(DateTime.now().toUtc());
      expect(
        claimable.where((j) => j.localSessionId == sessionId),
        hasLength(1),
      );
    });

    test('exposes the latest SyncJob as a UI sync snapshot on stop', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);

      await repository.startTracking();
      final syncSnapshotFuture = repository.syncSnapshots.firstWhere(
        (snapshot) => snapshot.status == AcquisitionSyncStatus.pending,
      );

      await repository.stopTracking();
      final syncSnapshot = await syncSnapshotFuture;

      expect(syncSnapshot.status, AcquisitionSyncStatus.pending);
      expect(syncSnapshot.localSessionId, isNotNull);
      expect(syncSnapshot.remoteIngestionId, isNull);
      expect(
          repository.currentSyncSnapshot.status, AcquisitionSyncStatus.pending);
    });

    test('createSyncJobIfAbsent is idempotent per session', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dao = database.acquisitionDao;
      await dao.createSession(
        id: 'sess-1',
        deviceId: 'dev',
        startedAt: DateTime.utc(2026, 1, 1),
      );

      final first = await dao.createSyncJobIfAbsent('sess-1');
      final second = await dao.createSyncJobIfAbsent('sess-1');

      expect(first.id, second.id);
      final claimable = await dao.claimableSyncJobs(DateTime.now().toUtc());
      expect(claimable, hasLength(1));
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

HarSensorWindow _harWindow({required DateTime startedAt}) {
  return HarSensorWindow(
    startedAt: startedAt,
    endedAt: startedAt.add(HarSensorWindow.targetDuration),
    accelerometerHz: HarSensorWindow.targetSamplingHz,
    gyroscopeHz: HarSensorWindow.targetSamplingHz,
    magnetometerHz: HarSensorWindow.targetSamplingHz,
    samples: [
      _harSample(startedAt: startedAt, value: 0),
      _harSample(
        startedAt: startedAt.add(HarSensorWindow.targetDuration),
        value: 10,
      ),
    ],
  );
}

HarSensorSample _harSample({
  required DateTime startedAt,
  required double value,
}) {
  return HarSensorSample(
    timestamp: startedAt,
    accX: value,
    accY: value,
    accZ: value,
    gyrX: value,
    gyrY: value,
    gyrZ: value,
    magX: value,
    magY: value,
    magZ: value,
  );
}

class _FakeAcquisitionSensorRuntime extends AcquisitionSensorRuntime {
  final List<HarSensorWindow> windows = [];
  HarWindowSink? harWindowSink;
  SamplingProfile? latestProfile;

  @override
  List<HarSensorWindow> get completedHarWindows {
    return List<HarSensorWindow>.unmodifiable(windows);
  }

  @override
  Future<void> start({
    required SamplingProfile profile,
    required AcquisitionRuntimeEventSink onEvent,
    HarWindowSink? onHarWindow,
  }) async {
    latestProfile = profile;
    harWindowSink = onHarWindow;
  }

  @override
  Future<void> configure(SamplingProfile profile) async {
    latestProfile = profile;
    if (!profile.harWindowEnabled) {
      windows.clear();
    }
  }

  @override
  Future<void> stop() async {
    windows.clear();
    harWindowSink = null;
    latestProfile = null;
  }

  Future<void> completeWindow(HarSensorWindow window) async {
    windows.insert(0, window);
    await harWindowSink?.call(window);
  }
}

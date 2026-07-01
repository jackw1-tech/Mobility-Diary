import 'dart:async';
import 'dart:convert';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/runtime/acquisition_sensor_runtime.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
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

    test('start stores the backend active ingestion id locally', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final runtime = _FakeAcquisitionSensorRuntime();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
        ingestionApi: _FakeTripIngestionApi(ingestionId: 42),
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.startTracking();

      final session = (await database.acquisitionDao.allSessions()).single;
      expect(session.remoteIngestionId, 42);
      expect(session.deviceId, 'stable-device');
      expect(runtime.latestProfile, const SamplingProfile.stationary());
      expect(repository.currentSnapshot.isTracking, isTrue);
    });

    test('start sends the stable device id to the backend', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.startTracking();

      expect(api.startedDeviceIds, ['stable-device']);
    });

    test('sends scheduled heartbeat while tracking', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi(ingestionId: 42);
      late _ManualTimer heartbeatTimer;
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
        heartbeatTimerFactory: (duration, callback) {
          expect(duration, const Duration(minutes: 5));
          heartbeatTimer = _ManualTimer(callback);
          return heartbeatTimer;
        },
      );
      addTearDown(repository.dispose);

      await repository.startTracking();
      heartbeatTimer.fire();
      await Future<void>.delayed(Duration.zero);

      expect(api.heartbeatCalls, hasLength(1));
      expect(api.heartbeatCalls.single.ingestionId, 42);
      expect(api.heartbeatCalls.single.deviceId, 'stable-device');
    });

    test('sends heartbeat when app returns to foreground', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi(ingestionId: 42);
      final lifecycle = StreamController<AppLifecycleState>();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
        lifecycleEvents: lifecycle.stream,
      );
      addTearDown(repository.dispose);
      addTearDown(lifecycle.close);

      await repository.startTracking();
      lifecycle.add(AppLifecycleState.resumed);
      await Future<void>.delayed(Duration.zero);

      expect(api.heartbeatCalls, hasLength(1));
      expect(api.heartbeatCalls.single.ingestionId, 42);
    });

    test('heartbeat failure does not stop local tracking', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi(
        ingestionId: 42,
        shouldFailHeartbeat: true,
      );
      late _ManualTimer heartbeatTimer;
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
        heartbeatTimerFactory: (_, callback) {
          heartbeatTimer = _ManualTimer(callback);
          return heartbeatTimer;
        },
      );
      addTearDown(repository.dispose);

      await repository.startTracking();
      heartbeatTimer.fire();
      await Future<void>.delayed(Duration.zero);

      expect(api.heartbeatCalls, hasLength(1));
      expect(repository.currentSnapshot.isTracking, isTrue);
    });

    test('start does not create a local session when backend start fails',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final runtime = _FakeAcquisitionSensorRuntime();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
        ingestionApi: _FakeTripIngestionApi(shouldFailStart: true),
      );
      addTearDown(repository.dispose);

      await expectLater(
        repository.startTracking(),
        throwsA(isA<StartRequiresConnectionException>()),
      );

      expect(await database.acquisitionDao.countSessions(), 0);
      expect(runtime.latestProfile, isNull);
      expect(repository.currentSnapshot.isTracking, isFalse);
    });

    test('start conflict resumes a same-device open SQLite session', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final runtime = _FakeAcquisitionSensorRuntime();
      final api = _FakeTripIngestionApi(
        conflictActive: _active(
          clientSessionId: 'remote-session',
          deviceId: 'stable-device',
        ),
      );
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);
      await database.acquisitionDao.createSession(
        id: 'remote-session',
        deviceId: 'stable-device',
        startedAt: DateTime.utc(2026, 1, 1, 8),
        remoteIngestionId: 7,
      );

      await repository.startTracking();

      expect(repository.currentSnapshot.isTracking, isTrue);
      expect(runtime.latestProfile, const SamplingProfile.stationary());
      expect(await database.acquisitionDao.countSessions(), 1);
      expect(api.abandonedIngestionIds, isEmpty);
    });

    test('start conflict abandons same-device remote lock without SQLite',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi(
        conflictActive: _active(
          clientSessionId: 'lost-session',
          deviceId: 'stable-device',
        ),
        conflictOnce: true,
      );
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.startTracking();

      final session = (await database.acquisitionDao.allSessions()).single;
      expect(session.id, isNot('lost-session'));
      expect(session.deviceId, 'stable-device');
      expect(api.abandonedIngestionIds, [7]);
      expect(api.startCallCount, 2);
    });

    test('start conflict from another device is blocked', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi(
        conflictActive: _active(deviceId: 'other-device'),
      );
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await expectLater(
        repository.startTracking(),
        throwsA(isA<ActiveTripOnAnotherDeviceException>()),
      );

      expect(await database.acquisitionDao.countSessions(), 0);
      expect(api.abandonedIngestionIds, isEmpty);
    });

    test('resumeSync abandons same-device remote lock without SQLite',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi(
        activeIngestion: _active(
          clientSessionId: 'missing-local-session',
          deviceId: 'stable-device',
        ),
      );
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.resumeSync();

      expect(api.activeLookupCount, 1);
      expect(api.abandonedIngestionIds, [7]);
      expect(repository.currentSnapshot.isTracking, isFalse);
    });

    test(
        'resumeSync does not abandon a stopped session with a pending core sync',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final dao = database.acquisitionDao;
      await dao.createSession(
        id: 'stopped-pending-session',
        deviceId: 'stable-device',
        startedAt: DateTime.utc(2026, 1, 1, 8),
        remoteIngestionId: 42,
      );
      await dao.endSession(
        id: 'stopped-pending-session',
        endedAt: DateTime.utc(2026, 1, 1, 8, 30),
      );
      // Sync job ancora da inviare: coreStatus default PENDING (attivo).
      await dao.createSyncJobIfAbsent('stopped-pending-session');

      final api = _FakeTripIngestionApi(
        activeIngestion: _active(
          ingestionId: 42,
          clientSessionId: 'stopped-pending-session',
          deviceId: 'stable-device',
        ),
      );
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.resumeSync();

      // Il backend chiudera' l'ingestione quando arrivera' il core: non va
      // abbandonata, altrimenti il viaggio fermato andrebbe perso.
      expect(api.abandonedIngestionIds, isEmpty);
      expect(repository.currentSnapshot.isTracking, isFalse);
    });

    test('ingests FSM events and exposes movement transition snapshots',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      await _enterMovement(repository, now);

      expect(
        repository.currentSnapshot.trackingState,
        TrackingState.movement,
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
        isTrue,
      );

      final sessions = await database.acquisitionDao.allSessions();
      final transitions = await database.acquisitionDao.transitionsForSession(
        sessions.single.id,
      );
      expect(transitions.single.fromState, 'STATIONARY');
      expect(transitions.single.toState, 'MOVEMENT');
      expect(transitions.single.sigma, 1.2);
    });

    test('stores GPS points while movement tracking is active', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      await _enterMovement(repository, now);
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

      expect(repository.currentSnapshot.trackingState, TrackingState.movement);
      expect(
        await database.acquisitionDao.countGpsPointsForSession(
          sessions.single.id,
        ),
        1,
      );
    });

    test('persists buffered HAR windows when movement starts', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final runtime = _FakeAcquisitionSensorRuntime();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
      );
      addTearDown(repository.dispose);
      final now = DateTime.utc(2026, 1, 1);

      await repository.startTracking();
      for (var index = 0; index < 3; index += 1) {
        await repository.ingestEvent(
          MotionWindowEvaluated(
            timestamp: now.add(Duration(seconds: index * 2)),
            sigma: 1.2,
            sampleCount: 20,
          ),
        );
      }
      await runtime.completeWindow(_harWindow(startedAt: now));

      final sessions = await database.acquisitionDao.allSessions();
      expect(
        await database.acquisitionDao.countSensorWindowsForSession(
          sessions.single.id,
        ),
        0,
      );

      await repository.ingestEvent(
        MotionWindowEvaluated(
          timestamp: now.add(const Duration(seconds: 6)),
          sigma: 1.2,
          sampleCount: 20,
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

    test('persists new HAR windows while movement tracking is running',
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
      await _enterMovement(repository, now);
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
      final runtime = _FakeAcquisitionSensorRuntime();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
        ingestionApi: _FakeTripIngestionApi(ingestionId: 42),
        deviceIdProvider: () async => 'stable-device',
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
      await _enterMovement(repository, now.add(const Duration(seconds: 2)));
      await runtime.completeWindow(
        _harWindow(startedAt: now.add(const Duration(seconds: 20))),
      );
      final sessions = await database.acquisitionDao.allSessions();
      final sessionId = sessions.single.id;

      await repository.stopTracking();

      expect(runtime.latestProfile, isNull);
      final job = await database.acquisitionDao.syncJobForSession(sessionId);
      expect(job, isNotNull);
      expect(job!.coreStatus, syncJobPending);
      expect(job.attempts, 0);
      expect(job.remoteIngestionId, 42);
      expect(
        await database.acquisitionDao.countGpsPointsForSession(sessionId),
        1,
      );
      expect(
        await database.acquisitionDao.countTransitionsForSession(sessionId),
        1,
      );
      expect(
        await database.acquisitionDao.countSensorWindowsForSession(sessionId),
        1,
      );

      // Claimable subito (nessun next_retry_at futuro).
      final claimable = await database.acquisitionDao
          .claimableSyncJobs(DateTime.now().toUtc());
      expect(
        claimable.where((j) => j.localSessionId == sessionId),
        hasLength(1),
      );
    });

    test('start is blocked while stopped trip core sync is pending', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi(ingestionId: 42);
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.startTracking();
      await repository.stopTracking();

      await expectLater(
        repository.startTracking(),
        throwsA(isA<PendingTripSyncException>()),
      );
      expect(api.startCallCount, 1);
    });

    test('resumeSync restores an open local tracking session', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final runtime = _FakeAcquisitionSensorRuntime();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        runtime: runtime,
      );
      addTearDown(repository.dispose);
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      final transitionAt = startedAt.add(const Duration(minutes: 5));
      final gpsAt = startedAt.add(const Duration(minutes: 6));

      await dao.createSession(
        id: 'open-session',
        deviceId: 'dev',
        startedAt: startedAt,
      );
      await dao.insertTransition(
        sessionId: 'open-session',
        fromState: TrackingState.stationary.wireName,
        toState: TrackingState.movement.wireName,
        reason: 'movement_sigma_above_threshold',
        timestamp: transitionAt,
        sigma: 1.4,
        speedMps: 0.8,
      );
      await dao.insertGpsPoint(
        sessionId: 'open-session',
        latitude: 44.49491,
        longitude: 11.34261,
        timestamp: gpsAt,
        speedMps: 1.1,
        accuracyMeters: 12,
      );

      await repository.resumeSync();

      expect(repository.currentSnapshot.isTracking, isTrue);
      expect(repository.currentSnapshot.trackingState, TrackingState.movement);
      expect(
          repository.currentSnapshot.samplingProfile.harWindowEnabled, isTrue);
      expect(repository.currentSnapshot.latitude, 44.49491);
      expect(repository.currentSnapshot.longitude, 11.34261);
      expect(runtime.latestProfile, const SamplingProfile.movement());

      await repository.stopTracking();

      final session = await dao.findSession('open-session');
      final job = await dao.syncJobForSession('open-session');
      expect(session!.endedAt, isNotNull);
      expect(job, isNotNull);
    });

    test('currentSessionRoute returns the recorded path after a resume',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);

      await dao.createSession(
        id: 'route-session',
        deviceId: 'dev',
        startedAt: startedAt,
      );
      // Punti accettati (in ordine sparso): devono tornare in ordine cronologico.
      await dao.insertGpsPoint(
        sessionId: 'route-session',
        latitude: 44.10,
        longitude: 11.10,
        timestamp: startedAt.add(const Duration(minutes: 2)),
        speedMps: 1.0,
      );
      await dao.insertGpsPoint(
        sessionId: 'route-session',
        latitude: 44.20,
        longitude: 11.20,
        timestamp: startedAt.add(const Duration(minutes: 1)),
        speedMps: 1.0,
      );
      // Punto scartato: non deve comparire nel percorso.
      await dao.insertGpsPoint(
        sessionId: 'route-session',
        latitude: 0,
        longitude: 0,
        timestamp: startedAt.add(const Duration(minutes: 3)),
        speedMps: 0,
        accepted: false,
        rejectionReason: 'accuracy',
      );

      expect(await repository.currentSessionRoute(), isEmpty);

      await repository.resumeSync();

      final route = await repository.currentSessionRoute();
      expect(route, [
        const AcquisitionRoutePoint(44.20, 11.20),
        const AcquisitionRoutePoint(44.10, 11.10),
      ]);
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

    test('failed-final sync job does not block a new local start', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final dao = database.acquisitionDao;
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);
      await dao.createSession(
        id: 'failed-final-session',
        deviceId: 'dev',
        startedAt: DateTime.utc(2026, 1, 1),
      );
      final job = await dao.createSyncJobIfAbsent('failed-final-session');
      await dao.updateSyncJob(job.id, coreStatus: syncJobFailedFinal);

      await repository.startTracking();

      expect(repository.currentSnapshot.isTracking, isTrue);
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
    test('startReplay fetches replay data and initiates a timer', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.startReplay(123);

      expect(repository.currentSnapshot.isTracking, isTrue);
      expect(api.startCallCount, 1);
      // It should not create a local sqlite session
      expect(await database.acquisitionDao.countSessions(), 0);
    });

    test('stopReplay builds payload and finalizes trip without SyncQueue',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      await repository.startReplay(123);
      final result = await repository.stopReplay();

      expect(result.tripId, 999);
      expect(repository.currentSnapshot.isTracking, isFalse);

      // Assicura che non sia stato creato alcun SyncJob
      final jobs = await database.acquisitionDao
          .claimableSyncJobs(DateTime.now().toUtc());
      expect(jobs, isEmpty);
    });

    test('stopReplay uses the selected past start for replay payload',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _FakeTripIngestionApi();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      addTearDown(repository.dispose);

      final selectedStart = DateTime.utc(2026, 6, 29, 12, 15);
      await repository.startReplay(123, scheduledStartAt: selectedStart);
      await repository.stopReplay();

      expect(api.lastInlineCoreBody?['started_at'], '2026-06-29T12:15:00Z');
    });
  });
}

Future<void> _enterMovement(
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

class _FakeTripIngestionApi implements TripIngestionApi {
  final int ingestionId;
  final bool shouldFailStart;
  final bool shouldFailHeartbeat;
  final ActiveIngestion? conflictActive;
  final ActiveIngestion? activeIngestion;
  final bool conflictOnce;
  final List<String> startedDeviceIds = [];
  final List<int> abandonedIngestionIds = [];
  final List<({int ingestionId, String clientSessionId, String deviceId})>
      heartbeatCalls = [];
  int startCallCount = 0;
  int activeLookupCount = 0;
  Map<String, dynamic>? lastInlineCoreBody;

  _FakeTripIngestionApi({
    this.ingestionId = 1,
    this.shouldFailStart = false,
    this.shouldFailHeartbeat = false,
    this.conflictActive,
    this.activeIngestion,
    this.conflictOnce = false,
  });

  @override
  Future<ActiveIngestion?> getActiveIngestion() async {
    activeLookupCount += 1;
    return activeIngestion;
  }

  @override
  Future<IngestionStartResult> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform = '',
    int? sourceTripId,
  }) async {
    startCallCount += 1;
    if (shouldFailStart) {
      throw const IngestionApiException('start failed', statusCode: 409);
    }
    final active = conflictActive;
    if (active != null && (!conflictOnce || startCallCount == 1)) {
      throw IngestionApiException(
        "viaggio in corso gia' presente",
        statusCode: 409,
        body: {'active_ingestion': _activeJson(active)},
      );
    }
    startedDeviceIds.add(deviceId);
    return IngestionStartResult(
      ingestionId: ingestionId,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
      recordingStartedAt: startedAt,
      alreadyExists: false,
    );
  }

  @override
  Future<void> abandonIngestion({
    required int ingestionId,
    required String deviceId,
  }) async {
    abandonedIngestionIds.add(ingestionId);
  }

  @override
  Future<void> heartbeatIngestion({
    required int ingestionId,
    required String clientSessionId,
    required String deviceId,
  }) async {
    heartbeatCalls.add((
      ingestionId: ingestionId,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
    ));
    if (shouldFailHeartbeat) {
      throw const IngestionApiException('heartbeat failed', statusCode: 500);
    }
  }

  @override
  Future<Map<String, dynamic>> getReplayData(int tripId) async {
    // Stesso contratto di `ReplayDataOut`: chiavi gps_points/state_transitions,
    // transizioni con soli timestamp/from_state/to_state.
    return {
      'source_trip_id': tripId,
      'gps_points': [
        {
          'timestamp': '2026-01-01T08:00:00Z',
          'latitude': 44.0,
          'longitude': 11.0,
          'speed_mps': 1.0,
          'accuracy_meters': 5.0,
        },
        {
          'timestamp': '2026-01-01T08:20:00Z',
          'latitude': 44.1,
          'longitude': 11.1,
          'speed_mps': 2.0,
          'accuracy_meters': null,
        },
      ],
      'state_transitions': [
        {
          'timestamp': '2026-01-01T08:05:00Z',
          'from_state': 'STATIONARY',
          'to_state': 'MOVEMENT',
        }
      ]
    };
  }

  @override
  Future<InlineCoreResult> postCoreInline(
      {required Map<String, dynamic> body}) async {
    lastInlineCoreBody = body;
    return InlineCoreResult(
      ingestionId: body['ingestion_id'] as int? ?? 1,
      tripId: 999,
      coreStatus: 'SAVED',
      rawStatus: 'PENDING',
      gpsPoints: (body['gps_points'] as List).length,
      stateTransitions: (body['state_transitions'] as List).length,
      pathPoints: 0,
      distanceMeters: 0,
      mapAvailable: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ManualTimer implements Timer {
  final void Function(Timer timer) _callback;
  bool _isActive = true;
  int _tick = 0;

  _ManualTimer(this._callback);

  void fire() {
    if (!_isActive) {
      return;
    }
    _tick += 1;
    _callback(this);
  }

  @override
  void cancel() {
    _isActive = false;
  }

  @override
  bool get isActive => _isActive;

  @override
  int get tick => _tick;
}

ActiveIngestion _active({
  int ingestionId = 7,
  String clientSessionId = 'remote-session',
  String deviceId = 'stable-device',
}) {
  return ActiveIngestion(
    ingestionId: ingestionId,
    clientSessionId: clientSessionId,
    deviceId: deviceId,
    recordingStartedAt: DateTime.utc(2026, 1, 1, 8),
    lastSeenAt: DateTime.utc(2026, 1, 1, 8, 5),
  );
}

Map<String, dynamic> _activeJson(ActiveIngestion active) {
  return {
    'ingestion_id': active.ingestionId,
    'client_session_id': active.clientSessionId,
    'device_id': active.deviceId,
    'recording_started_at': active.recordingStartedAt.toIso8601String(),
    'last_seen_at': active.lastSeenAt?.toIso8601String(),
  };
}

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionLocalDatabase', () {
    test('creates sessions and stores ordered transitions', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);

      await dao.createSession(
        id: 'session-1',
        deviceId: 'device-1',
        remoteIngestionId: 42,
        startedAt: startedAt,
      );
      await dao.insertTransition(
        sessionId: 'session-1',
        fromState: 'STATIONARY',
        toState: 'MOVEMENT',
        reason: 'movement_sigma_above_threshold',
        timestamp: startedAt.add(const Duration(seconds: 2)),
        sigma: 0.7,
        speedMps: 0,
      );
      await dao.endSession(
        id: 'session-1',
        endedAt: startedAt.add(const Duration(minutes: 1)),
      );

      final sessions = await dao.allSessions();
      final transitions = await dao.transitionsForSession('session-1');

      expect(sessions.single.id, 'session-1');
      expect(sessions.single.deviceId, 'device-1');
      expect(sessions.single.remoteIngestionId, 42);
      expect(sessions.single.endedAt, isNotNull);
      expect(transitions.single.reason, 'movement_sigma_above_threshold');
      expect(await dao.countTransitionsForSession('session-1'), 1);
    });

    test('stores inline core metadata on sync jobs', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);

      await dao.createSession(
        id: 'session-core',
        deviceId: 'device-1',
        remoteIngestionId: 42,
        startedAt: startedAt,
      );
      await dao.createSyncJobIfAbsent('session-core');

      final created = await dao.syncJobForSession('session-core');
      expect(created!.remoteIngestionId, 42);
      expect(created.corePayloadSha256, isNull);
      expect(created.corePayloadSizeBytes, 0);
      expect(created.coreMapAvailable, isFalse);

      await dao.updateSyncJob(
        created.id,
        corePayloadSha256: const Value('abc123'),
        corePayloadSizeBytes: 128,
        coreMapAvailable: true,
      );

      final updated = await dao.syncJobForSession('session-core');
      expect(updated!.corePayloadSha256, 'abc123');
      expect(updated.corePayloadSizeBytes, 128);
      expect(updated.coreMapAvailable, isTrue);
    });

    test('purgeSyncedSession removes raw data, the sync job and the session',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);

      await dao.createSession(
        id: 'synced-session',
        deviceId: 'device-1',
        startedAt: startedAt,
      );
      await dao.insertTransition(
        sessionId: 'synced-session',
        fromState: 'STATIONARY',
        toState: 'MOVEMENT',
        reason: 'movement_sigma_above_threshold',
        timestamp: startedAt,
        sigma: 1.2,
        speedMps: 1,
      );
      await dao.insertGpsPoint(
        sessionId: 'synced-session',
        latitude: 44.0,
        longitude: 11.0,
        timestamp: startedAt,
        speedMps: 1,
      );
      final job = await dao.createSyncJobIfAbsent('synced-session');
      await dao.updateSyncJob(
        job.id,
        coreStatus: syncJobCompleted,
        rawStatus: syncJobCompleted,
        remoteTripId: const Value(55),
      );

      await dao.purgeSyncedSession('synced-session');

      expect(await dao.findSession('synced-session'), isNull);
      expect(await dao.syncJobForSession('synced-session'), isNull);
      expect(await dao.transitionsForSession('synced-session'), isEmpty);
      expect(await dao.countGpsPointsForSession('synced-session'), 0);
    });

    test('localSessionIdForRemoteTrip finds the session behind a Trip id',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dao = database.acquisitionDao;

      await dao.createSession(
        id: 'trip-source-session',
        deviceId: 'device-1',
        startedAt: DateTime.utc(2026, 1, 1, 8),
      );
      final job = await dao.createSyncJobIfAbsent('trip-source-session');
      await dao.updateSyncJob(job.id, remoteTripId: const Value(77));

      expect(await dao.localSessionIdForRemoteTrip(77), 'trip-source-session');
      expect(await dao.localSessionIdForRemoteTrip(999), isNull);
    });
  });
}

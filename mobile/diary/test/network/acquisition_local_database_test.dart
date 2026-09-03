import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AcquisitionLocalDatabase database;
  late AcquisitionDao dao;

  setUp(() {
    database = AcquisitionLocalDatabase(NativeDatabase.memory());
    dao = AcquisitionDao(database);
  });

  tearDown(() => database.close());

  test('persists a resumable acquisition session with UTC timestamps',
      () async {
    final startedAt = DateTime.parse('2026-08-30T12:00:00+02:00');
    await dao.createSession(
      id: 'session-1',
      deviceId: 'iphone-1',
      startedAt: startedAt,
      remoteUploadId: 42,
    );

    final stored = await dao.latestOpenSession();

    expect(stored?.id, 'session-1');
    expect(stored?.startedAt, DateTime.utc(2026, 8, 30, 10));
    expect(stored?.startedAt.isUtc, isTrue);
    expect(stored?.remoteUploadId, 42);
  });

  test('returns only accepted GPS evidence in chronological order', () async {
    await dao.createSession(
      id: 'session-1',
      deviceId: 'iphone-1',
      startedAt: DateTime.utc(2026, 8, 30, 10),
    );
    await dao.insertGpsPoint(
      sessionId: 'session-1',
      latitude: 45.47,
      longitude: 9.20,
      timestamp: DateTime.utc(2026, 8, 30, 10, 2),
      speedMps: 1,
    );
    await dao.insertGpsPoint(
      sessionId: 'session-1',
      latitude: 0,
      longitude: 0,
      timestamp: DateTime.utc(2026, 8, 30, 10, 1),
      speedMps: 0,
      accepted: false,
      rejectionReason: 'accuracy',
    );
    await dao.insertGpsPoint(
      sessionId: 'session-1',
      latitude: 45.46,
      longitude: 9.19,
      timestamp: DateTime.utc(2026, 8, 30, 10),
      speedMps: 1,
    );

    final accepted = await dao.gpsPointsForSession('session-1');

    expect(await dao.countGpsPointsForSession('session-1'), 3);
    expect(accepted.map((point) => point.latitude), [45.46, 45.47]);
  });

  test('creates one durable sync job per stopped session', () async {
    await dao.createSession(
      id: 'session-1',
      deviceId: 'iphone-1',
      startedAt: DateTime.utc(2026, 8, 30, 10),
      remoteUploadId: 77,
    );

    final first = await dao.createSyncJobIfAbsent('session-1');
    final retry = await dao.createSyncJobIfAbsent('session-1');

    expect(retry.id, first.id);
    expect(retry.remoteUploadId, 77);
    expect((await dao.claimableSyncJobs(DateTime.now().toUtc())).length, 1);
  });

  test('reads sensor windows in stable bounded pages', () async {
    final startedAt = DateTime.utc(2026, 8, 30, 10);
    await dao.createSession(
      id: 'session-1',
      deviceId: 'iphone-1',
      startedAt: startedAt,
    );
    for (final minute in [4, 1, 3, 0, 2]) {
      final windowStart = startedAt.add(Duration(minutes: minute));
      await dao.insertSensorWindow(
        sessionId: 'session-1',
        startTimestamp: windowStart,
        endTimestamp: windowStart.add(const Duration(seconds: 5)),
        sampleCount: 1,
        frequencyHz: 100,
        matrixJson: '[[1,2,3,4,5,6]]',
      );
    }

    final first = await dao.sensorWindowsPageForSession(
      'session-1',
      limit: 2,
      offset: 0,
    );
    final second = await dao.sensorWindowsPageForSession(
      'session-1',
      limit: 2,
      offset: 2,
    );
    final third = await dao.sensorWindowsPageForSession(
      'session-1',
      limit: 2,
      offset: 4,
    );

    expect(
      [...first, ...second, ...third].map((window) => window.startTimestamp),
      [
        for (var minute = 0; minute < 5; minute += 1)
          startedAt.add(Duration(minutes: minute)),
      ],
    );
    expect(first, hasLength(2));
    expect(second, hasLength(2));
    expect(third, hasLength(1));
  });

  test('purges all local evidence only after synchronization completes',
      () async {
    await dao.createSession(
      id: 'session-1',
      deviceId: 'iphone-1',
      startedAt: DateTime.utc(2026, 8, 30, 10),
    );
    await dao.insertGpsPoint(
      sessionId: 'session-1',
      latitude: 45.46,
      longitude: 9.19,
      timestamp: DateTime.utc(2026, 8, 30, 10),
      speedMps: 1,
    );
    await dao.insertSensorWindow(
      sessionId: 'session-1',
      startTimestamp: DateTime.utc(2026, 8, 30, 10),
      endTimestamp: DateTime.utc(2026, 8, 30, 10, 0, 5),
      sampleCount: 1,
      frequencyHz: 100,
      matrixJson: '[[1,2,3,4,5,6]]',
    );
    await dao.createSyncJobIfAbsent('session-1');

    await dao.purgeSyncedSession('session-1');

    expect(await dao.findSession('session-1'), isNull);
    expect(await dao.syncJobForSession('session-1'), isNull);
    expect(await dao.countGpsPointsForSession('session-1'), 0);
    expect(await dao.countSensorWindowsForSession('session-1'), 0);
  });
}

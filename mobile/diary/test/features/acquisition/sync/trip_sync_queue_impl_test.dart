import 'dart:io';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeIngestionApi implements TripIngestionApi {
  bool failCreate = false;
  bool coreCompleteCalled = false;
  bool rawCompleteCalled = false;
  String coreStatusBeforeComplete = 'PENDING';
  String coreStatusAfterComplete = 'COMPLETED';
  String rawStatusBeforeComplete = 'PENDING';
  String rawStatusAfterComplete = 'RECEIVED';
  final List<String> confirmed = [];
  final List<String> uploaded = [];
  int _nextId = 100;

  @override
  Future<int> createIngestion({
    required String clientSessionId,
    required Map<String, int> expectedCoreParts,
    required Map<String, int> expectedRawParts,
    DateTime? startedAt,
    DateTime? endedAt,
    String deviceId = '',
    String devicePlatform = '',
  }) async {
    if (failCreate) {
      throw const IngestionApiException('boom', statusCode: 500);
    }
    return _nextId++;
  }

  @override
  Future<PresignResult> presignPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
    required int sizeBytes,
  }) async {
    return PresignResult(
      objectKey: '$kind-$sequence',
      uploadUrl: 'http://storage.local/$kind-$sequence',
    );
  }

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {
    uploaded.add(uploadUrl);
  }

  @override
  Future<void> confirmPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
  }) async {
    confirmed.add('$kind#$sequence');
  }

  @override
  Future<void> completeCoreIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    coreCompleteCalled = true;
  }

  @override
  Future<void> completeRawIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    rawCompleteCalled = true;
  }

  @override
  Future<IngestionStatus> getStatus(int ingestionId) async {
    if (!coreCompleteCalled) {
      return IngestionStatus(
        coreStatus: coreStatusBeforeComplete,
        rawStatus: rawStatusBeforeComplete,
        missingCoreParts: const [],
        missingRawParts: const [],
      );
    }
    final rawStatus =
        rawCompleteCalled ? rawStatusAfterComplete : rawStatusBeforeComplete;
    return IngestionStatus(
      coreStatus: coreStatusAfterComplete,
      rawStatus: rawStatus,
      missingCoreParts: const [],
      missingRawParts: const [],
      tripId: coreStatusAfterComplete == 'COMPLETED' ? 1 : null,
    );
  }
}

void main() {
  late AcquisitionLocalDatabase database;
  late Directory tempDir;

  setUp(() async {
    database = AcquisitionLocalDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('queue_test');
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  Future<String> seedSessionWithData() async {
    final dao = database.acquisitionDao;
    const id = 'sess-q';
    await dao.createSession(
      id: id,
      deviceId: 'dev',
      startedAt: DateTime.utc(2026, 6, 12, 10),
    );
    await dao.endSession(id: id, endedAt: DateTime.utc(2026, 6, 12, 10, 30));
    await dao.insertGpsPoint(
      sessionId: id,
      latitude: 45.4,
      longitude: 9.1,
      timestamp: DateTime.utc(2026, 6, 12, 10, 0, 3),
      speedMps: 3.2,
      accuracyMeters: 12,
    );
    await dao.insertTransition(
      sessionId: id,
      fromState: 'STATIONARY',
      toState: 'POTENTIAL_MOTION',
      reason: 'x',
      timestamp: DateTime.utc(2026, 6, 12, 10, 1),
      sigma: 1.2,
      speedMps: 0.8,
    );
    await dao.insertSensorWindow(
      sessionId: id,
      startTimestamp: DateTime.utc(2026, 6, 12, 10, 2),
      endTimestamp: DateTime.utc(2026, 6, 12, 10, 2, 5),
      sampleCount: 1,
      frequencyHz: 100,
      matrixJson: '[[1,2,3,4,5,6,7,8,9]]',
    );
    await dao.createSyncJobIfAbsent(id);
    return id;
  }

  TripSyncQueueImpl queue(FakeIngestionApi api, {String? token = 'tkn'}) {
    return TripSyncQueueImpl(
      dao: database.acquisitionDao,
      builder: TripPackageBuilder(
        dao: database.acquisitionDao,
        baseDirProvider: () async => tempDir,
      ),
      api: api,
      tokenProvider: () async => token,
    );
  }

  test('happy path: uploads all parts, completes, marks job COMPLETED',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi();

    await queue(api).kick();

    expect(api.confirmed.toSet(), {
      'gps_points#1',
      'state_transitions#1',
      'sensor_windows#1',
    });
    expect(api.uploaded, hasLength(3));
    expect(api.coreCompleteCalled, isTrue);
    expect(api.rawCompleteCalled, isTrue);

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobCompleted);
    expect(job.remoteIngestionId, isNotNull);
    // I blob temporanei sono stati ripuliti.
    expect(
      await Directory('${tempDir.path}/trip_package_$id').exists(),
      isFalse,
    );
  });

  test(
      'failure schedules a retry with backoff and is not immediately claimable',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..failCreate = true;

    await queue(api).kick();

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobFailedRetryable);
    expect(job.attempts, 1);
    expect(job.nextRetryAt, isNotNull);
    expect(job.lastError, contains('boom'));

    // next_retry_at e' nel futuro: non ripreso subito.
    final claimable =
        await database.acquisitionDao.claimableSyncJobs(DateTime.now().toUtc());
    expect(claimable, isEmpty);
  });

  test('polls without reuploading when backend is already processing',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..coreStatusBeforeComplete = 'PROCESSING';

    await queue(api).kick();

    expect(api.uploaded, isEmpty);
    expect(api.confirmed, isEmpty);
    expect(api.coreCompleteCalled, isFalse);
    expect(api.rawCompleteCalled, isFalse);

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobWaitingProcessing);
    expect(job.nextRetryAt, isNotNull);
  });

  test('marks job failed final without completing when backend failed final',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..coreStatusBeforeComplete = 'FAILED_FINAL';

    await queue(api).kick();

    expect(api.uploaded, isEmpty);
    expect(api.confirmed, isEmpty);
    expect(api.coreCompleteCalled, isFalse);
    expect(api.rawCompleteCalled, isFalse);

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobFailedFinal);
    expect(job.lastError, contains('backend fallita'));
  });

  test('does not retry raw when core is already failed final', () async {
    final id = await seedSessionWithData();
    final job = await database.acquisitionDao.syncJobForSession(id);
    await database.acquisitionDao.updateSyncJob(
      job!.id,
      coreStatus: syncJobFailedFinal,
    );
    final api = FakeIngestionApi();

    await queue(api).kick();

    expect(api.uploaded, isEmpty);
    expect(api.confirmed, isEmpty);
    expect(api.coreCompleteCalled, isFalse);
    expect(api.rawCompleteCalled, isFalse);
    final unchanged = await database.acquisitionDao.syncJobForSession(id);
    expect(unchanged!.coreStatus, syncJobFailedFinal);
    expect(unchanged.rawStatus, syncJobPending);
  });

  test('no-op when not authenticated (no token)', () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi();

    await queue(api, token: null).kick();

    expect(api.confirmed, isEmpty);
    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobPending);
    expect(job.attempts, 0);
  });

  test('empty session completes without calling the API', () async {
    final dao = database.acquisitionDao;
    await dao.createSession(
      id: 'empty',
      deviceId: 'dev',
      startedAt: DateTime.utc(2026, 6, 12),
    );
    await dao.createSyncJobIfAbsent('empty');
    final api = FakeIngestionApi();

    await queue(api).kick();

    expect(api.coreCompleteCalled, isFalse);
    expect(api.rawCompleteCalled, isFalse);
    expect(api.confirmed, isEmpty);
    final job = await dao.syncJobForSession('empty');
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobCompleted);
  });
}

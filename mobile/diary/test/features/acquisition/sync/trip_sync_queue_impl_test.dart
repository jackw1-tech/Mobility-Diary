import 'dart:io';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeIngestionApi implements TripIngestionApi {
  bool failCoreInline = false;
  int createIngestionCallCount = 0;
  int coreInlineCallCount = 0;
  int rawUploadFailuresRemaining = 0;
  bool coreCompleteCalled = false;
  bool rawCompleteCalled = false;
  String inlineCoreStatus = 'COMPLETED';
  bool inlineMapAvailable = true;
  String rawStatusBeforeComplete = 'PENDING';
  String rawStatusAfterComplete = 'COMPLETED';
  final List<String> presigned = [];
  final List<String> confirmed = [];
  final List<Map<String, dynamic>> inlineBodies = [];
  final List<String> uploaded = [];
  int _nextId = 100;

  bool get coreInlineCalled => coreInlineCallCount > 0;

  @override
  Future<ActiveIngestion?> getActiveIngestion() async => null;

  @override
  Future<IngestionStartResult> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform = '',
    int? sourceTripId,
  }) async {
    return IngestionStartResult(
      ingestionId: _nextId++,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
      recordingStartedAt: startedAt,
      alreadyExists: false,
    );
  }

  @override
  Future<Map<String, dynamic>> getReplayData(int tripId) async {
    return {};
  }

  @override
  Future<void> abandonIngestion({
    required int ingestionId,
    required String deviceId,
  }) async {}

  @override
  Future<void> heartbeatIngestion({
    required int ingestionId,
    required String clientSessionId,
    required String deviceId,
  }) async {}

  @override
  Future<InlineCoreResult> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    coreInlineCallCount += 1;
    inlineBodies.add(body);
    if (failCoreInline) {
      throw const IngestionApiException('boom', statusCode: 500);
    }
    final expectedRawParts =
        Map<String, dynamic>.from(body['expected_raw_parts'] as Map);
    final rawStatus =
        expectedRawParts.isEmpty ? 'COMPLETED' : rawStatusBeforeComplete;
    final responseIngestionId = body['ingestion_id'] as int? ?? _nextId++;
    return InlineCoreResult(
      ingestionId: responseIngestionId,
      tripId: inlineCoreStatus == 'COMPLETED' ? 1 : null,
      coreStatus: inlineCoreStatus,
      rawStatus: rawStatus,
      gpsPoints: (body['gps_points'] as List<dynamic>? ?? const []).length,
      stateTransitions:
          (body['state_transitions'] as List<dynamic>? ?? const []).length,
      pathPoints: (body['gps_points'] as List<dynamic>? ?? const []).length,
      distanceMeters: inlineMapAvailable ? 1000 : 0,
      mapAvailable: inlineMapAvailable,
    );
  }

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
    createIngestionCallCount += 1;
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
    presigned.add('$kind#$sequence');
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
    if (rawUploadFailuresRemaining > 0) {
      rawUploadFailuresRemaining -= 1;
      throw const IngestionApiException('raw boom', statusCode: 500);
    }
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
    final rawStatus =
        rawCompleteCalled ? rawStatusAfterComplete : rawStatusBeforeComplete;
    return IngestionStatus(
      coreStatus: inlineCoreStatus,
      rawStatus: rawStatus,
      missingCoreParts: const [],
      missingRawParts: rawCompleteCalled
          ? const []
          : const [(kind: 'sensor_windows', sequence: 1)],
      tripId: inlineCoreStatus == 'COMPLETED' ? 1 : null,
      mapAvailable: inlineMapAvailable,
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

  Future<String> seedSessionWithData({
    bool includeSensorWindow = true,
    int? remoteIngestionId,
  }) async {
    final dao = database.acquisitionDao;
    const id = 'sess-q';
    await dao.createSession(
      id: id,
      deviceId: 'dev',
      remoteIngestionId: remoteIngestionId,
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
      toState: 'MOVEMENT',
      reason: 'x',
      timestamp: DateTime.utc(2026, 6, 12, 10, 1),
      sigma: 1.2,
      speedMps: 0.8,
    );
    if (includeSensorWindow) {
      await dao.insertSensorWindow(
        sessionId: id,
        startTimestamp: DateTime.utc(2026, 6, 12, 10, 2),
        endTimestamp: DateTime.utc(2026, 6, 12, 10, 2, 5),
        sampleCount: 1,
        frequencyHz: 100,
        matrixJson: '[[1,2,3,4,5,6,7,8,9]]',
      );
    }
    await dao.createSyncJobIfAbsent(id);
    return id;
  }

  TripSyncQueueImpl queue(
    FakeIngestionApi api, {
    String? token = 'tkn',
    List<Duration>? backoff,
    Duration pollDelay = const Duration(seconds: 15),
  }) {
    return TripSyncQueueImpl(
      dao: database.acquisitionDao,
      builder: TripPackageBuilder(
        dao: database.acquisitionDao,
        baseDirProvider: () async => tempDir,
      ),
      api: api,
      tokenProvider: () async => token,
      backoff: backoff,
      pollDelay: pollDelay,
    );
  }

  test('happy path: posts inline core, uploads raw, marks job COMPLETED',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi();

    await queue(api).kick();

    expect(api.coreInlineCalled, isTrue);
    expect(api.inlineBodies, hasLength(1));
    expect(api.inlineBodies.single['client_session_id'], id);
    expect(api.inlineBodies.single['core_payload_sha256'], isNotEmpty);
    expect(api.inlineBodies.single['gps_points'], hasLength(1));
    expect(api.inlineBodies.single['state_transitions'], hasLength(1));
    expect(api.createIngestionCallCount, 0);
    expect(api.presigned, ['sensor_windows#1']);
    expect(api.confirmed, ['sensor_windows#1']);
    expect(api.uploaded, hasLength(1));
    expect(api.coreCompleteCalled, isFalse);
    expect(api.rawCompleteCalled, isTrue);

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobCompleted);
    expect(job.remoteIngestionId, isNotNull);
    expect(job.remoteTripId, 1);
    expect(
        job.corePayloadSha256, api.inlineBodies.single['core_payload_sha256']);
    expect(job.corePayloadSizeBytes, greaterThan(0));
    expect(job.coreMapAvailable, isTrue);
    // I blob temporanei sono stati ripuliti.
    expect(
      await Directory('${tempDir.path}/trip_package_$id').exists(),
      isFalse,
    );
    // La mole di dati grezzi locali e' stata ripulita dopo il sync completo...
    expect(await database.acquisitionDao.countGpsPointsForSession(id), 0);
    expect(await database.acquisitionDao.countSensorWindowsForSession(id), 0);
    expect(await database.acquisitionDao.countTransitionsForSession(id), 0);
    // ...ma la sessione e il sync job restano per lo stato mostrato in UI.
    expect(await database.acquisitionDao.findSession(id), isNotNull);
  });

  test('posts final core against the ingestion created at start', () async {
    final id = await seedSessionWithData(remoteIngestionId: 321);
    final api = FakeIngestionApi();

    await queue(api).kick();

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.inlineBodies.single['ingestion_id'], 321);
    expect(job!.remoteIngestionId, 321);
  });

  test(
      'failure schedules a retry with backoff and is not immediately claimable',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..failCoreInline = true;

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

  test('retries final core failure against the same remote ingestion id',
      () async {
    final id = await seedSessionWithData(remoteIngestionId: 321);
    final api = FakeIngestionApi()..failCoreInline = true;

    await queue(api, backoff: const [Duration.zero]).kick();

    var job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobFailedRetryable);
    expect(job.remoteIngestionId, 321);

    api.failCoreInline = false;
    await queue(api, backoff: const [Duration.zero]).kick();

    job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.remoteIngestionId, 321);
    expect(api.inlineBodies, hasLength(2));
    expect(api.inlineBodies.map((body) => body['ingestion_id']), [321, 321]);
  });

  test('polls without raw upload when backend is already processing', () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..inlineCoreStatus = 'PROCESSING';

    await queue(api).kick();

    expect(api.coreInlineCalled, isTrue);
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
    final api = FakeIngestionApi()..inlineCoreStatus = 'FAILED_FINAL';

    await queue(api).kick();

    expect(api.coreInlineCalled, isTrue);
    expect(api.uploaded, isEmpty);
    expect(api.confirmed, isEmpty);
    expect(api.coreCompleteCalled, isFalse);
    expect(api.rawCompleteCalled, isFalse);

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobFailedFinal);
    expect(job.lastError, contains('backend fallita'));
  });

  test('core completed without map keeps the map gate unavailable', () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..inlineMapAvailable = false;

    await queue(api).kick();

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.remoteTripId, 1);
    expect(job.coreMapAvailable, isFalse);
  });

  test('core with no raw completes both phases without raw upload', () async {
    final id = await seedSessionWithData(includeSensorWindow: false);
    final api = FakeIngestionApi();

    await queue(api).kick();

    expect(api.coreInlineCallCount, 1);
    expect(api.inlineBodies.single['expected_raw_parts'], isEmpty);
    expect(api.uploaded, isEmpty);
    expect(api.confirmed, isEmpty);
    expect(api.rawCompleteCalled, isFalse);

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobCompleted);
    expect(job.remoteTripId, 1);
    expect(job.coreMapAvailable, isTrue);
  });

  test('raw queued after upload waits for backend HAR completion', () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..rawStatusAfterComplete = 'QUEUED';

    await queue(
      api,
      backoff: const [Duration.zero],
      pollDelay: Duration.zero,
    ).kick();

    var job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.rawCompleteCalled, isTrue);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobWaitingProcessing);
    expect(job.nextRetryAt, isNotNull);
    expect(await database.acquisitionDao.countSensorWindowsForSession(id), 1);
    expect(
      await Directory('${tempDir.path}/trip_package_$id').exists(),
      isFalse,
    );

    api.rawStatusAfterComplete = 'COMPLETED';
    await queue(
      api,
      backoff: const [Duration.zero],
      pollDelay: Duration.zero,
    ).kick();

    job = await database.acquisitionDao.syncJobForSession(id);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobCompleted);
    expect(await database.acquisitionDao.countSensorWindowsForSession(id), 0);
  });

  test('raw processing after upload waits for backend HAR completion',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..rawStatusAfterComplete = 'PROCESSING';

    await queue(
      api,
      backoff: const [Duration.zero],
      pollDelay: Duration.zero,
    ).kick();

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.rawCompleteCalled, isTrue);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobWaitingProcessing);
    expect(job.nextRetryAt, isNotNull);
    expect(await database.acquisitionDao.countSensorWindowsForSession(id), 1);
  });

  test('raw received completes without re-uploading already accepted parts',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()
      ..rawStatusBeforeComplete = 'RECEIVED'
      ..rawStatusAfterComplete = 'QUEUED';

    await queue(
      api,
      backoff: const [Duration.zero],
      pollDelay: Duration.zero,
    ).kick();

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.presigned, isEmpty);
    expect(api.uploaded, isEmpty);
    expect(api.confirmed, isEmpty);
    expect(api.rawCompleteCalled, isTrue);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobWaitingProcessing);
    expect(await database.acquisitionDao.countSensorWindowsForSession(id), 1);
  });

  test('raw failed retryable keeps polling without re-uploading phone data',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..rawStatusAfterComplete = 'FAILED_RETRYABLE';

    await queue(
      api,
      backoff: const [Duration.zero],
      pollDelay: Duration.zero,
    ).kick();

    var job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.rawCompleteCalled, isTrue);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobWaitingProcessing);
    expect(await database.acquisitionDao.countSensorWindowsForSession(id), 1);

    api.rawStatusAfterComplete = 'COMPLETED';
    await queue(
      api,
      backoff: const [Duration.zero],
      pollDelay: Duration.zero,
    ).kick();

    job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.coreInlineCallCount, 1);
    expect(job!.rawStatus, syncJobCompleted);
    expect(await database.acquisitionDao.countSensorWindowsForSession(id), 0);
  });

  test('raw failed final preserves synced trip but closes raw phase as failed',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..rawStatusAfterComplete = 'FAILED_FINAL';

    await queue(api).kick();

    final job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.rawCompleteCalled, isTrue);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobFailedFinal);
    expect(job.remoteTripId, 1);
    expect(job.coreMapAvailable, isTrue);
  });

  test('raw retry keeps core completed and does not repost inline core',
      () async {
    final id = await seedSessionWithData();
    final api = FakeIngestionApi()..rawUploadFailuresRemaining = 1;

    await queue(api, backoff: const [Duration.zero]).kick();

    var job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.coreInlineCallCount, 1);
    expect(api.rawCompleteCalled, isFalse);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobFailedRetryable);
    expect(job.remoteTripId, 1);
    expect(job.coreMapAvailable, isTrue);

    await queue(api, backoff: const [Duration.zero]).kick();

    job = await database.acquisitionDao.syncJobForSession(id);
    expect(api.coreInlineCallCount, 1);
    expect(api.rawCompleteCalled, isTrue);
    expect(api.confirmed, ['sensor_windows#1']);
    expect(job!.coreStatus, syncJobCompleted);
    expect(job.rawStatus, syncJobCompleted);
    expect(job.remoteTripId, 1);
    expect(job.coreMapAvailable, isTrue);
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

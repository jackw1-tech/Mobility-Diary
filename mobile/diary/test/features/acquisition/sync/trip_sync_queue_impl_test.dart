import 'dart:async';
import 'dart:io';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/sensor_matrix_blob.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue_impl.dart';
import 'package:diary/mappers/ingestion_mapper.dart';
import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/ingestion/inline_core_result_dto.dart';
import 'package:diary/network/dto/ingestion/presign_result_dto.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('TripSyncQueueImpl', () {
    late AcquisitionLocalDatabase database;
    late Directory tempDir;
    late _FakeTripIngestionService service;

    setUp(() async {
      database = AcquisitionLocalDatabase(NativeDatabase.memory());
      tempDir = await Directory.systemTemp.createTemp('trip_sync_queue_test_');
      service = _FakeTripIngestionService();
    });

    tearDown(() async {
      await database.close();
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });

    TripSyncQueueImpl queue({Future<String?> Function()? tokenProvider}) {
      return TripSyncQueueImpl(
        dao: database.acquisitionDao,
        builder: TripPackageBuilder(
          dao: database.acquisitionDao,
          baseDirProvider: () async => tempDir,
        ),
        service: service,
        mapper: IngestionMapper(),
        tokenProvider: tokenProvider ?? () async => 'token',
        backoff: const [Duration(milliseconds: 1)],
        pollDelay: const Duration(milliseconds: 1),
        processingPollDelay: const Duration(milliseconds: 1),
      );
    }

    test('does nothing when auth token is missing', () async {
      await _seedSyncJob(database, sessionId: 'session-token-missing');
      final syncQueue = queue(tokenProvider: () async => null);

      await syncQueue.processDue();

      expect(service.postCoreInlineCalls, 0);
      expect(await database.acquisitionDao.countSessions(), 1);
    });

    test('posts inline core and purges local data when sync completes',
        () async {
      await _seedSyncJob(database, sessionId: 'session-success');
      service.inlineTripId = 77;
      final syncQueue = queue();

      await syncQueue.processDue();

      expect(service.postCoreInlineCalls, 1);
      expect(service.postedCoreBodies.single['client_session_id'],
          'session-success');
      expect(await database.acquisitionDao.countSessions(), 0);
    });

    test(
        'discards immediately on 410 (permanently abandoned/closed) without retrying',
        () async {
      await _seedSyncJob(database, sessionId: 'session-abandoned');
      service.postCoreInlineError = const IngestionApiException(
        'viaggio abbandonato',
        statusCode: 410,
      );
      final syncQueue = queue();

      await syncQueue.processDue();

      expect(service.postCoreInlineCalls, 1);
      expect(await database.acquisitionDao.countSessions(), 0);
      expect(
        await database.acquisitionDao.syncJobForSession('session-abandoned'),
        isNull,
      );
    });

    test('uploads real raw sensor window parts before waiting for processing',
        () async {
      await _seedSyncJob(database, sessionId: 'session-raw');
      await _seedSensorWindows(database, sessionId: 'session-raw');
      service.inlineRawStatus = 'PENDING';
      service.statusAfterRawComplete = 'QUEUED';
      final syncQueue = queue();

      await syncQueue.processDue();

      expect(service.postCoreInlineCalls, 1);
      expect(service.postedCoreBodies.single['expected_raw_parts'],
          {'sensor_windows': 1});
      expect(service.presignedParts, ['sensor_windows#1']);
      expect(service.uploadedParts, hasLength(1));
      expect(service.confirmedParts, ['sensor_windows#1']);
      expect(service.completeRawCalls, 1);

      final job =
          await database.acquisitionDao.syncJobForSession('session-raw');
      expect(job, isNotNull);
      expect(job!.coreStatus, syncJobCompleted);
      expect(job.rawStatus, syncJobWaitingProcessing);
      expect(await database.acquisitionDao.countSessions(), 1);
    });

    test('keeps only one processing pass active at a time', () async {
      await _seedSyncJob(database, sessionId: 'session-concurrent');
      service.blockInlineCore = true;
      final syncQueue = queue();

      final first = syncQueue.processDue();
      await _waitUntil(() => service.postCoreInlineCalls == 1);
      final second = syncQueue.processDue();

      expect(service.postCoreInlineCalls, 1);
      service.releaseInlineCore();
      await Future.wait([first, second]);
      expect(service.postCoreInlineCalls, 1);
    });
  });
}

Future<void> _seedSyncJob(
  AcquisitionLocalDatabase database, {
  required String sessionId,
}) async {
  final dao = database.acquisitionDao;
  final startedAt = DateTime.utc(2026, 1, 1, 8);
  await dao.createSession(
    id: sessionId,
    deviceId: 'device-1',
    startedAt: startedAt,
    remoteIngestionId: 10,
  );
  await dao.endSession(
    id: sessionId,
    endedAt: startedAt.add(const Duration(minutes: 10)),
  );
  await dao.insertGpsPoint(
    sessionId: sessionId,
    latitude: 45.46,
    longitude: 9.19,
    timestamp: startedAt,
    speedMps: 1.2,
    accuracyMeters: 5,
  );
  await dao.insertTransition(
    sessionId: sessionId,
    fromState: 'STATIONARY',
    toState: 'MOVEMENT',
    reason: 'test',
    timestamp: startedAt,
    sigma: 0.8,
    speedMps: 1.2,
  );
  await dao.createSyncJobIfAbsent(sessionId);
}

Future<void> _seedSensorWindows(
  AcquisitionLocalDatabase database, {
  required String sessionId,
}) async {
  final matrix = [
    for (var i = 0; i < 500; i += 1) [0.1, 0.2, 9.7, 0.01, 0.02, 0.03],
  ];
  await database.acquisitionDao.insertSensorWindow(
    sessionId: sessionId,
    startTimestamp: DateTime.utc(2026, 1, 1, 8, 1),
    endTimestamp: DateTime.utc(2026, 1, 1, 8, 1, 5),
    sampleCount: matrix.length,
    frequencyHz: 100,
    matrixBlob: encodeSensorMatrixBlob(matrix),
  );
}

Future<void> _waitUntil(bool Function() predicate) async {
  for (var i = 0; i < 20; i += 1) {
    if (predicate()) return;
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  fail('condition was not met before timeout');
}

class _FakeTripIngestionService implements TripIngestionService {
  int postCoreInlineCalls = 0;
  int completeRawCalls = 0;
  int inlineTripId = 42;
  String inlineRawStatus = 'COMPLETED';
  String statusAfterRawComplete = 'COMPLETED';
  bool blockInlineCore = false;
  IngestionApiException? postCoreInlineError;
  final List<Map<String, dynamic>> postedCoreBodies = [];
  final List<String> presignedParts = [];
  final List<List<int>> uploadedParts = [];
  final List<String> confirmedParts = [];
  Completer<void>? _inlineBlocker;

  void releaseInlineCore() {
    _inlineBlocker?.complete();
  }

  @override
  Future<InlineCoreResultDto> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    postCoreInlineCalls += 1;
    postedCoreBodies.add(body);
    final error = postCoreInlineError;
    if (error != null) {
      throw error;
    }
    if (blockInlineCore) {
      _inlineBlocker ??= Completer<void>();
      await _inlineBlocker!.future;
    }
    return InlineCoreResultDto(
      ingestionId: body['ingestion_id'] as int? ?? 10,
      tripId: inlineTripId,
      coreStatus: 'COMPLETED',
      rawStatus: inlineRawStatus,
      gpsPoints: (body['gps_points'] as List).length,
      stateTransitions: (body['state_transitions'] as List).length,
      pathPoints: (body['gps_points'] as List).length,
      distanceMeters: 0,
      mapAvailable: true,
    );
  }

  @override
  Future<void> abandonIngestion({
    required int ingestionId,
    required String deviceId,
  }) async {}

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
    return 10;
  }

  @override
  Future<void> completeCoreIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {}

  @override
  Future<void> completeRawIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    completeRawCalls += 1;
  }

  @override
  Future<ActiveIngestionDto?> getActiveIngestion() async {
    return null;
  }

  @override
  Future<IngestionStatusDto> getStatus(int ingestionId) async {
    return IngestionStatusDto(
      coreStatus: 'COMPLETED',
      rawStatus: statusAfterRawComplete,
      missingCoreParts: const [],
      missingRawParts: const [],
      tripId: inlineTripId,
      coreIngestionMode: 'INLINE',
      mapAvailable: true,
    );
  }

  @override
  Future<Map<String, dynamic>> getReplayData(int tripId) async {
    return const {};
  }

  @override
  Future<List<List<double>>> getReplaySensorWindow(
    int tripId,
    int offsetSeconds,
  ) async {
    return const [];
  }

  @override
  Future<void> heartbeatIngestion({
    required int ingestionId,
    required String clientSessionId,
    required String deviceId,
  }) async {}

  @override
  Future<PresignResultDto> presignPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
    required int sizeBytes,
  }) async {
    presignedParts.add('$kind#$sequence');
    return PresignResultDto(
      objectKey: '$kind-$sequence',
      uploadUrl: 'http://unused/$kind/$sequence',
      uploadHeaders: const {},
    );
  }

  @override
  Future<IngestionStartResultDto> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform = '',
    int? sourceTripId,
  }) async {
    return IngestionStartResultDto(
      ingestionId: 10,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
      recordingStartedAt: startedAt,
      alreadyExists: false,
    );
  }

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {
    uploadedParts.add(bytes);
  }

  @override
  Future<void> confirmPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
  }) async {
    confirmedParts.add('$kind#$sequence');
  }
}

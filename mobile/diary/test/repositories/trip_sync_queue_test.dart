import 'dart:io';

import 'package:diary/mappers/upload_mapper.dart';
import 'package:diary/network/dto/upload/active_upload_dto.dart';
import 'package:diary/network/dto/upload/upload_start_result_dto.dart';
import 'package:diary/network/dto/upload/upload_status_dto.dart';
import 'package:diary/network/dto/upload/inline_core_result_dto.dart';
import 'package:diary/network/dto/upload/presign_result_dto.dart';
import 'package:diary/network/dto/upload/replay_data_dto.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/repositories/impl/acquisition/trip_package_builder.dart';
import 'package:diary/repositories/impl/acquisition/trip_sync_queue_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

class BoundaryUploadService implements TripUploadService {
  Object? postCoreError;
  int postCoreCalls = 0;
  Map<String, dynamic>? lastCoreBody;

  @override
  Future<InlineCoreResultDto> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    postCoreCalls += 1;
    lastCoreBody = body;
    final error = postCoreError;
    if (error != null) throw error;
    return const InlineCoreResultDto(
      uploadId: 77,
      tripId: 12,
      coreStatus: 'COMPLETED',
      rawStatus: 'COMPLETED',
      mapAvailable: true,
    );
  }

  @override
  Future<ActiveUploadDto?> getActiveUpload() async => null;

  @override
  Future<UploadStatusDto> getStatus(int uploadId) =>
      throw UnimplementedError();

  @override
  Future<UploadStartResultDto> startUpload({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform = '',
    int? sourceTripId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> abandonUpload({
    required int uploadId,
    required String deviceId,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> heartbeatUpload({
    required int uploadId,
    required String clientSessionId,
    required String deviceId,
  }) =>
      throw UnimplementedError();

  @override
  Future<PresignResultDto> presignPart(
    int uploadId, {
    required int sequence,
    required String sha256,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) =>
      throw UnimplementedError();

  @override
  Future<void> confirmPart(
    int uploadId, {
    required int sequence,
    required String sha256,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> completeRawUpload(
    int uploadId, {
    required int totalParts,
  }) =>
      throw UnimplementedError();

  @override
  Future<ReplayDataDto> getReplayData(int tripId) => throw UnimplementedError();

  @override
  Future<List<List<double>>> getReplaySensorWindow(
    int tripId,
    int offsetSeconds,
  ) =>
      throw UnimplementedError();
}

void main() {
  late AcquisitionLocalDatabase database;
  late AcquisitionDao dao;
  late BoundaryUploadService service;
  late Directory tempDirectory;

  setUp(() async {
    database = AcquisitionLocalDatabase(NativeDatabase.memory());
    dao = AcquisitionDao(database);
    service = BoundaryUploadService();
    tempDirectory =
        await Directory.systemTemp.createTemp('mobility-sync-test-');
  });

  tearDown(() async {
    await database.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  Future<void> createStoppedSession() async {
    await dao.createSession(
      id: 'session-1',
      deviceId: 'iphone-1',
      startedAt: DateTime.utc(2026, 8, 30, 10),
      remoteUploadId: 77,
    );
    await dao.endSession(
      id: 'session-1',
      endedAt: DateTime.utc(2026, 8, 30, 10, 10),
    );
    await dao.insertGpsPoint(
      sessionId: 'session-1',
      latitude: 45.4642,
      longitude: 9.19,
      timestamp: DateTime.utc(2026, 8, 30, 10),
      speedMps: 1.2,
      accuracyMeters: 4,
    );
    await dao.createSyncJobIfAbsent('session-1');
  }

  TripSyncQueueImpl queue(Future<String?> Function() tokenProvider) {
    return TripSyncQueueImpl(
      dao: dao,
      builder: TripPackageBuilder(
        dao: dao,
        baseDirProvider: () async => tempDirectory,
      ),
      service: service,
      mapper: UploadMapper(),
      tokenProvider: tokenProvider,
      backoff: const [Duration.zero],
      pollDelay: Duration.zero,
      processingPollDelay: Duration.zero,
    );
  }

  test('sends a stopped trip and purges it after backend completion', () async {
    await createStoppedSession();

    await queue(() async => 'mobile-token').kick();

    expect(service.postCoreCalls, 1);
    expect(service.lastCoreBody?['client_session_id'], 'session-1');
    expect(service.lastCoreBody?['upload_id'], 77);
    expect(service.lastCoreBody?['gps_points'], hasLength(1));
    expect(await dao.findSession('session-1'), isNull);
    expect(await dao.syncJobForSession('session-1'), isNull);
  });

  test('does not upload cached GPS fixes older than the session', () async {
    await createStoppedSession();
    await dao.insertGpsPoint(
      sessionId: 'session-1',
      latitude: 45.4639,
      longitude: 9.1897,
      timestamp: DateTime.utc(2026, 8, 30, 9, 59, 59),
      speedMps: 0,
      accuracyMeters: 10,
    );

    await queue(() async => 'mobile-token').kick();

    final points = service.lastCoreBody?['gps_points'] as List<dynamic>;
    expect(points, hasLength(1));
    expect(points.single['timestamp'], '2026-08-30T10:00:00Z');
  });

  test('keeps the durable job untouched while the user is logged out',
      () async {
    await createStoppedSession();

    await queue(() async => null).kick();

    expect(service.postCoreCalls, 0);
    expect(await dao.findSession('session-1'), isNotNull);
    expect(await dao.syncJobForSession('session-1'), isNotNull);
  });

  test('keeps transient upload failures retryable', () async {
    await createStoppedSession();
    service.postCoreError = const UploadApiException(
      'rete non disponibile',
      statusCode: 503,
    );

    await queue(() async => 'mobile-token').kick();

    final job = await dao.syncJobForSession('session-1');
    expect(job?.coreStatus, syncJobFailedRetryable);
    expect(job?.attempts, 1);
    expect(job?.lastError, 'rete non disponibile');
    expect(await dao.findSession('session-1'), isNotNull);
  });
}

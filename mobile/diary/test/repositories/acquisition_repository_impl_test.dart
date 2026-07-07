import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue.dart';
import 'package:diary/network/dto/ingestion/active_ingestion_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_start_result_dto.dart';
import 'package:diary/network/dto/ingestion/ingestion_status_dto.dart';
import 'package:diary/network/dto/ingestion/inline_core_result_dto.dart';
import 'package:diary/network/dto/ingestion/presign_result_dto.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionRepositoryImpl', () {
    test('live stop creates a local sync job and kicks the sync queue',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _FakeTripIngestionService();
      final queue = _FakeTripSyncQueue();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        ingestionService: service,
        syncQueue: queue,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);

      await repository.startTracking();
      expect(repository.currentSnapshot.isTracking, isTrue);
      expect(repository.currentSnapshot.isReplay, isFalse);

      await repository.stopTracking();

      final sessions = await database.acquisitionDao.allSessions();
      expect(sessions, hasLength(1));
      final job =
          await database.acquisitionDao.syncJobForSession(sessions.single.id);
      expect(job, isNotNull);
      expect(queue.kickCount, 1);
      expect(repository.currentSnapshot.isTracking, isFalse);
    });

    test('replay stop posts inline core and does not create local sync jobs',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _FakeTripIngestionService()
        ..replayData = _simpleReplayData()
        ..inlineCoreTripId = 99;
      final queue = _FakeTripSyncQueue();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        ingestionService: service,
        syncQueue: queue,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);

      await repository.startReplay(42, replaySpeedMultiplier: 5);
      expect(repository.currentSnapshot.isTracking, isTrue);
      expect(repository.currentSnapshot.isReplay, isTrue);

      final result = await repository.stopReplay();

      expect(result.tripId, 99);
      expect(service.startedSourceTripIds, [42]);
      expect(service.postedCoreBodies, hasLength(1));
      expect(await database.acquisitionDao.countSessions(), 0);
      expect(queue.kickCount, 0);
      expect(repository.currentSnapshot.isTracking, isFalse);
    });

    test('replay sensor window is delegated to the replay service offset',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final service = _FakeTripIngestionService()
        ..replayData = _simpleReplayData()
        ..replaySensorWindow = const [
          [1, 2, 3, 4, 5, 6],
        ];
      final repository = AcquisitionRepositoryImpl(
        database: database,
        ingestionService: service,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);

      await repository.startReplay(7);

      final window = await repository.currentSensorWindow();

      expect(window, service.replaySensorWindow);
      expect(service.sensorWindowRequests.single.tripId, 7);
    });
  });
}

Map<String, dynamic> _simpleReplayData() {
  return {
    'gps_points': [
      {
        'timestamp': '2026-01-01T08:00:00Z',
        'latitude': 45.0,
        'longitude': 9.0,
        'accuracy_meters': 5.0,
        'speed_mps': 1.2,
      },
    ],
    'state_transitions': [
      {
        'timestamp': '2026-01-01T08:00:00Z',
        'from_state': 'STATIONARY',
        'to_state': 'MOVEMENT',
        'reason': 'replay',
      },
    ],
  };
}

class _FakeTripSyncQueue implements TripSyncQueue {
  int kickCount = 0;

  @override
  Future<void> kick() async {
    kickCount += 1;
  }
}

class _SensorWindowRequest {
  final int tripId;
  final int offsetSeconds;

  const _SensorWindowRequest(this.tripId, this.offsetSeconds);
}

class _FakeTripIngestionService implements TripIngestionService {
  int _nextIngestionId = 100;
  int? inlineCoreTripId;
  Map<String, dynamic> replayData = const {};
  List<List<double>> replaySensorWindow = const [];
  final List<int?> startedSourceTripIds = [];
  final List<Map<String, dynamic>> postedCoreBodies = [];
  final List<_SensorWindowRequest> sensorWindowRequests = [];

  @override
  Future<IngestionStartResultDto> startIngestion({
    required String clientSessionId,
    required DateTime startedAt,
    required String deviceId,
    String devicePlatform = '',
    int? sourceTripId,
  }) async {
    startedSourceTripIds.add(sourceTripId);
    return IngestionStartResultDto(
      ingestionId: _nextIngestionId++,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
      recordingStartedAt: startedAt,
      alreadyExists: false,
    );
  }

  @override
  Future<Map<String, dynamic>> getReplayData(int tripId) async {
    return replayData;
  }

  @override
  Future<List<List<double>>> getReplaySensorWindow(
    int tripId,
    int offsetSeconds,
  ) async {
    sensorWindowRequests.add(_SensorWindowRequest(tripId, offsetSeconds));
    return replaySensorWindow;
  }

  @override
  Future<InlineCoreResultDto> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    postedCoreBodies.add(body);
    return InlineCoreResultDto(
      ingestionId: body['ingestion_id'] as int? ?? 0,
      tripId: inlineCoreTripId,
      coreStatus: 'COMPLETED',
      rawStatus: 'COMPLETED',
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
    return _nextIngestionId++;
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
  }) async {}

  @override
  Future<ActiveIngestionDto?> getActiveIngestion() async {
    return null;
  }

  @override
  Future<IngestionStatusDto> getStatus(int ingestionId) async {
    return const IngestionStatusDto(
      coreStatus: 'COMPLETED',
      rawStatus: 'COMPLETED',
      missingCoreParts: [],
      missingRawParts: [],
      coreIngestionMode: 'INLINE',
      mapAvailable: true,
    );
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
    return const PresignResultDto(
      objectKey: 'unused',
      uploadUrl: 'http://unused',
      uploadHeaders: {},
    );
  }

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {}

  @override
  Future<void> confirmPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
  }) async {}
}

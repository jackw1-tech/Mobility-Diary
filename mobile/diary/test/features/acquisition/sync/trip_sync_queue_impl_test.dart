import 'dart:io';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/sensor_matrix_blob.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue_impl.dart';
import 'package:diary/network/dto/trip_list_item_dto.dart';
import 'package:diary/network/dto/trip_reload_dto.dart';
import 'package:diary/network/dto/trip_reload_slots_dto.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Un fallimento definitivo (core o raw, o tentativi esauriti) non deve mai
/// restare in attesa di un'azione dell'utente: la coda lo scarta subito da
/// sola (Trip lato backend eliminato se gia' esistente, dati locali
/// cancellati). Questi test lo verificano end-to-end attraverso
/// `processDue()`, senza toccare direttamente i metodi privati.
void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('trip_sync_queue_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  TripSyncQueueImpl buildQueue({
    required AcquisitionDao dao,
    required _FakeIngestionApi api,
    TripsService? tripsService,
    List<Duration>? backoff,
    int maxAttempts = 5,
    int sensorWindowsPartBudgetBytes = 12 * 1024 * 1024,
    Duration processingPollDelay = const Duration(seconds: 2),
    int rawUploadConcurrency = 3,
  }) {
    return TripSyncQueueImpl(
      dao: dao,
      builder: TripPackageBuilder(
        dao: dao,
        baseDirProvider: () async => tempDir,
        sensorWindowsPartBudgetBytes: sensorWindowsPartBudgetBytes,
      ),
      api: api,
      tokenProvider: () async => 'token',
      tripsService: tripsService,
      backoff: backoff ??
          const [
            Duration.zero,
            Duration.zero,
            Duration.zero,
            Duration.zero,
          ],
      maxAttempts: maxAttempts,
      processingPollDelay: processingPollDelay,
      rawUploadConcurrency: rawUploadConcurrency,
    );
  }

  Future<void> seedSessionWithCoreEvidence(
    AcquisitionDao dao,
    String sessionId,
  ) async {
    final startedAt = DateTime.utc(2026, 1, 1, 8);
    await dao.createSession(
      id: sessionId,
      deviceId: 'dev',
      startedAt: startedAt,
    );
    await dao.insertGpsPoint(
      sessionId: sessionId,
      latitude: 44.0,
      longitude: 11.0,
      timestamp: startedAt,
      speedMps: 1,
    );
    await dao.endSession(
      id: sessionId,
      endedAt: startedAt.add(const Duration(minutes: 5)),
    );
  }

  Future<void> seedSensorWindows(
    AcquisitionDao dao,
    String sessionId,
    int count,
  ) async {
    final startedAt = DateTime.utc(2026, 1, 1, 8);
    for (var i = 0; i < count; i += 1) {
      await dao.insertSensorWindow(
        sessionId: sessionId,
        startTimestamp: startedAt.add(Duration(seconds: i * 5)),
        endTimestamp: startedAt.add(Duration(seconds: i * 5 + 5)),
        sampleCount: 1,
        frequencyHz: 100,
        matrixBlob: encodeSensorMatrixJsonToBlob(
          '[[0.0,0.0,0.0,0.0,0.0,0.0]]',
        ),
      );
    }
  }

  test(
      'discards automatically when core processing fails permanently '
      '(no Trip ever existed)', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await seedSessionWithCoreEvidence(dao, 'core-failed-session');
    await dao.createSyncJobIfAbsent('core-failed-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineResult = const InlineCoreResult(
        ingestionId: 1,
        tripId: null,
        coreStatus: 'FAILED_FINAL',
        rawStatus: 'PENDING',
        gpsPoints: 1,
        stateTransitions: 0,
        pathPoints: 0,
        distanceMeters: 0,
        mapAvailable: false,
      );
    final tripsService = _FakeTripsService();
    final queue = buildQueue(dao: dao, api: api, tripsService: tripsService);

    await queue.processDue();

    expect(await dao.findSession('core-failed-session'), isNull);
    expect(await dao.syncJobForSession('core-failed-session'), isNull);
    // Il core non e' mai stato materializzato: nessun Trip da eliminare.
    expect(tripsService.deletedTripIds, isEmpty);
  });

  test(
      'discards automatically and deletes the backend Trip when core '
      'succeeded but raw failed for good', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await seedSessionWithCoreEvidence(dao, 'raw-failed-session');
    await dao.createSyncJobIfAbsent('raw-failed-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineResult = const InlineCoreResult(
        ingestionId: 5,
        tripId: 777,
        coreStatus: 'COMPLETED',
        rawStatus: 'FAILED_FINAL',
        gpsPoints: 1,
        stateTransitions: 0,
        pathPoints: 1,
        distanceMeters: 10,
        mapAvailable: true,
      );
    final tripsService = _FakeTripsService();
    final queue = buildQueue(dao: dao, api: api, tripsService: tripsService);

    await queue.processDue();

    expect(tripsService.deletedTripIds, [777]);
    expect(await dao.findSession('raw-failed-session'), isNull);
    expect(await dao.syncJobForSession('raw-failed-session'), isNull);
  });

  test('discards automatically once upload attempts are exhausted', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await seedSessionWithCoreEvidence(dao, 'exhausted-session');
    await dao.createSyncJobIfAbsent('exhausted-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineError =
          const IngestionApiException('rete non disponibile');
    final tripsService = _FakeTripsService();
    final queue = buildQueue(
      dao: dao,
      api: api,
      tripsService: tripsService,
      maxAttempts: 2,
      backoff: const [Duration.zero],
    );

    await queue.processDue(); // tentativo 1: fallisce, riprovabile
    final job = await dao.syncJobForSession('exhausted-session');
    expect(job!.coreStatus, syncJobFailedRetryable);

    await queue.processDue(); // tentativo 2: fallisce, tentativi esauriti

    expect(await dao.findSession('exhausted-session'), isNull);
    expect(await dao.syncJobForSession('exhausted-session'), isNull);
    expect(tripsService.deletedTripIds, isEmpty);
  });

  test('purges a session with genuinely nothing to sync', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await dao.createSession(
      id: 'empty-session',
      deviceId: 'dev',
      startedAt: DateTime.utc(2026, 1, 1),
    );
    await dao.endSession(
      id: 'empty-session',
      endedAt: DateTime.utc(2026, 1, 1, 0, 1),
    );
    await dao.createSyncJobIfAbsent('empty-session');

    final queue = buildQueue(dao: dao, api: _FakeIngestionApi());

    await queue.processDue();

    expect(await dao.findSession('empty-session'), isNull);
    expect(await dao.syncJobForSession('empty-session'), isNull);
  });

  test('discards a session with raw parts but no core evidence', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    final startedAt = DateTime.utc(2026, 1, 1, 8);
    await dao.createSession(
      id: 'raw-only-session',
      deviceId: 'dev',
      startedAt: startedAt,
    );
    await dao.insertSensorWindow(
      sessionId: 'raw-only-session',
      startTimestamp: startedAt,
      endTimestamp: startedAt.add(const Duration(seconds: 5)),
      sampleCount: 1,
      frequencyHz: 100,
      matrixBlob: encodeSensorMatrixJsonToBlob(
        '[[0.0,0.0,0.0,0.0,0.0,0.0]]',
      ),
    );
    await dao.endSession(
      id: 'raw-only-session',
      endedAt: startedAt.add(const Duration(minutes: 1)),
    );
    await dao.createSyncJobIfAbsent('raw-only-session');

    final tripsService = _FakeTripsService();
    final queue = buildQueue(
      dao: dao,
      api: _FakeIngestionApi(),
      tripsService: tripsService,
    );

    await queue.processDue();

    expect(await dao.findSession('raw-only-session'), isNull);
    expect(await dao.syncJobForSession('raw-only-session'), isNull);
    expect(tripsService.deletedTripIds, isEmpty);
  });

  test('uploads raw parts concurrently within the configured limit', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await seedSessionWithCoreEvidence(dao, 'parallel-upload-session');
    await seedSensorWindows(dao, 'parallel-upload-session', 3);
    await dao.createSyncJobIfAbsent('parallel-upload-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineResult = const InlineCoreResult(
        ingestionId: 42,
        tripId: 777,
        coreStatus: 'COMPLETED',
        rawStatus: 'PENDING',
        gpsPoints: 1,
        stateTransitions: 0,
        pathPoints: 1,
        distanceMeters: 10,
        mapAvailable: true,
      )
      ..statusAfterRawComplete = const IngestionStatus(
        coreStatus: 'COMPLETED',
        rawStatus: 'COMPLETED',
        missingCoreParts: [],
        missingRawParts: [],
        tripId: 777,
        mapAvailable: true,
      )
      ..uploadDelay = const Duration(milliseconds: 30);
    final queue = buildQueue(
      dao: dao,
      api: api,
      sensorWindowsPartBudgetBytes: 53,
      rawUploadConcurrency: 2,
    );

    await queue.processDue();

    expect(api.maxConcurrentUploads, 2);
    expect(api.confirmedSequences, unorderedEquals([1, 2, 3]));
    expect(await dao.findSession('parallel-upload-session'), isNull);
  });

  test('uses fast polling while raw processing is in flight', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await seedSessionWithCoreEvidence(dao, 'fast-poll-session');
    await dao.createSyncJobIfAbsent('fast-poll-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineResult = const InlineCoreResult(
        ingestionId: 9,
        tripId: 123,
        coreStatus: 'COMPLETED',
        rawStatus: 'PROCESSING',
        gpsPoints: 1,
        stateTransitions: 0,
        pathPoints: 1,
        distanceMeters: 10,
        mapAvailable: true,
      );
    final before = DateTime.now().toUtc();
    final queue = buildQueue(
      dao: dao,
      api: api,
      processingPollDelay: const Duration(seconds: 2),
    );

    await queue.processDue();

    final job = await dao.syncJobForSession('fast-poll-session');
    expect(job!.rawStatus, syncJobWaitingProcessing);
    expect(job.nextRetryAt!.difference(before),
        lessThan(const Duration(seconds: 4)));
  });

  test(
      'falls back to presigned core parts when inline core is rejected as '
      'too large (413)', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await seedSessionWithCoreEvidence(dao, 'core-too-big-session');
    await dao.createSyncJobIfAbsent('core-too-big-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineError =
          const IngestionApiException('troppo grande', statusCode: 413)
      ..createIngestionResult = 501
      ..statusSequence = const [
        IngestionStatus(
          coreStatus: 'PENDING',
          rawStatus: 'PENDING',
          missingCoreParts: [],
          missingRawParts: [],
        ),
        IngestionStatus(
          coreStatus: 'COMPLETED',
          rawStatus: 'COMPLETED',
          missingCoreParts: [],
          missingRawParts: [],
          tripId: 909,
          mapAvailable: true,
        ),
      ];
    final queue = buildQueue(dao: dao, api: api);

    await queue.processDue();

    // Niente inline (413): l'ingestion e' stata creata e la parte core (solo
    // gps_points: seedSessionWithCoreEvidence non inserisce transizioni)
    // caricata/confermata come fallback, invece di scartare il viaggio.
    expect(api.createIngestionCalls, hasLength(1));
    expect(api.createIngestionCalls.single.core, {'gps_points': 1});
    expect(api.confirmedKinds, ['gps_points']);
    expect(api.completeCoreTotalParts, [1]);
    expect(await dao.findSession('core-too-big-session'), isNull);
  });

  test(
      'still tries inline first (and falls back correctly on 413) even when '
      'start_ingestion already assigned a remote id — a known ingestion id '
      'is not itself a signal that a parts fallback is under way', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    // A differenza di seedSessionWithCoreEvidence, qui la sessione ha GIA' un
    // remoteIngestionId — esattamente come dopo una start_ingestion riuscita
    // all'avvio della registrazione, il caso comune per QUALSIASI viaggio,
    // non solo quelli troppo grandi per l'inline.
    await dao.createSession(
      id: 'already-started-session',
      deviceId: 'dev',
      startedAt: DateTime.utc(2026, 1, 1, 8),
      remoteIngestionId: 321,
    );
    await dao.insertGpsPoint(
      sessionId: 'already-started-session',
      latitude: 44.0,
      longitude: 11.0,
      timestamp: DateTime.utc(2026, 1, 1, 8),
      speedMps: 1,
    );
    await dao.endSession(
      id: 'already-started-session',
      endedAt: DateTime.utc(2026, 1, 1, 8, 5),
    );
    await dao.createSyncJobIfAbsent('already-started-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineResult = const InlineCoreResult(
        ingestionId: 321,
        tripId: 555,
        coreStatus: 'COMPLETED',
        rawStatus: 'COMPLETED',
        gpsPoints: 1,
        stateTransitions: 0,
        pathPoints: 1,
        distanceMeters: 5,
        mapAvailable: true,
      );
    final queue = buildQueue(dao: dao, api: api);

    await queue.processDue();

    // L'inline va provato normalmente: niente createIngestion, niente parti.
    expect(api.createIngestionCalls, isEmpty);
    expect(api.confirmedKinds, isEmpty);
    expect(await dao.findSession('already-started-session'), isNull);
  });

  test(
      'falls back to parts on 413 even when start_ingestion already '
      'assigned a remote id', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await dao.createSession(
      id: 'already-started-too-big-session',
      deviceId: 'dev',
      startedAt: DateTime.utc(2026, 1, 1, 8),
      remoteIngestionId: 654,
    );
    await dao.insertGpsPoint(
      sessionId: 'already-started-too-big-session',
      latitude: 44.0,
      longitude: 11.0,
      timestamp: DateTime.utc(2026, 1, 1, 8),
      speedMps: 1,
    );
    await dao.endSession(
      id: 'already-started-too-big-session',
      endedAt: DateTime.utc(2026, 1, 1, 8, 5),
    );
    await dao.createSyncJobIfAbsent('already-started-too-big-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineError =
          const IngestionApiException('troppo grande', statusCode: 413)
      ..createIngestionResult = 654
      ..statusSequence = const [
        IngestionStatus(
          coreStatus: 'PENDING',
          rawStatus: 'PENDING',
          missingCoreParts: [],
          missingRawParts: [],
        ),
        IngestionStatus(
          coreStatus: 'COMPLETED',
          rawStatus: 'COMPLETED',
          missingCoreParts: [],
          missingRawParts: [],
          tripId: 654,
          mapAvailable: true,
        ),
      ];
    final queue = buildQueue(dao: dao, api: api);

    await queue.processDue();

    // Il fallback deve scattare comunque, nonostante l'id gia' noto.
    expect(api.createIngestionCalls, hasLength(1));
    expect(api.confirmedKinds, ['gps_points']);
    expect(
      await dao.findSession('already-started-too-big-session'),
      isNull,
    );
  });

  test(
      'discards a session when inline core fails for a reason other than '
      'payload size', () async {
    final database = AcquisitionLocalDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dao = database.acquisitionDao;
    await seedSessionWithCoreEvidence(dao, 'core-other-error-session');
    await dao.createSyncJobIfAbsent('core-other-error-session');

    final api = _FakeIngestionApi()
      ..postCoreInlineError =
          const IngestionApiException('sessione scaduta', statusCode: 401);
    final queue = buildQueue(
      dao: dao,
      api: api,
      backoff: const [Duration.zero],
      maxAttempts: 1,
    );

    await queue.processDue();

    // Un 401 non e' un problema di dimensione: niente fallback a parti,
    // il job viene scartato secondo la logica di retry esistente.
    expect(api.createIngestionCalls, isEmpty);
    expect(await dao.findSession('core-other-error-session'), isNull);
  });
}

class _FakeIngestionApi implements TripIngestionApi {
  InlineCoreResult? postCoreInlineResult;
  Object? postCoreInlineError;
  IngestionStatus? statusAfterRawComplete;
  final _statusQueue = <IngestionStatus>[];
  int? createIngestionResult;
  final createIngestionCalls = <({Map<String, int> core, Map<String, int> raw})>[];
  final completeCoreTotalParts = <int>[];
  Duration uploadDelay = Duration.zero;
  var activeUploads = 0;
  var maxConcurrentUploads = 0;
  final confirmedSequences = <int>[];
  final confirmedKinds = <String>[];

  /// Risposte in sequenza per chiamate successive a [getStatus] (usato dal
  /// percorso a parti, che interroga lo stato piu' volte in un solo job).
  set statusSequence(List<IngestionStatus> statuses) {
    _statusQueue
      ..clear()
      ..addAll(statuses);
  }

  @override
  Future<InlineCoreResult> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    final failure = postCoreInlineError;
    if (failure != null) throw failure;
    return postCoreInlineResult!;
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
    createIngestionCalls
        .add((core: expectedCoreParts, raw: expectedRawParts));
    return createIngestionResult!;
  }

  @override
  Future<void> completeCoreIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {
    completeCoreTotalParts.add(totalParts);
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
      uploadUrl: 'memory://upload/$sequence',
    );
  }

  @override
  Future<void> uploadPart(
    String uploadUrl,
    List<int> bytes, {
    Map<String, String> headers = const {},
  }) async {
    activeUploads += 1;
    if (activeUploads > maxConcurrentUploads) {
      maxConcurrentUploads = activeUploads;
    }
    try {
      if (uploadDelay > Duration.zero) {
        await Future<void>.delayed(uploadDelay);
      }
    } finally {
      activeUploads -= 1;
    }
  }

  @override
  Future<void> confirmPart(
    int ingestionId, {
    required String kind,
    required int sequence,
    required String sha256,
  }) async {
    confirmedSequences.add(sequence);
    confirmedKinds.add(kind);
  }

  @override
  Future<void> completeRawIngestion(
    int ingestionId, {
    required int totalParts,
  }) async {}

  @override
  Future<IngestionStatus> getStatus(int ingestionId) async {
    if (_statusQueue.isNotEmpty) {
      return _statusQueue.removeAt(0);
    }
    return statusAfterRawComplete!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeTripsService implements TripsService {
  final List<int> deletedTripIds = [];

  @override
  Future<void> deleteTrip(int tripId) async {
    deletedTripIds.add(tripId);
  }

  @override
  Future<List<TripListItemDto>> fetchTrips() async => const [];

  @override
  Future<List<TripListItemDto>> fetchReloadableTrips() async => const [];

  @override
  Future<TripReloadSlotsDto> fetchReloadSlots(int sourceTripId) async {
    return TripReloadSlotsDto(
      sourceTripId: sourceTripId,
      durationSeconds: 0,
      slots: const [],
    );
  }

  @override
  Future<TripListItemDto> setTripReloadable({
    required int tripId,
    required bool isReloadable,
  }) =>
      throw UnimplementedError();

  @override
  Future<TripListItemDto> updateTripNote({
    required int tripId,
    required String note,
  }) =>
      throw UnimplementedError();

  @override
  Future<TripReloadDto> reloadTrip({
    required int sourceTripId,
    required String reloadRequestId,
    DateTime? scheduledStartAt,
  }) =>
      throw UnimplementedError();
}

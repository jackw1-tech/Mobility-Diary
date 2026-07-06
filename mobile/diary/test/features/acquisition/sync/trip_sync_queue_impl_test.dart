import 'dart:io';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
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
  }) {
    return TripSyncQueueImpl(
      dao: dao,
      builder: TripPackageBuilder(
        dao: dao,
        baseDirProvider: () async => tempDir,
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
      ..postCoreInlineError = const IngestionApiException('rete non disponibile');
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
      matrixJson: '[[0.0,0.0,0.0,0.0,0.0,0.0]]',
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
}

class _FakeIngestionApi implements TripIngestionApi {
  InlineCoreResult? postCoreInlineResult;
  Object? postCoreInlineError;

  @override
  Future<InlineCoreResult> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    final failure = postCoreInlineError;
    if (failure != null) throw failure;
    return postCoreInlineResult!;
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

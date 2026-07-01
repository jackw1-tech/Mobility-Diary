import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';

void main() {
  group('AcquisitionCubit', () {
    test('starts from repository idle snapshot', () {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      expect(cubit.state.status, AcquisitionCubitStatus.idle);
      expect(cubit.state.trackingState, TrackingState.stationary);
    });

    test('starts tracking and applies FSM events through repository', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);
      final now = DateTime.utc(2026, 1, 1);

      await cubit.startTracking();

      expect(cubit.state.status, AcquisitionCubitStatus.tracking);
      expect(cubit.state.samplingProfile.accelerometerHz, 10);

      for (var index = 0; index < 4; index += 1) {
        await cubit.ingestEvent(
          MotionWindowEvaluated(
            timestamp: now.add(Duration(seconds: index * 2)),
            sigma: 1.2,
            sampleCount: 20,
          ),
        );
      }

      expect(cubit.state.trackingState, TrackingState.movement);
      expect(cubit.state.samplingProfile.accelerometerHz, 100);
      expect(cubit.state.samplingProfile.gyroscopeHz, 100);
    });

    test('restores the recorded route on reopen so the map can redraw it',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      // Sessione locale ancora aperta (viaggio in corso quando l'app si chiude).
      await dao.createSession(
        id: 'reopen-session',
        deviceId: 'dev',
        startedAt: startedAt,
      );
      const coordinates = [
        LatLng(44.10, 11.10),
        LatLng(44.11, 11.11),
        LatLng(44.12, 11.12),
      ];
      for (var i = 0; i < coordinates.length; i += 1) {
        await dao.insertGpsPoint(
          sessionId: 'reopen-session',
          latitude: coordinates[i].latitude,
          longitude: coordinates[i].longitude,
          timestamp: startedAt.add(Duration(minutes: i)),
          speedMps: 1.0,
        );
      }

      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      final restored = await cubit.stream.firstWhere(
        (state) => state.routePoints.length >= 3,
      );

      expect(restored.status, AcquisitionCubitStatus.tracking);
      expect(restored.routePoints, coordinates);
    });

    test('closing during route restore does not emit after close', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);
      await dao.createSession(
        id: 'reopen-session',
        deviceId: 'dev',
        startedAt: startedAt,
      );
      for (var i = 0; i < 3; i += 1) {
        await dao.insertGpsPoint(
          sessionId: 'reopen-session',
          latitude: 44.10 + i,
          longitude: 11.10 + i,
          timestamp: startedAt.add(Duration(minutes: i)),
          speedMps: 1.0,
        );
      }

      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      addTearDown(repository.dispose);

      // Costruzione + chiusura immediata: il ripristino (fire-and-forget) deve
      // completare senza lanciare "Cannot emit new states after calling close".
      final cubit = AcquisitionCubit(repository);
      await cubit.close();
      await Future<void>.delayed(const Duration(milliseconds: 50));

      expect(cubit.isClosed, isTrue);
    });

    test('restoreActiveTrip re-checks for an active trip after autologin',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final api = _CountingActiveLookupApi();
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: api,
        deviceIdProvider: () async => 'stable-device',
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      // Lascia completare il ripristino del costruttore (1 verifica).
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(api.activeLookupCount, 1);

      // Trigger post-autologin: deve rifare la verifica.
      await cubit.restoreActiveTrip();
      expect(api.activeLookupCount, 2);
    });

    test('surfaces sync status after stop', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      await cubit.startTracking();
      final pendingStateFuture = cubit.stream.firstWhere(
        (state) => state.syncSnapshot.status == AcquisitionSyncStatus.pending,
      );

      await cubit.stopTracking();
      final pendingState = await pendingStateFuture;

      expect(pendingState.status, AcquisitionCubitStatus.idle);
      expect(pendingState.syncSnapshot.status, AcquisitionSyncStatus.pending);
      expect(pendingState.syncSnapshot.localSessionId, isNotNull);
    });

    test('dismisses non-recoverable sync state from the current UI', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final dao = database.acquisitionDao;
      final now = DateTime.utc(2026, 1, 1);
      await dao.createSession(
        id: 'failed-session',
        deviceId: 'dev',
        startedAt: now,
      );
      final job = await dao.createSyncJobIfAbsent('failed-session');
      await dao.updateSyncJob(job.id, coreStatus: syncJobFailedFinal);
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      final failedState = await cubit.stream.firstWhere(
        (state) => state.syncSnapshot.isNonRecoverable,
      );
      expect(failedState.syncSnapshot.canRetry, isFalse);

      cubit.dismissNonRecoverableSync();

      expect(cubit.state.syncSnapshot.hasJob, isFalse);
    });

    test('surfaces pending stop message when starting before sync closes core',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      await cubit.startTracking();
      await cubit.stopTracking();

      await expectLater(
        cubit.startTracking(),
        throwsA(isA<PendingTripSyncException>()),
      );

      expect(cubit.state.errorMessage, PendingTripSyncException.defaultMessage);
      expect(cubit.state.status, AcquisitionCubitStatus.idle);
    });

    test('surfaces backend connection message when start cannot reach backend',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: _StartFailureApi(),
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      await expectLater(
        cubit.startTracking(),
        throwsA(isA<StartRequiresConnectionException>()),
      );

      expect(
        cubit.state.errorMessage,
        StartRequiresConnectionException.defaultMessage,
      );
      expect(cubit.state.status, AcquisitionCubitStatus.idle);
    });

    test('surfaces another-device start conflict message', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: _AnotherDeviceConflictApi(),
        deviceIdProvider: () async => 'this-device',
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      await expectLater(
        cubit.startTracking(),
        throwsA(isA<ActiveTripOnAnotherDeviceException>()),
      );

      expect(
        cubit.state.errorMessage,
        ActiveTripOnAnotherDeviceException.defaultMessage,
      );
      expect(cubit.state.status, AcquisitionCubitStatus.idle);
    });

    test('startReplay initiates replay and emits tracking status', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: _FakeTripIngestionApi(),
        deviceIdProvider: () async => 'this-device',
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      await cubit.startReplay(123);

      expect(cubit.state.status, AcquisitionCubitStatus.tracking);
      expect(cubit.state.completedReplayTripId, isNull);
    });

    test('stopReplay emits the completed trip ID and sets status to idle',
        () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: _FakeTripIngestionApi(),
        deviceIdProvider: () async => 'this-device',
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      await cubit.startReplay(123);
      await cubit.stopReplay();

      expect(cubit.state.status, AcquisitionCubitStatus.idle);
      expect(cubit.state.completedReplayTripId, 999);
    });

    test('startReplay clears a previous completed replay trip ID', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      final repository = AcquisitionRepositoryImpl(
        database: database,
        enableRuntime: false,
        ingestionApi: _FakeTripIngestionApi(),
        deviceIdProvider: () async => 'this-device',
      );
      final cubit = AcquisitionCubit(repository);
      addTearDown(repository.dispose);
      addTearDown(cubit.close);

      await cubit.startReplay(123);
      await cubit.stopReplay();
      await cubit.startReplay(123);

      expect(cubit.state.status, AcquisitionCubitStatus.tracking);
      expect(cubit.state.completedReplayTripId, isNull);
    });
  });
}

class _FakeTripIngestionApi implements TripIngestionApi {
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
      ingestionId: 1,
      clientSessionId: clientSessionId,
      deviceId: deviceId,
      recordingStartedAt: startedAt,
      alreadyExists: false,
    );
  }

  @override
  Future<Map<String, dynamic>> getReplayData(int tripId) async {
    return {
      'points': [
        {
          'timestamp': '2026-01-01T08:00:00Z',
          'latitude': 44.0,
          'longitude': 11.0,
          'speed_mps': 1.0,
          'accuracy_meters': 5.0,
        },
      ],
      'transitions': [
        {
          'timestamp': '2026-01-01T08:00:00Z',
          'from_state': 'stationary',
          'to_state': 'vehicle',
          'sigma': 0.0,
          'speed_mps': 0.0,
        }
      ]
    };
  }

  @override
  Future<InlineCoreResult> postCoreInline({
    required Map<String, dynamic> body,
  }) async {
    final expectedRawParts =
        Map<String, dynamic>.from(body['expected_raw_parts'] as Map);
    final rawStatus = expectedRawParts.isEmpty ? 'COMPLETED' : 'PENDING';
    final responseIngestionId = body['ingestion_id'] as int? ?? 123;

    if (responseIngestionId != 123 && body['cutoff_source_timestamp'] == null) {
      throw Exception('Missing cutoff_source_timestamp for replay');
    }

    return InlineCoreResult(
      ingestionId: responseIngestionId,
      tripId: 999,
      coreStatus: 'SAVED',
      rawStatus: rawStatus,
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

class _StartFailureApi implements TripIngestionApi {
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
    throw const IngestionApiException('network offline');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CountingActiveLookupApi implements TripIngestionApi {
  int activeLookupCount = 0;

  @override
  Future<ActiveIngestion?> getActiveIngestion() async {
    activeLookupCount += 1;
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _AnotherDeviceConflictApi implements TripIngestionApi {
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
    throw IngestionApiException(
      "viaggio in corso gia' presente",
      statusCode: 409,
      body: {
        'active_ingestion': {
          'ingestion_id': 7,
          'client_session_id': 'other-session',
          'device_id': 'other-device',
          'recording_started_at': DateTime.utc(2026).toIso8601String(),
          'last_seen_at': DateTime.utc(2026, 1, 1, 0, 5).toIso8601String(),
        },
      },
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

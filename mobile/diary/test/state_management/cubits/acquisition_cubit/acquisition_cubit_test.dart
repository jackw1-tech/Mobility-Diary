import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/repositories/impl/acquisition_repository_impl.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

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
  });
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
  }) async {
    throw const IngestionApiException('network offline');
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

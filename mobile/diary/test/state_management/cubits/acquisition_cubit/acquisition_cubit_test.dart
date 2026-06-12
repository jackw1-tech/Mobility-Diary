import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
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

      expect(cubit.state.trackingState, TrackingState.potentialMotion);
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
  });
}

import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/ui/pages/home_page.dart';
import 'package:flutter_test/flutter_test.dart';

AcquisitionCubitState _state({
  AcquisitionSyncSnapshot syncSnapshot = const AcquisitionSyncSnapshot.none(),
  int? completedReplayTripId,
}) {
  return AcquisitionCubitState.fromSnapshot(
    AcquisitionSnapshot.idle(),
    syncSnapshot: syncSnapshot,
    completedReplayTripId: completedReplayTripId,
  );
}

void main() {
  group('autoOpenTripDetailId', () {
    test('opens when core sync detail becomes available', () {
      final previous = _state(
        syncSnapshot: const AcquisitionSyncSnapshot(
          status: AcquisitionSyncStatus.uploading,
          localSessionId: 'local-1',
        ),
      );
      final current = _state(
        syncSnapshot: const AcquisitionSyncSnapshot(
          status: AcquisitionSyncStatus.completed,
          localSessionId: 'local-1',
          remoteTripId: 42,
          coreMapAvailable: true,
        ),
      );

      expect(autoOpenTripDetailId(previous, current), 42);
    });

    test('does not reopen an already available sync detail', () {
      final previous = _state(
        syncSnapshot: const AcquisitionSyncSnapshot(
          status: AcquisitionSyncStatus.completed,
          remoteTripId: 42,
        ),
      );
      final current = _state(
        syncSnapshot: const AcquisitionSyncSnapshot(
          status: AcquisitionSyncStatus.completed,
          remoteTripId: 42,
        ),
      );

      expect(autoOpenTripDetailId(previous, current), isNull);
    });

    test('opens when a replay finishes with a new trip id', () {
      final previous = _state(completedReplayTripId: 99);
      final current = _state(completedReplayTripId: 100);

      expect(autoOpenTripDetailId(previous, current), 100);
    });

    test('prefers a newly completed replay over an old sync detail', () {
      final previous = _state(
        syncSnapshot: const AcquisitionSyncSnapshot(
          status: AcquisitionSyncStatus.completed,
          remoteTripId: 42,
        ),
        completedReplayTripId: 99,
      );
      final current = _state(
        syncSnapshot: const AcquisitionSyncSnapshot(
          status: AcquisitionSyncStatus.completed,
          remoteTripId: 42,
        ),
        completedReplayTripId: 100,
      );

      expect(autoOpenTripDetailId(previous, current), 100);
    });
  });

  group('syncDebugMessage', () {
    test('announces when HAR raw parts are being uploaded', () {
      const sync = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.uploading,
        localSessionId: 'local-raw',
        remoteIngestionId: 10,
      );

      expect(syncDebugMessage(sync), 'HAR trovata: upload sensor_windows');
    });

    test('announces when raw parts have reached backend processing', () {
      const sync = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.waitingProcessing,
        localSessionId: 'local-raw',
        remoteIngestionId: 10,
      );

      expect(
        syncDebugMessage(sync),
        'Raw confermati. Processing HAR finale',
      );
    });

    test('includes retry details when upload fails before processing', () {
      const sync = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.failedRetryable,
        localSessionId: 'local-raw',
        remoteIngestionId: 10,
        lastError: 'Upload parte fallito',
      );

      expect(syncDebugMessage(sync), 'Sync in retry: Upload parte fallito');
    });
  });
}

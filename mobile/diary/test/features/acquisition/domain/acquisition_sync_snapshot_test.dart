import 'package:diary/features/acquisition/domain/acquisition_sync_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionSyncSnapshot', () {
    test('opens the map only after core completion with a remote trip id', () {
      const ready = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 42,
      );

      const waitingCore = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.waitingProcessing,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 42,
      );

      const missingTrip = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.pending,
      );

      expect(ready.canOpenCoreMap, isTrue);
      expect(waitingCore.canOpenCoreMap, isFalse);
      expect(missingTrip.canOpenCoreMap, isFalse);
    });
  });
}

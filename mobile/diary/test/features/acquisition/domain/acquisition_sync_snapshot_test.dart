import 'package:diary/features/acquisition/domain/acquisition_sync_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionSyncSnapshot', () {
    test('opens the detail after core completion with a remote trip id', () {
      const ready = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 42,
        coreMapAvailable: true,
      );

      const waitingCore = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.waitingProcessing,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 42,
      );

      const missingTrip = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.pending,
        coreMapAvailable: true,
      );

      const missingMapFlag = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 42,
      );

      expect(ready.canOpenCoreDetail, isTrue);
      expect(waitingCore.canOpenCoreDetail, isFalse);
      expect(missingTrip.canOpenCoreDetail, isFalse);
      expect(missingMapFlag.canOpenCoreDetail, isTrue);
    });
  });
}

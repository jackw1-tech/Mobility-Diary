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

    test('opens the detail once per completed remote trip id', () {
      const none = AcquisitionSyncSnapshot.none();
      const waiting = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.waitingProcessing,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 42,
      );
      const completed42 = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 42,
      );
      const completed42Again = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.completed,
        remoteTripId: 42,
      );
      const completed43 = AcquisitionSyncSnapshot(
        status: AcquisitionSyncStatus.completed,
        rawStatus: AcquisitionSyncStatus.pending,
        remoteTripId: 43,
      );

      expect(completed42.shouldOpenCoreDetailAfter(none), isTrue);
      expect(waiting.shouldOpenCoreDetailAfter(none), isFalse);
      expect(completed42Again.shouldOpenCoreDetailAfter(completed42), isFalse);
      expect(completed43.shouldOpenCoreDetailAfter(completed42), isTrue);
    });
  });
}

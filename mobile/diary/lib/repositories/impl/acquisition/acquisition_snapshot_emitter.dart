import 'dart:async';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';

mixin AcquisitionSnapshotEmitter {
  final StreamController<AcquisitionSnapshot> _snapshotController =
      StreamController<AcquisitionSnapshot>.broadcast(sync: true);

  AcquisitionSnapshot _currentSnapshot = AcquisitionSnapshot.idle();

  Stream<AcquisitionSnapshot> get snapshots => _snapshotController.stream;

  AcquisitionSnapshot get currentSnapshot => _currentSnapshot;

  void emitSnapshot(AcquisitionSnapshot snapshot) {
    _currentSnapshot = snapshot;
    if (!_snapshotController.isClosed) {
      _snapshotController.add(snapshot);
    }
  }

  void closeSnapshots() => _snapshotController.close();
}

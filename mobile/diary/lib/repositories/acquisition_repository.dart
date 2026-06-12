import 'package:diary/features/acquisition/domain/acquisition_domain.dart';

abstract class AcquisitionRepository {
  Stream<AcquisitionSnapshot> get snapshots;

  Stream<AcquisitionSyncSnapshot> get syncSnapshots;

  AcquisitionSnapshot get currentSnapshot;

  AcquisitionSyncSnapshot get currentSyncSnapshot;

  Future<void> startTracking();

  Future<void> stopTracking();

  Future<void> ingestEvent(TrackingEvent event);

  /// Riprende in modo opportunistico la sincronizzazione dei SyncJob pendenti
  /// (es. all'avvio app). Non blocca: la coda lavora in background.
  Future<void> resumeSync();

  void dispose();
}

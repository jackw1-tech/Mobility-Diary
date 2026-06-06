import 'package:diary/features/acquisition/domain/acquisition_domain.dart';

abstract class AcquisitionRepository {
  Stream<AcquisitionSnapshot> get snapshots;

  AcquisitionSnapshot get currentSnapshot;

  Future<void> startTracking();

  Future<void> stopTracking();

  Future<void> ingestEvent(TrackingEvent event);

  void dispose();
}

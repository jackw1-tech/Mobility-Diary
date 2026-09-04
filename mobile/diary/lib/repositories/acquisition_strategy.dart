import 'package:diary/model/entities/acquisition/acquisition_domain.dart';

typedef AcquisitionSnapshotListener = void Function(
  AcquisitionSnapshot snapshot,
);

abstract class AcquisitionStrategy {
  Future<void> start();

  Future<AcquisitionStopResult> stop();

  Future<void> ingestEvent(TrackingEvent event);

  Future<List<AcquisitionRoutePoint>> currentSessionRoute();

  Future<List<List<double>>> currentSensorWindow();

  void dispose();
}

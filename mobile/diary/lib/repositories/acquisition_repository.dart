import 'package:diary/model/entities/acquisition/acquisition_domain.dart';

class ActiveTripOnAnotherDeviceException implements Exception {
  static const defaultMessage =
      "Hai gia' un viaggio in corso su un altro dispositivo";

  final String message;

  const ActiveTripOnAnotherDeviceException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

class PendingTripSyncException implements Exception {
  static const defaultMessage =
      'Hai un viaggio in chiusura. Attendi la sincronizzazione prima di iniziarne un altro.';

  final String message;

  const PendingTripSyncException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

class StartRequiresConnectionException implements Exception {
  static const defaultMessage =
      'Serve connessione al backend per avviare un nuovo viaggio.';

  final String message;

  const StartRequiresConnectionException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

class AcquisitionPermissionException implements Exception {
  static const defaultMessage =
      'Per registrare un viaggio serve il permesso di posizione "Sempre": '
      'impostalo dalle impostazioni del telefono.';

  final String message;

  const AcquisitionPermissionException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

abstract class AcquisitionTrackingRepository {
  Stream<AcquisitionSnapshot> get snapshots;

  AcquisitionSnapshot get currentSnapshot;

  Future<void> startTracking();

  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  });

  Future<ReplayStopResult> stopReplay();

  Future<void> stopTracking();

  Future<void> ingestEvent(TrackingEvent event);

  Future<List<AcquisitionRoutePoint>> currentSessionRoute();

  Future<List<List<double>>> currentSensorWindow();

  void dispose();
}

abstract class AcquisitionSyncRepository {
  Stream<AcquisitionSyncSnapshot> get syncSnapshots;

  AcquisitionSyncSnapshot get currentSyncSnapshot;

  Future<void> resumeSync();
}

abstract class AcquisitionLocalTripPurger {
  Future<void> purgeLocalDataForRemoteTrip(int tripId);
}

abstract class AcquisitionRepository
    implements
        AcquisitionTrackingRepository,
        AcquisitionSyncRepository,
        AcquisitionLocalTripPurger {}

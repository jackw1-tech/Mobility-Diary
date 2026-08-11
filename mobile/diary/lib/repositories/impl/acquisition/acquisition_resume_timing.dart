import 'package:diary/network/service/impl/acquisition_local_database.dart';

/// Calcoli temporali usati alla ripresa di una sessione aperta. Sono funzioni
/// pure sulle righe gia' lette dal DAO: separate dalla strategy perche' sono la
/// parte verificabile in isolamento del recupero sessione.

/// Istante dell'ultimo dato realmente registrato dalla sessione. Serve a capire
/// se la sessione e' stantia e a chiuderla al momento giusto invece che "ora",
/// che includerebbe il buco (es. telefono spento per ore).
DateTime latestKnownEventAt(
  AcquisitionSession session,
  StateTransition? latestTransition,
  GpsPoint? latestGpsPoint,
  SensorWindow? latestSensorWindow,
) {
  var latest = session.startedAt;
  final transitionAt = latestTransition?.timestamp;
  if (transitionAt != null && transitionAt.isAfter(latest)) {
    latest = transitionAt;
  }
  final gpsAt = latestGpsPoint?.timestamp;
  if (gpsAt != null && gpsAt.isAfter(latest)) {
    latest = gpsAt;
  }
  final sensorAt = latestSensorWindow?.endTimestamp;
  if (sensorAt != null && sensorAt.isAfter(latest)) {
    latest = sensorAt;
  }
  return latest;
}

/// Ultimo istante in cui abbiamo avuto evidenza inerziale. Da qui si misura da
/// quanto i sensori tacciono, per correggere uno stato "movimento" rimasto
/// appeso mentre l'app era in background.
DateTime resumeInertialReferenceAt(
  AcquisitionSession session,
  StateTransition? latestTransition,
  SensorWindow? latestSensorWindow,
) {
  var referenceAt = latestSensorWindow?.endTimestamp ?? session.startedAt;
  final transitionAt = latestTransition?.timestamp;
  if (transitionAt != null && transitionAt.isAfter(referenceAt)) {
    referenceAt = transitionAt;
  }
  return referenceAt;
}

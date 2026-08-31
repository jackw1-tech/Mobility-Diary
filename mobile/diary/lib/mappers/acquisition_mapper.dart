import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';

/// Converte le righe del database locale di acquisizione nelle entity di
/// dominio. E' il gemello locale di [IngestionMapper], che copre invece i DTO
/// di rete: il DB Drift e' l'altra sorgente dati dell'acquisizione, e le sue
/// righe generate sono a tutti gli effetti i suoi "DTO".
class AcquisitionMapper {
  AcquisitionSyncSnapshot mapSyncSnapshot(SyncJob? job) {
    if (job == null) {
      return const AcquisitionSyncSnapshot.none();
    }

    return AcquisitionSyncSnapshot(
      status: mapSyncStatus(job.coreStatus),
      rawStatus: mapSyncStatus(job.rawStatus),
      localSessionId: job.localSessionId,
      remoteIngestionId: job.remoteIngestionId,
      remoteTripId: job.remoteTripId,
      coreMapAvailable: job.coreMapAvailable,
      attempts: job.attempts,
      nextRetryAt: job.nextRetryAt,
      lastError: job.lastError,
      updatedAt: job.updatedAt,
    );
  }

  AcquisitionSyncStatus mapSyncStatus(String status) {
    switch (status) {
      case syncJobPending:
        return AcquisitionSyncStatus.pending;
      case syncJobPackaging:
        return AcquisitionSyncStatus.packaging;
      case syncJobUploading:
        return AcquisitionSyncStatus.uploading;
      case syncJobWaitingProcessing:
        return AcquisitionSyncStatus.waitingProcessing;
      case syncJobCompleted:
        return AcquisitionSyncStatus.completed;
      case syncJobFailedRetryable:
        return AcquisitionSyncStatus.failedRetryable;
      case syncJobFailedFinal:
        return AcquisitionSyncStatus.failedFinal;
    }

    return AcquisitionSyncStatus.none;
  }

  /// Punti GPS di una sessione locale, nella forma condivisa col payload core.
  List<CoreGpsPoint> mapGpsPoints(List<GpsPoint> rows) {
    return [
      for (final row in rows)
        CoreGpsPoint(
          timestamp: row.timestamp,
          latitude: row.latitude,
          longitude: row.longitude,
          speedMps: row.speedMps,
          accuracyMeters: row.accuracyMeters,
        ),
    ];
  }

  /// Transizioni FSM di una sessione locale. A differenza di quelle rigiocate
  /// portano le evidenze della decisione (sigma e velocita').
  List<CoreStateTransition> mapStateTransitions(List<StateTransition> rows) {
    return [
      for (final row in rows)
        CoreStateTransition(
          timestamp: row.timestamp,
          fromState: row.fromState,
          toState: row.toState,
          reason: row.reason,
          sigma: row.sigma,
          speedMps: row.speedMps,
        ),
    ];
  }

  /// Istante dell'ultimo dato realmente registrato dalla sessione. Serve a
  /// capire se la sessione e' stantia e a chiuderla al momento giusto invece
  /// che "ora", che includerebbe il buco (es. telefono spento per ore).
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

  /// Ultimo istante in cui abbiamo avuto evidenza di essere vivi e in moto. Da
  /// qui si misura da quanto non arriva piu' nulla, per correggere uno stato
  /// "movimento" rimasto appeso mentre l'app era in background.
  ///
  /// Include il GPS e non solo l'inerziale: in background iOS smette di
  /// consegnare CoreMotion ma continua a mandare fix, quindi un viaggio in auto
  /// ha evidenza fresca anche senza una sola finestra sensori.
  DateTime resumeInertialReferenceAt(
    AcquisitionSession session,
    StateTransition? latestTransition,
    SensorWindow? latestSensorWindow,
    GpsPoint? latestGpsPoint,
  ) {
    var referenceAt = latestSensorWindow?.endTimestamp ?? session.startedAt;
    final transitionAt = latestTransition?.timestamp;
    if (transitionAt != null && transitionAt.isAfter(referenceAt)) {
      referenceAt = transitionAt;
    }
    final gpsAt = latestGpsPoint?.timestamp;
    if (gpsAt != null && gpsAt.isAfter(referenceAt)) {
      referenceAt = gpsAt;
    }
    return referenceAt;
  }
}

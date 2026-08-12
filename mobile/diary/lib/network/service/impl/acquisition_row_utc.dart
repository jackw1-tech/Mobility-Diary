import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:drift/drift.dart';

/// SQLite non conserva il fuso: le righe rilette vanno rinormalizzate a UTC
/// prima di uscire dal DAO, altrimenti i confronti temporali a valle
/// (staleness, retry, ordinamenti) userebbero un'ora locale implicita.

DateTime asUtc(DateTime value) {
  return value.isUtc ? value : value.toUtc();
}

AcquisitionSession sessionAsUtc(AcquisitionSession session) {
  final endedAt = session.endedAt;
  if (endedAt == null) {
    return session.copyWith(startedAt: asUtc(session.startedAt));
  }
  return session.copyWith(
    startedAt: asUtc(session.startedAt),
    endedAt: Value(asUtc(endedAt)),
  );
}

StateTransition transitionAsUtc(StateTransition transition) {
  return transition.copyWith(timestamp: asUtc(transition.timestamp));
}

GpsPoint gpsPointAsUtc(GpsPoint point) {
  return point.copyWith(timestamp: asUtc(point.timestamp));
}

SensorWindow sensorWindowAsUtc(SensorWindow window) {
  return window.copyWith(
    startTimestamp: asUtc(window.startTimestamp),
    endTimestamp: asUtc(window.endTimestamp),
  );
}

SyncJob syncJobAsUtc(SyncJob job) {
  return job.copyWith(
    createdAt: asUtc(job.createdAt),
    updatedAt: asUtc(job.updatedAt),
    nextRetryAt: Value(
      job.nextRetryAt == null ? null : asUtc(job.nextRetryAt!),
    ),
  );
}

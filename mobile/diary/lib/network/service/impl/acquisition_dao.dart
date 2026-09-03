import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/network/service/impl/acquisition_row_utc.dart';
import 'package:drift/drift.dart';

part 'acquisition_dao.g.dart';

/// Accesso al database locale dell'acquisizione. Tutte le scritture
/// normalizzano i timestamp a UTC e tutte le letture li rinormalizzano
/// uscendo, cosi' il resto dell'app non vede mai un'ora locale implicita.
@DriftAccessor(
  tables: [
    AcquisitionSessions,
    StateTransitions,
    GpsPoints,
    SensorWindows,
    SyncJobs,
  ],
)
class AcquisitionDao extends DatabaseAccessor<AcquisitionLocalDatabase>
    with _$AcquisitionDaoMixin {
  AcquisitionDao(super.db);

  Future<void> createSession({
    required String id,
    required String deviceId,
    required DateTime startedAt,
    int? remoteUploadId,
  }) {
    return into(acquisitionSessions).insert(
      AcquisitionSessionsCompanion.insert(
        id: id,
        deviceId: deviceId,
        remoteUploadId: Value(remoteUploadId),
        startedAt: asUtc(startedAt),
      ),
    );
  }

  Future<void> endSession({
    required String id,
    required DateTime endedAt,
  }) {
    return (update(acquisitionSessions)
          ..where((session) => session.id.equals(id)))
        .write(
      AcquisitionSessionsCompanion(
        endedAt: Value(asUtc(endedAt)),
      ),
    );
  }

  Future<AcquisitionSession?> findSession(String id) {
    return (select(acquisitionSessions)
          ..where((session) => session.id.equals(id)))
        .getSingleOrNull()
        .then((session) => session == null ? null : sessionAsUtc(session));
  }

  Future<AcquisitionSession?> latestOpenSession() {
    return (select(acquisitionSessions)
          ..where((session) => session.endedAt.isNull())
          ..orderBy([
            (session) => OrderingTerm.desc(session.startedAt),
          ])
          ..limit(1))
        .getSingleOrNull()
        .then((session) => session == null ? null : sessionAsUtc(session));
  }

  Future<AcquisitionSession?> findOpenSession(String id) {
    return (select(acquisitionSessions)
          ..where(
            (session) => session.id.equals(id) & session.endedAt.isNull(),
          ))
        .getSingleOrNull()
        .then((session) => session == null ? null : sessionAsUtc(session));
  }

  // --- Transizioni FSM --------------------------------------------------- //

  Future<void> insertTransition({
    required String sessionId,
    required String fromState,
    required String toState,
    required String reason,
    required DateTime timestamp,
    required double sigma,
    required double speedMps,
  }) {
    return into(stateTransitions).insert(
      StateTransitionsCompanion.insert(
        sessionId: sessionId,
        fromState: fromState,
        toState: toState,
        reason: reason,
        timestamp: asUtc(timestamp),
        sigma: Value(sigma),
        speedMps: Value(speedMps),
      ),
    );
  }

  Future<List<StateTransition>> transitionsForSession(String sessionId) {
    return (select(stateTransitions)
          ..where((transition) => transition.sessionId.equals(sessionId))
          ..orderBy([
            (transition) => OrderingTerm.asc(transition.timestamp),
          ]))
        .get()
        .then((transitions) => transitions.map(transitionAsUtc).toList());
  }

  Future<StateTransition?> latestTransitionForSession(String sessionId) {
    return (select(stateTransitions)
          ..where((transition) => transition.sessionId.equals(sessionId))
          ..orderBy([
            (transition) => OrderingTerm.desc(transition.timestamp),
          ])
          ..limit(1))
        .getSingleOrNull()
        .then((transition) =>
            transition == null ? null : transitionAsUtc(transition));
  }

  // --- Punti GPS --------------------------------------------------------- //

  Future<int> insertGpsPoint({
    required String sessionId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    required double speedMps,
    double? accuracyMeters,
    bool accepted = true,
    String? rejectionReason,
  }) {
    return into(gpsPoints).insert(
      GpsPointsCompanion.insert(
        sessionId: sessionId,
        latitude: latitude,
        longitude: longitude,
        timestamp: asUtc(timestamp),
        speedMps: speedMps,
        accuracyMeters: Value(accuracyMeters),
        accepted: Value(accepted),
        rejectionReason: Value(rejectionReason),
      ),
    );
  }

  Future<List<GpsPoint>> gpsPointsForSession(String sessionId) {
    return (select(gpsPoints)
          ..where(
              (p) => p.sessionId.equals(sessionId) & p.accepted.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.timestamp)]))
        .get()
        .then((points) => points.map(gpsPointAsUtc).toList());
  }

  Future<GpsPoint?> latestGpsPointForSession(String sessionId) {
    return (select(gpsPoints)
          ..where(
              (p) => p.sessionId.equals(sessionId) & p.accepted.equals(true))
          ..orderBy([(p) => OrderingTerm.desc(p.timestamp)])
          ..limit(1))
        .getSingleOrNull()
        .then((point) => point == null ? null : gpsPointAsUtc(point));
  }

  Future<int> countGpsPointsForSession(String sessionId) {
    final count = gpsPoints.id.count();
    final query = selectOnly(gpsPoints)
      ..addColumns([count])
      ..where(gpsPoints.sessionId.equals(sessionId));

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<int> insertSensorWindow({
    required String sessionId,
    required DateTime startTimestamp,
    required DateTime endTimestamp,
    required int sampleCount,
    required int frequencyHz,
    required String matrixJson,
  }) {
    return into(sensorWindows).insert(
      SensorWindowsCompanion.insert(
        sessionId: sessionId,
        startTimestamp: asUtc(startTimestamp),
        endTimestamp: asUtc(endTimestamp),
        sampleCount: sampleCount,
        frequencyHz: frequencyHz,
        matrixJson: matrixJson,
      ),
    );
  }

  Future<List<SensorWindow>> sensorWindowsForSession(String sessionId) {
    return (select(sensorWindows)
          ..where((window) => window.sessionId.equals(sessionId))
          ..orderBy([
            (window) => OrderingTerm.asc(window.startTimestamp),
          ]))
        .get()
        .then((windows) => windows.map(sensorWindowAsUtc).toList());
  }

  /// Legge una porzione ordinata delle finestre senza materializzare in RAM
  /// tutta una registrazione lunga. Le sessioni vengono impacchettate solo
  /// dopo lo stop, quindi la paginazione per offset lavora su un insieme
  /// stabile e non puo' saltare righe inserite durante la lettura.
  Future<List<SensorWindow>> sensorWindowsPageForSession(
    String sessionId, {
    required int limit,
    required int offset,
  }) {
    if (limit < 1) {
      throw ArgumentError.value(limit, 'limit', 'deve essere positivo');
    }
    if (offset < 0) {
      throw ArgumentError.value(offset, 'offset', 'non puo essere negativo');
    }
    return (select(sensorWindows)
          ..where((window) => window.sessionId.equals(sessionId))
          ..orderBy([
            (window) => OrderingTerm.asc(window.startTimestamp),
            (window) => OrderingTerm.asc(window.id),
          ])
          ..limit(limit, offset: offset))
        .get()
        .then((windows) => windows.map(sensorWindowAsUtc).toList());
  }

  /// Finestra sensori piu' recente della sessione: usata dalla classificazione
  /// live dell'assistente di percorso. Null se la sessione non ne ha ancora.
  Future<SensorWindow?> latestSensorWindow(String sessionId) {
    return (select(sensorWindows)
          ..where((window) => window.sessionId.equals(sessionId))
          ..orderBy([(window) => OrderingTerm.desc(window.startTimestamp)])
          ..limit(1))
        .getSingleOrNull()
        .then((window) => window == null ? null : sensorWindowAsUtc(window));
  }

  Future<int> countSensorWindowsForSession(String sessionId) {
    final count = sensorWindows.id.count();
    final query = selectOnly(sensorWindows)
      ..addColumns([count])
      ..where(sensorWindows.sessionId.equals(sessionId));

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  // --- Pulizia ----------------------------------------------------------- //

  /// Cancella del tutto una sessione ormai
  Future<void> purgeSyncedSession(String sessionId) {
    return transaction(() async {
      await (delete(stateTransitions)
            ..where((t) => t.sessionId.equals(sessionId)))
          .go();
      await (delete(gpsPoints)..where((p) => p.sessionId.equals(sessionId)))
          .go();
      await (delete(sensorWindows)..where((w) => w.sessionId.equals(sessionId)))
          .go();
      await (delete(syncJobs)..where((j) => j.localSessionId.equals(sessionId)))
          .go();
      await (delete(acquisitionSessions)..where((s) => s.id.equals(sessionId)))
          .go();
    });
  }

  // --- SyncJob ----------------------------------------------------------- //

  /// Sessione locale che ha prodotto un dato Trip remoto, se ancora presente
  /// sul device (es. core riuscito ma raw fallito in modo definitivo: la riga
  /// resta per permettere un retry manuale anche se il Trip e' gia' visibile).
  Future<String?> localSessionIdForRemoteTrip(int tripId) async {
    final job = await (select(syncJobs)
          ..where((j) => j.remoteTripId.equals(tripId)))
        .getSingleOrNull();
    return job?.localSessionId;
  }

  /// Crea il SyncJob per la sessione se non esiste gia' (idempotente: un re-stop
  /// non duplica il job). Ritorna il job esistente o quello appena creato.
  Future<SyncJob> createSyncJobIfAbsent(String localSessionId) async {
    final existing = await (select(syncJobs)
          ..where((j) => j.localSessionId.equals(localSessionId)))
        .getSingleOrNull();
    if (existing != null) {
      return syncJobAsUtc(existing);
    }
    final session = await findSession(localSessionId);
    final now = DateTime.now().toUtc();
    await into(syncJobs).insert(
      SyncJobsCompanion.insert(
        localSessionId: localSessionId,
        remoteUploadId: Value(session?.remoteUploadId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final created = await (select(syncJobs)
          ..where((j) => j.localSessionId.equals(localSessionId)))
        .getSingle();
    return syncJobAsUtc(created);
  }

  /// Job su cui il processore puo' lavorare ora: stato attivo e senza un
  /// next_retry_at futuro.
  Future<List<SyncJob>> claimableSyncJobs(DateTime now) {
    final nowUtc = asUtc(now);
    return (select(syncJobs)
          ..where((j) =>
              (j.coreStatus.isIn(syncJobActiveStatuses) |
                  (j.coreStatus.equals(syncJobCompleted) &
                      j.rawStatus.isIn(syncJobActiveStatuses))) &
              (j.nextRetryAt.isNull() |
                  j.nextRetryAt.isSmallerOrEqualValue(nowUtc)))
          ..orderBy([(j) => OrderingTerm.asc(j.createdAt)]))
        .get()
        .then((jobs) => jobs.map(syncJobAsUtc).toList());
  }

  Future<SyncJob?> latestUnclosedCoreSyncJob() {
    return (select(syncJobs)
          ..where((j) => j.coreStatus.isIn(syncJobActiveStatuses))
          ..orderBy([(j) => OrderingTerm.desc(j.updatedAt)])
          ..limit(1))
        .getSingleOrNull()
        .then((job) => job == null ? null : syncJobAsUtc(job));
  }

  Future<SyncJob?> syncJobForSession(String localSessionId) {
    return (select(syncJobs)
          ..where((j) => j.localSessionId.equals(localSessionId)))
        .getSingleOrNull()
        .then((job) => job == null ? null : syncJobAsUtc(job));
  }

  Stream<SyncJob?> watchLatestSyncJob() {
    return (select(syncJobs)
          ..orderBy([(j) => OrderingTerm.desc(j.updatedAt)])
          ..limit(1))
        .watchSingleOrNull()
        .map((job) => job == null ? null : syncJobAsUtc(job));
  }

  Future<void> updateSyncJob(
    int id, {
    String? coreStatus,
    String? rawStatus,
    int? attempts,
    Value<int?> remoteUploadId = const Value.absent(),
    Value<int?> remoteTripId = const Value.absent(),
    int? corePayloadSizeBytes,
    bool? coreMapAvailable,
    Value<DateTime?> nextRetryAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
  }) async {
    await (update(syncJobs)..where((j) => j.id.equals(id))).write(
      SyncJobsCompanion(
        coreStatus:
            coreStatus == null ? const Value.absent() : Value(coreStatus),
        rawStatus: rawStatus == null ? const Value.absent() : Value(rawStatus),
        attempts: attempts == null ? const Value.absent() : Value(attempts),
        remoteUploadId: remoteUploadId,
        remoteTripId: remoteTripId,
        corePayloadSizeBytes: corePayloadSizeBytes == null
            ? const Value.absent()
            : Value(corePayloadSizeBytes),
        coreMapAvailable: coreMapAvailable == null
            ? const Value.absent()
            : Value(coreMapAvailable),
        nextRetryAt: nextRetryAt.present
            ? Value(
                nextRetryAt.value == null ? null : asUtc(nextRetryAt.value!))
            : const Value.absent(),
        lastError: lastError,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}

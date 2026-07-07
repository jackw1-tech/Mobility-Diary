import 'dart:io';

import 'package:diary/features/acquisition/domain/sensor_matrix_blob.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'acquisition_local_database.g.dart';

class AcquisitionSessions extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
  IntColumn get remoteIngestionId => integer().nullable()();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class StateTransitions extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().references(AcquisitionSessions, #id)();
  TextColumn get fromState => text()();
  TextColumn get toState => text()();
  TextColumn get reason => text()();
  DateTimeColumn get timestamp => dateTime()();
  RealColumn get sigma => real().nullable()();
  RealColumn get speedMps => real().nullable()();
}

class GpsPoints extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().references(AcquisitionSessions, #id)();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  DateTimeColumn get timestamp => dateTime()();
  RealColumn get speedMps => real()();
  RealColumn get accuracyMeters => real().nullable()();
  BoolColumn get accepted => boolean().withDefault(const Constant(true))();
  TextColumn get rejectionReason => text().nullable()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
}

class SensorWindows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().references(AcquisitionSessions, #id)();
  DateTimeColumn get startTimestamp => dateTime()();
  DateTimeColumn get endTimestamp => dateTime()();
  IntColumn get sampleCount => integer()();
  IntColumn get frequencyHz => integer()();
  BlobColumn get matrixBlob => blob()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
}

/// Coda di sincronizzazione persistente: un job per sessione conclusa.
/// Disaccoppia lo stato del viaggio dallo stato di upload, cosi' lo STOP non
/// resta bloccato sulla rete e la sync riprende all'apertura app
/// (REPORT_STRATEGIA_INGESTION_ASINCRONA.md D5, SyncJob).
class SyncJobs extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get localSessionId =>
      text().references(AcquisitionSessions, #id)();
  IntColumn get remoteIngestionId => integer().nullable()();
  // Trip di dominio materializzato dal backend (null finche' il core non completa).
  IntColumn get remoteTripId => integer().nullable()();
  TextColumn get corePayloadSha256 => text().nullable()();
  IntColumn get corePayloadSizeBytes =>
      integer().withDefault(const Constant(0))();
  BoolColumn get coreMapAvailable =>
      boolean().withDefault(const Constant(false))();
  TextColumn get coreStatus =>
      text().withDefault(const Constant(syncJobPending))();
  TextColumn get rawStatus =>
      text().withDefault(const Constant(syncJobPending))();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
  DateTimeColumn get nextRetryAt => dateTime().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  List<Set<Column>> get uniqueKeys => [
        {localSessionId},
      ];
}

// Stati del SyncJob (vedi report). Tenuti come costanti per evitare enum nel DB.
const String syncJobPending = 'PENDING';
const String syncJobPackaging = 'PACKAGING';
const String syncJobUploading = 'UPLOADING';
const String syncJobWaitingProcessing = 'WAITING_PROCESSING';
const String syncJobCompleted = 'COMPLETED';
const String syncJobFailedRetryable = 'FAILED_RETRYABLE';
const String syncJobFailedFinal = 'FAILED_FINAL';

// Stati su cui il processore puo' ancora lavorare (claimable).
const List<String> syncJobActiveStatuses = [
  syncJobPending,
  syncJobPackaging,
  syncJobUploading,
  syncJobWaitingProcessing,
  syncJobFailedRetryable,
];

@DriftDatabase(
  tables: [
    AcquisitionSessions,
    StateTransitions,
    GpsPoints,
    SensorWindows,
    SyncJobs,
  ],
  daos: [AcquisitionDao],
)
class AcquisitionLocalDatabase extends _$AcquisitionLocalDatabase {
  AcquisitionLocalDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            // Tabella creata da zero con lo schema corrente (gia' completo).
            await m.createTable(syncJobs);
          } else {
            // Tabella preesistente: aggiungo le colonne mancanti in modo incrementale.
            if (from < 3) {
              await m.addColumn(syncJobs, syncJobs.coreStatus);
              await m.addColumn(syncJobs, syncJobs.rawStatus);
              await customStatement(
                "UPDATE sync_jobs SET core_status = status, raw_status = '$syncJobPending'",
              );
            }
            if (from < 4) {
              await m.addColumn(syncJobs, syncJobs.remoteTripId);
            }
            if (from < 5) {
              await m.addColumn(syncJobs, syncJobs.corePayloadSha256);
              await m.addColumn(syncJobs, syncJobs.corePayloadSizeBytes);
              await m.addColumn(syncJobs, syncJobs.coreMapAvailable);
            }
            if (from < 6) {
              await m.addColumn(
                acquisitionSessions,
                acquisitionSessions.remoteIngestionId,
              );
            }
          }
          if (from < 8) {
            // v7 aggiungeva matrix_blob con un semplice ADD COLUMN ma non
            // rimuoveva mai la vecchia matrix_json (NOT NULL, senza
            // default). Risultato: ogni INSERT tipizzato successivo (Drift
            // non conosce piu' quella colonna, quindi non la popola) fallisce
            // con un vincolo NOT NULL — su qualunque device che sia passato
            // di qui, anche quelli aggiornati PRIMA di questo fix e quindi
            // gia' fermi a schemaVersion 7 con la colonna orfana ancora
            // presente. Per questo il controllo e' dinamico (PRAGMA
            // table_info) invece di assumere `from == 6`: deve pulire sia chi
            // arriva da versioni precedenti sia chi e' gia' bloccato a 7.
            final columns =
                await customSelect("PRAGMA table_info('sensor_windows')").get();
            final hasLegacyMatrixJson =
                columns.any((row) => row.read<String>('name') == 'matrix_json');
            final hasMatrixBlob =
                columns.any((row) => row.read<String>('name') == 'matrix_blob');

            if (hasLegacyMatrixJson) {
              // SQLite non supporta DROP/ALTER COLUMN diretto: si ricostruisce
              // la tabella, il pattern standard per rimuovere una colonna.
              await customStatement(
                'ALTER TABLE sensor_windows RENAME TO sensor_windows_legacy_cleanup',
              );
              await m.createTable(sensorWindows);
              await customStatement('''
                INSERT INTO sensor_windows
                  (id, session_id, start_timestamp, end_timestamp,
                   sample_count, frequency_hz, matrix_blob, is_synced)
                SELECT id, session_id, start_timestamp, end_timestamp,
                       sample_count, frequency_hz,
                       ${hasMatrixBlob ? 'matrix_blob' : "X''"}, is_synced
                FROM sensor_windows_legacy_cleanup
              ''');
              if (!hasMatrixBlob) {
                await _migrateSensorWindowMatrixJsonToBlob(
                  legacyTable: 'sensor_windows_legacy_cleanup',
                );
              }
              await customStatement('DROP TABLE sensor_windows_legacy_cleanup');
            } else if (!hasMatrixBlob) {
              // Caso non atteso in pratica (v7 senza matrix_blob e senza
              // matrix_json) — rete di sicurezza.
              await customStatement(
                "ALTER TABLE sensor_windows ADD COLUMN matrix_blob BLOB NOT NULL DEFAULT X''",
              );
            }
          }
        },
      );

  Future<void> _migrateSensorWindowMatrixJsonToBlob({
    required String legacyTable,
  }) async {
    final rows = await customSelect(
      'SELECT id, matrix_json FROM $legacyTable',
    ).get();
    for (final row in rows) {
      final id = row.read<int>('id');
      final matrixJson = row.read<String>('matrix_json');
      final matrixBlob = encodeSensorMatrixJsonToBlob(matrixJson);
      await customUpdate(
        'UPDATE sensor_windows SET matrix_blob = ? WHERE id = ?',
        variables: [
          Variable<Uint8List>(matrixBlob),
          Variable<int>(id),
        ],
        updates: {sensorWindows},
      );
    }
  }
}

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
    int? remoteIngestionId,
  }) {
    return into(acquisitionSessions).insert(
      AcquisitionSessionsCompanion.insert(
        id: id,
        deviceId: deviceId,
        remoteIngestionId: Value(remoteIngestionId),
        startedAt: _asUtc(startedAt),
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
        endedAt: Value(_asUtc(endedAt)),
      ),
    );
  }

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
        timestamp: _asUtc(timestamp),
        sigma: Value(sigma),
        speedMps: Value(speedMps),
      ),
    );
  }

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
        timestamp: _asUtc(timestamp),
        speedMps: speedMps,
        accuracyMeters: Value(accuracyMeters),
        accepted: Value(accepted),
        rejectionReason: Value(rejectionReason),
      ),
    );
  }

  Future<int> insertSensorWindow({
    required String sessionId,
    required DateTime startTimestamp,
    required DateTime endTimestamp,
    required int sampleCount,
    required int frequencyHz,
    required Uint8List matrixBlob,
  }) {
    return into(sensorWindows).insert(
      SensorWindowsCompanion.insert(
        sessionId: sessionId,
        startTimestamp: _asUtc(startTimestamp),
        endTimestamp: _asUtc(endTimestamp),
        sampleCount: sampleCount,
        frequencyHz: frequencyHz,
        matrixBlob: matrixBlob,
      ),
    );
  }

  Future<AcquisitionSession?> findSession(String id) {
    return (select(acquisitionSessions)
          ..where((session) => session.id.equals(id)))
        .getSingleOrNull()
        .then((session) => session == null ? null : _sessionAsUtc(session));
  }

  Future<AcquisitionSession?> latestOpenSession() {
    return (select(acquisitionSessions)
          ..where((session) => session.endedAt.isNull())
          ..orderBy([
            (session) => OrderingTerm.desc(session.startedAt),
          ])
          ..limit(1))
        .getSingleOrNull()
        .then((session) => session == null ? null : _sessionAsUtc(session));
  }

  Future<AcquisitionSession?> findOpenSession(String id) {
    return (select(acquisitionSessions)
          ..where(
            (session) => session.id.equals(id) & session.endedAt.isNull(),
          ))
        .getSingleOrNull()
        .then((session) => session == null ? null : _sessionAsUtc(session));
  }

  Future<List<AcquisitionSession>> allSessions() {
    return (select(acquisitionSessions)
          ..orderBy([
            (session) => OrderingTerm.asc(session.startedAt),
          ]))
        .get()
        .then((sessions) => sessions.map(_sessionAsUtc).toList());
  }

  Future<List<StateTransition>> transitionsForSession(String sessionId) {
    return (select(stateTransitions)
          ..where((transition) => transition.sessionId.equals(sessionId))
          ..orderBy([
            (transition) => OrderingTerm.asc(transition.timestamp),
          ]))
        .get()
        .then((transitions) => transitions.map(_transitionAsUtc).toList());
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
            transition == null ? null : _transitionAsUtc(transition));
  }

  Future<int> countTransitionsForSession(String sessionId) {
    final count = stateTransitions.id.count();
    final query = selectOnly(stateTransitions)
      ..addColumns([count])
      ..where(stateTransitions.sessionId.equals(sessionId));

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<int> countGpsPointsForSession(String sessionId) {
    final count = gpsPoints.id.count();
    final query = selectOnly(gpsPoints)
      ..addColumns([count])
      ..where(gpsPoints.sessionId.equals(sessionId));

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<List<SensorWindow>> sensorWindowsForSession(String sessionId) {
    return (select(sensorWindows)
          ..where((window) => window.sessionId.equals(sessionId))
          ..orderBy([
            (window) => OrderingTerm.asc(window.startTimestamp),
          ]))
        .get()
        .then((windows) => windows.map(_sensorWindowAsUtc).toList());
  }

  /// Finestra sensori piu' recente della sessione: usata dalla classificazione
  /// live dell'assistente di percorso. Null se la sessione non ne ha ancora.
  Future<SensorWindow?> latestSensorWindow(String sessionId) {
    return (select(sensorWindows)
          ..where((window) => window.sessionId.equals(sessionId))
          ..orderBy([(window) => OrderingTerm.desc(window.startTimestamp)])
          ..limit(1))
        .getSingleOrNull()
        .then((window) => window == null ? null : _sensorWindowAsUtc(window));
  }

  Future<int> countSensorWindowsForSession(String sessionId) {
    final count = sensorWindows.id.count();
    final query = selectOnly(sensorWindows)
      ..addColumns([count])
      ..where(sensorWindows.sessionId.equals(sessionId));

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<List<GpsPoint>> gpsPointsForSession(String sessionId) {
    return (select(gpsPoints)
          ..where(
              (p) => p.sessionId.equals(sessionId) & p.accepted.equals(true))
          ..orderBy([(p) => OrderingTerm.asc(p.timestamp)]))
        .get()
        .then((points) => points.map(_gpsPointAsUtc).toList());
  }

  Future<GpsPoint?> latestGpsPointForSession(String sessionId) {
    return (select(gpsPoints)
          ..where(
              (p) => p.sessionId.equals(sessionId) & p.accepted.equals(true))
          ..orderBy([(p) => OrderingTerm.desc(p.timestamp)])
          ..limit(1))
        .getSingleOrNull()
        .then((point) => point == null ? null : _gpsPointAsUtc(point));
  }

  Future<List<GpsPoint>> unsyncedGpsPoints(String sessionId) {
    return (select(gpsPoints)
          ..where(
              (p) => p.sessionId.equals(sessionId) & p.isSynced.equals(false))
          ..orderBy([(p) => OrderingTerm.asc(p.timestamp)]))
        .get()
        .then((points) => points.map(_gpsPointAsUtc).toList());
  }

  Future<void> markGpsPointsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await (update(gpsPoints)..where((p) => p.id.isIn(ids)))
        .write(const GpsPointsCompanion(isSynced: Value(true)));
  }

  Future<List<SensorWindow>> unsyncedSensorWindows(String sessionId) {
    return (select(sensorWindows)
          ..where(
              (w) => w.sessionId.equals(sessionId) & w.isSynced.equals(false))
          ..orderBy([(w) => OrderingTerm.asc(w.startTimestamp)]))
        .get()
        .then((windows) => windows.map(_sensorWindowAsUtc).toList());
  }

  Future<void> markSensorWindowsSynced(List<int> ids) async {
    if (ids.isEmpty) return;
    await (update(sensorWindows)..where((w) => w.id.isIn(ids)))
        .write(const SensorWindowsCompanion(isSynced: Value(true)));
  }

  Future<int> countSessions() {
    final count = acquisitionSessions.id.count();
    final query = selectOnly(acquisitionSessions)..addColumns([count]);

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  /// Cancella del tutto una sessione ormai sincronizzata: dati grezzi (punti
  /// GPS, finestre sensori, transizioni), il SyncJob e la riga sessione
  /// stessa. Da chiamare solo dopo che il backend ha confermato core+raw
  /// COMPLETED: da quel momento il telefono non e' piu' l'unica copia, e lo
  /// stato di sync mostrato in UI (mappa disponibile, navigazione al viaggio
  /// appena sincronizzato) reagisce alla transizione a COMPLETED prima che
  /// questa riga sparisca, non dopo — cancellarla subito non perde nulla.
  /// L'ordine di cancellazione rispetta le foreign key verso
  /// [AcquisitionSessions] (le tabelle figlie prima, la sessione per ultima).
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

  /// Sessione locale che ha prodotto un dato Trip remoto, se ancora presente
  /// sul device (es. core riuscito ma raw fallito in modo definitivo: la riga
  /// resta per permettere un retry manuale anche se il Trip e' gia' visibile).
  Future<String?> localSessionIdForRemoteTrip(int tripId) async {
    final job = await (select(syncJobs)
          ..where((j) => j.remoteTripId.equals(tripId)))
        .getSingleOrNull();
    return job?.localSessionId;
  }

  // --- SyncJob ---------------------------------------------------------- //

  /// Crea il SyncJob per la sessione se non esiste gia' (idempotente: un re-stop
  /// non duplica il job). Ritorna il job esistente o quello appena creato.
  Future<SyncJob> createSyncJobIfAbsent(String localSessionId) async {
    final existing = await (select(syncJobs)
          ..where((j) => j.localSessionId.equals(localSessionId)))
        .getSingleOrNull();
    if (existing != null) {
      return _syncJobAsUtc(existing);
    }
    final session = await findSession(localSessionId);
    final now = DateTime.now().toUtc();
    await into(syncJobs).insert(
      SyncJobsCompanion.insert(
        localSessionId: localSessionId,
        remoteIngestionId: Value(session?.remoteIngestionId),
        createdAt: now,
        updatedAt: now,
      ),
    );
    final created = await (select(syncJobs)
          ..where((j) => j.localSessionId.equals(localSessionId)))
        .getSingle();
    return _syncJobAsUtc(created);
  }

  /// Job su cui il processore puo' lavorare ora: stato attivo e senza un
  /// next_retry_at futuro.
  Future<List<SyncJob>> claimableSyncJobs(DateTime now) {
    final nowUtc = _asUtc(now);
    return (select(syncJobs)
          ..where((j) =>
              (j.coreStatus.isIn(syncJobActiveStatuses) |
                  (j.coreStatus.equals(syncJobCompleted) &
                      j.rawStatus.isIn(syncJobActiveStatuses))) &
              (j.nextRetryAt.isNull() |
                  j.nextRetryAt.isSmallerOrEqualValue(nowUtc)))
          ..orderBy([(j) => OrderingTerm.asc(j.createdAt)]))
        .get()
        .then((jobs) => jobs.map(_syncJobAsUtc).toList());
  }

  Future<SyncJob?> latestUnclosedCoreSyncJob() {
    return (select(syncJobs)
          ..where((j) => j.coreStatus.isIn(syncJobActiveStatuses))
          ..orderBy([(j) => OrderingTerm.desc(j.updatedAt)])
          ..limit(1))
        .getSingleOrNull()
        .then((job) => job == null ? null : _syncJobAsUtc(job));
  }

  Future<SyncJob?> syncJobForSession(String localSessionId) {
    return (select(syncJobs)
          ..where((j) => j.localSessionId.equals(localSessionId)))
        .getSingleOrNull()
        .then((job) => job == null ? null : _syncJobAsUtc(job));
  }

  Stream<SyncJob?> watchSyncJobForSession(String localSessionId) {
    return (select(syncJobs)
          ..where((j) => j.localSessionId.equals(localSessionId)))
        .watchSingleOrNull()
        .map((job) => job == null ? null : _syncJobAsUtc(job));
  }

  Stream<SyncJob?> watchLatestSyncJob() {
    return (select(syncJobs)
          ..orderBy([(j) => OrderingTerm.desc(j.updatedAt)])
          ..limit(1))
        .watchSingleOrNull()
        .map((job) => job == null ? null : _syncJobAsUtc(job));
  }

  Future<void> updateSyncJob(
    int id, {
    String? coreStatus,
    String? rawStatus,
    int? attempts,
    Value<int?> remoteIngestionId = const Value.absent(),
    Value<int?> remoteTripId = const Value.absent(),
    Value<String?> corePayloadSha256 = const Value.absent(),
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
        remoteIngestionId: remoteIngestionId,
        remoteTripId: remoteTripId,
        corePayloadSha256: corePayloadSha256,
        corePayloadSizeBytes: corePayloadSizeBytes == null
            ? const Value.absent()
            : Value(corePayloadSizeBytes),
        coreMapAvailable: coreMapAvailable == null
            ? const Value.absent()
            : Value(coreMapAvailable),
        nextRetryAt: nextRetryAt.present
            ? Value(
                nextRetryAt.value == null ? null : _asUtc(nextRetryAt.value!))
            : const Value.absent(),
        lastError: lastError,
        updatedAt: Value(DateTime.now().toUtc()),
      ),
    );
  }
}

DateTime _asUtc(DateTime value) {
  return value.isUtc ? value : value.toUtc();
}

AcquisitionSession _sessionAsUtc(AcquisitionSession session) {
  final endedAt = session.endedAt;
  if (endedAt == null) {
    return session.copyWith(startedAt: _asUtc(session.startedAt));
  }
  return session.copyWith(
    startedAt: _asUtc(session.startedAt),
    endedAt: Value(_asUtc(endedAt)),
  );
}

StateTransition _transitionAsUtc(StateTransition transition) {
  return transition.copyWith(timestamp: _asUtc(transition.timestamp));
}

GpsPoint _gpsPointAsUtc(GpsPoint point) {
  return point.copyWith(timestamp: _asUtc(point.timestamp));
}

SensorWindow _sensorWindowAsUtc(SensorWindow window) {
  return window.copyWith(
    startTimestamp: _asUtc(window.startTimestamp),
    endTimestamp: _asUtc(window.endTimestamp),
  );
}

SyncJob _syncJobAsUtc(SyncJob job) {
  return job.copyWith(
    createdAt: _asUtc(job.createdAt),
    updatedAt: _asUtc(job.updatedAt),
    nextRetryAt: Value(
      job.nextRetryAt == null ? null : _asUtc(job.nextRetryAt!),
    ),
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'mobility_diary.sqlite'));
    return NativeDatabase(file);
  });
}

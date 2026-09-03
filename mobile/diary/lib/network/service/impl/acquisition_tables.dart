import 'package:drift/drift.dart';

/// Schema locale dell'acquisizione: una sessione con i suoi dati grezzi (GPS,
/// transizioni FSM, finestre sensori) e la coda di sincronizzazione.

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
}

class SensorWindows extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get sessionId => text().references(AcquisitionSessions, #id)();
  DateTimeColumn get startTimestamp => dateTime()();
  DateTimeColumn get endTimestamp => dateTime()();
  IntColumn get sampleCount => integer()();
  IntColumn get frequencyHz => integer()();
  TextColumn get matrixJson => text()();
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

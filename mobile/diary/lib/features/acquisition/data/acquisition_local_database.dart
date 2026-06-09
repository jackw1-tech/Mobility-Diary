import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'acquisition_local_database.g.dart';

class AcquisitionSessions extends Table {
  TextColumn get id => text()();
  TextColumn get deviceId => text()();
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
  TextColumn get matrixJson => text()();
  BoolColumn get isSynced => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(
  tables: [
    AcquisitionSessions,
    StateTransitions,
    GpsPoints,
    SensorWindows,
  ],
  daos: [AcquisitionDao],
)
class AcquisitionLocalDatabase extends _$AcquisitionLocalDatabase {
  AcquisitionLocalDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 1;
}

@DriftAccessor(
  tables: [
    AcquisitionSessions,
    StateTransitions,
    GpsPoints,
    SensorWindows,
  ],
)
class AcquisitionDao extends DatabaseAccessor<AcquisitionLocalDatabase>
    with _$AcquisitionDaoMixin {
  AcquisitionDao(super.db);

  Future<void> createSession({
    required String id,
    required String deviceId,
    required DateTime startedAt,
  }) {
    return into(acquisitionSessions).insert(
      AcquisitionSessionsCompanion.insert(
        id: id,
        deviceId: deviceId,
        startedAt: startedAt,
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
        endedAt: Value(endedAt),
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
        timestamp: timestamp,
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
        timestamp: timestamp,
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
    required String matrixJson,
  }) {
    return into(sensorWindows).insert(
      SensorWindowsCompanion.insert(
        sessionId: sessionId,
        startTimestamp: startTimestamp,
        endTimestamp: endTimestamp,
        sampleCount: sampleCount,
        frequencyHz: frequencyHz,
        matrixJson: matrixJson,
      ),
    );
  }

  Future<AcquisitionSession?> findSession(String id) {
    return (select(acquisitionSessions)
          ..where((session) => session.id.equals(id)))
        .getSingleOrNull();
  }

  Future<List<AcquisitionSession>> allSessions() {
    return (select(acquisitionSessions)
          ..orderBy([
            (session) => OrderingTerm.asc(session.startedAt),
          ]))
        .get();
  }

  Future<List<StateTransition>> transitionsForSession(String sessionId) {
    return (select(stateTransitions)
          ..where((transition) => transition.sessionId.equals(sessionId))
          ..orderBy([
            (transition) => OrderingTerm.asc(transition.timestamp),
          ]))
        .get();
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
        .get();
  }

  Future<int> countSensorWindowsForSession(String sessionId) {
    final count = sensorWindows.id.count();
    final query = selectOnly(sensorWindows)
      ..addColumns([count])
      ..where(sensorWindows.sessionId.equals(sessionId));

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }

  Future<int> countSessions() {
    final count = acquisitionSessions.id.count();
    final query = selectOnly(acquisitionSessions)..addColumns([count]);

    return query.map((row) => row.read(count) ?? 0).getSingle();
  }
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'mobility_diary.sqlite'));
    return NativeDatabase(file);
  });
}

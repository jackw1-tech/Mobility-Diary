import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

/// Schema v8: matrix_blob BLOB e le colonne is_synced, entrambe eliminate da
/// v9. Viene creato nell'hook `setup`, cioe' prima che Drift apra il database:
/// altrimenti Drift eseguirebbe `onCreate` con lo schema nuovo e la migrazione
/// non verrebbe mai esercitata.
const List<String> _v8Schema = [
  '''
  CREATE TABLE acquisition_sessions (
    id TEXT NOT NULL PRIMARY KEY,
    device_id TEXT NOT NULL,
    remote_ingestion_id INTEGER NULL,
    started_at INTEGER NOT NULL,
    ended_at INTEGER NULL
  )''',
  '''
  CREATE TABLE gps_points (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES acquisition_sessions (id),
    latitude REAL NOT NULL,
    longitude REAL NOT NULL,
    timestamp INTEGER NOT NULL,
    speed_mps REAL NOT NULL,
    accuracy_meters REAL NULL,
    accepted INTEGER NOT NULL DEFAULT 1,
    rejection_reason TEXT NULL,
    is_synced INTEGER NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE sensor_windows (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES acquisition_sessions (id),
    start_timestamp INTEGER NOT NULL,
    end_timestamp INTEGER NOT NULL,
    sample_count INTEGER NOT NULL,
    frequency_hz INTEGER NOT NULL,
    matrix_blob BLOB NOT NULL,
    is_synced INTEGER NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE state_transitions (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    session_id TEXT NOT NULL REFERENCES acquisition_sessions (id),
    from_state TEXT NOT NULL,
    to_state TEXT NOT NULL,
    reason TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    sigma REAL NOT NULL DEFAULT 0,
    speed_mps REAL NOT NULL DEFAULT 0
  )''',
  '''
  CREATE TABLE sync_jobs (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    local_session_id TEXT NOT NULL UNIQUE REFERENCES acquisition_sessions (id),
    remote_ingestion_id INTEGER NULL,
    remote_trip_id INTEGER NULL,
    core_payload_size_bytes INTEGER NOT NULL DEFAULT 0,
    core_map_available INTEGER NOT NULL DEFAULT 0,
    core_status TEXT NOT NULL DEFAULT 'PENDING',
    raw_status TEXT NOT NULL DEFAULT 'PENDING',
    attempts INTEGER NOT NULL DEFAULT 0,
    next_retry_at INTEGER NULL,
    last_error TEXT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL
  )''',
];

AcquisitionLocalDatabase openFromV8({List<String> seed = const []}) {
  return AcquisitionLocalDatabase(
    NativeDatabase.memory(
      setup: (raw) {
        for (final statement in _v8Schema) {
          raw.execute(statement);
        }
        for (final statement in seed) {
          raw.execute(statement);
        }
        raw.execute('PRAGMA user_version = 8');
      },
    ),
  );
}

Future<Set<String>> columnsOf(
  AcquisitionLocalDatabase db,
  String table,
) async {
  final rows = await db.customSelect("PRAGMA table_info('$table')").get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  test('v9 sostituisce matrix_blob con matrix_json su sensor_windows',
      () async {
    final db = openFromV8();

    final columns = await columnsOf(db, 'sensor_windows');

    expect(columns, contains('matrix_json'));
    expect(columns, isNot(contains('matrix_blob')));
    await db.close();
  });

  test('v9 elimina la colonna morta is_synced da entrambe le tabelle',
      () async {
    final db = openFromV8();

    expect(await columnsOf(db, 'sensor_windows'), isNot(contains('is_synced')));
    expect(await columnsOf(db, 'gps_points'), isNot(contains('is_synced')));
    await db.close();
  });

  test('dopo la migrazione si inseriscono e rileggono finestre JSON', () async {
    final db = openFromV8();
    final dao = db.acquisitionDao;
    await dao.createSession(
      id: 'session-1',
      deviceId: 'device-1',
      startedAt: DateTime.utc(2026, 9, 2, 10),
    );

    await dao.insertSensorWindow(
      sessionId: 'session-1',
      startTimestamp: DateTime.utc(2026, 9, 2, 10),
      endTimestamp: DateTime.utc(2026, 9, 2, 10, 0, 5),
      sampleCount: 1,
      frequencyHz: 100,
      matrixJson: '[[1,2,3,4,5,6]]',
    );

    final windows = await dao.sensorWindowsForSession('session-1');
    expect(windows.single.matrixJson, '[[1,2,3,4,5,6]]');
    await db.close();
  });

  test('i dati non-sensori sopravvivono alla migrazione', () async {
    final db = openFromV8(seed: [
      "INSERT INTO acquisition_sessions (id, device_id, started_at) "
          "VALUES ('session-1', 'device-1', 0)",
      "INSERT INTO gps_points (session_id, latitude, longitude, timestamp, "
          "speed_mps) VALUES ('session-1', 45.46, 9.19, 0, 1.0)",
    ]);

    expect(await db.acquisitionDao.countGpsPointsForSession('session-1'), 1);
    expect(await db.acquisitionDao.findSession('session-1'), isNot(null));
    await db.close();
  });
}

import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Schema minimo di un vecchio db locale (versione 8), usato solo per
// simulare un telefono che apre l'app dopo un bump di schemaVersion.
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

Future<Set<String>> columnsOf(AcquisitionLocalDatabase db, String table) async {
  final rows = await db.customSelect("PRAGMA table_info('$table')").get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void main() {
  // App non ancora distribuita: l'unico contratto che conta e' che aprire un
  // db locale fermo a una versione vecchia porti sempre allo schema
  // corrente, ricreato da zero (vedi il commento su
  // AcquisitionLocalDatabase.migration).

  test('un db fermo a una versione vecchia arriva allo schema corrente',
      () async {
    final db = openFromV8();

    expect(await columnsOf(db, 'sensor_windows'), contains('matrix_json'));
    expect(
      await columnsOf(db, 'gps_points'),
      isNot(anyOf(contains('accepted'), contains('rejection_reason'), contains('is_synced'))),
    );
    expect(await columnsOf(db, 'state_transitions'), isNot(contains('reason')));
    expect(
      await columnsOf(db, 'acquisition_sessions'),
      allOf(contains('remote_upload_id'), isNot(contains('remote_ingestion_id'))),
    );
    await db.close();
  });

  test('la velocita GPS e nullable sullo schema corrente', () async {
    final db = openFromV8();

    final columns = await db.customSelect("PRAGMA table_info('gps_points')").get();
    final speedColumn = columns.singleWhere(
      (row) => row.read<String>('name') == 'speed_mps',
    );

    expect(speedColumn.read<int>('notnull'), 0);
    await db.close();
  });

  test('i dati del vecchio schema non sopravvivono (ricreazione distruttiva)',
      () async {
    final db = openFromV8(
      seed: [
        "INSERT INTO acquisition_sessions (id, device_id, started_at) "
            "VALUES ('session-1', 'device-1', 0)",
        "INSERT INTO gps_points (session_id, latitude, longitude, timestamp, "
            "speed_mps) VALUES ('session-1', 45.46, 9.19, 0, 1.0)",
      ],
    );

    expect(await db.acquisitionDao.findSession('session-1'), isNull);
    expect(await db.acquisitionDao.countGpsPointsForSession('session-1'), 0);
    await db.close();
  });

  test('dopo la migrazione si puo di nuovo scrivere e rileggere normalmente',
      () async {
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
}

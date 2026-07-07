import 'dart:io';
import 'dart:typed_data';

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/sensor_matrix_blob.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('migrates v6 sensor matrix JSON to matrix blob', () async {
    final tempDir = await Directory.systemTemp.createTemp('acq_db_migration_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final dbFile = File('${tempDir.path}/acquisition.sqlite');
    final database = AcquisitionLocalDatabase(
      NativeDatabase(
        dbFile,
        setup: (raw) {
          raw.execute('''
            CREATE TABLE acquisition_sessions (
              id TEXT NOT NULL PRIMARY KEY,
              device_id TEXT NOT NULL,
              remote_ingestion_id INTEGER NULL,
              started_at INTEGER NOT NULL,
              ended_at INTEGER NULL
            );
          ''');
          raw.execute('''
            CREATE TABLE sensor_windows (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL REFERENCES acquisition_sessions (id),
              start_timestamp INTEGER NOT NULL,
              end_timestamp INTEGER NOT NULL,
              sample_count INTEGER NOT NULL,
              frequency_hz INTEGER NOT NULL,
              matrix_json TEXT NOT NULL,
              is_synced INTEGER NOT NULL DEFAULT 0 CHECK ("is_synced" IN (0, 1))
            );
          ''');
          raw.execute(
            "INSERT INTO acquisition_sessions "
            "(id, device_id, started_at) VALUES ('s1', 'dev', 0)",
          );
          raw.execute(
            "INSERT INTO sensor_windows "
            "(session_id, start_timestamp, end_timestamp, sample_count, "
            "frequency_hz, matrix_json) VALUES "
            "('s1', 0, 5000000, 1, 100, "
            "'[[0.1,0.2,9.7,0.01,0.02,0.03,1.0,2.0,3.0]]')",
          );
          raw.execute('PRAGMA user_version = 6');
        },
      ),
    );
    addTearDown(database.close);

    final windows = await database.acquisitionDao.sensorWindowsForSession('s1');

    expect(windows, hasLength(1));
    expect(windows.single.matrixBlob.lengthInBytes, 1 * 6 * 4);
    final matrix = decodeSensorMatrixBlob(
      windows.single.matrixBlob,
      sampleCount: windows.single.sampleCount,
    );
    expect(matrix.single, [
      closeTo(0.1, 0.000001),
      closeTo(0.2, 0.000001),
      closeTo(9.7, 0.000001),
      closeTo(0.01, 0.000001),
      closeTo(0.02, 0.000001),
      closeTo(0.03, 0.000001),
    ]);

    // Regressione: la colonna legacy matrix_json (NOT NULL, senza default)
    // deve essere sparita dalla tabella fisica dopo la migrazione — altrimenti
    // ogni nuova finestra sensore registrata su un device aggiornato in-place
    // (non installazione pulita) fallisce con un vincolo NOT NULL, perche'
    // l'insert tipizzato di Drift non conosce piu' quella colonna e quindi
    // non la popola.
    await database.acquisitionDao.insertSensorWindow(
      sessionId: 's1',
      startTimestamp: DateTime.utc(2026, 1, 1),
      endTimestamp: DateTime.utc(2026, 1, 1, 0, 0, 5),
      sampleCount: 1,
      frequencyHz: 100,
      matrixBlob: Uint8List(24),
    );
    final afterInsert =
        await database.acquisitionDao.sensorWindowsForSession('s1');
    expect(afterInsert, hasLength(2));
  });

  test(
      'cleans up devices already stuck at v7 (broken migration already ran '
      'once, matrix_json still orphaned, matrix_blob already populated)',
      () async {
    final tempDir = await Directory.systemTemp.createTemp('acq_db_migration_');
    addTearDown(() async {
      if (await tempDir.exists()) {
        await tempDir.delete(recursive: true);
      }
    });
    final dbFile = File('${tempDir.path}/acquisition.sqlite');
    final database = AcquisitionLocalDatabase(
      NativeDatabase(
        dbFile,
        setup: (raw) {
          raw.execute('''
            CREATE TABLE acquisition_sessions (
              id TEXT NOT NULL PRIMARY KEY,
              device_id TEXT NOT NULL,
              remote_ingestion_id INTEGER NULL,
              started_at INTEGER NOT NULL,
              ended_at INTEGER NULL
            );
          ''');
          // Stato esatto lasciato dalla PRIMA migrazione (v6->v7, rotta): la
          // colonna legacy e' ancora li', matrix_blob esiste ed e' gia'
          // stata popolata correttamente per le righe preesistenti.
          raw.execute('''
            CREATE TABLE sensor_windows (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              session_id TEXT NOT NULL REFERENCES acquisition_sessions (id),
              start_timestamp INTEGER NOT NULL,
              end_timestamp INTEGER NOT NULL,
              sample_count INTEGER NOT NULL,
              frequency_hz INTEGER NOT NULL,
              matrix_json TEXT NOT NULL,
              matrix_blob BLOB NOT NULL DEFAULT X'',
              is_synced INTEGER NOT NULL DEFAULT 0 CHECK ("is_synced" IN (0, 1))
            );
          ''');
          raw.execute(
            "INSERT INTO acquisition_sessions "
            "(id, device_id, started_at) VALUES ('s1', 'dev', 0)",
          );
          final legacyBlob = encodeSensorMatrixJsonToBlob(
            '[[0.1,0.2,9.7,0.01,0.02,0.03,1.0,2.0,3.0]]',
          );
          raw.execute(
            "INSERT INTO sensor_windows "
            "(session_id, start_timestamp, end_timestamp, sample_count, "
            "frequency_hz, matrix_json, matrix_blob) VALUES "
            "('s1', 0, 5000000, 1, 100, "
            "'[[0.1,0.2,9.7,0.01,0.02,0.03,1.0,2.0,3.0]]', ?)",
            [legacyBlob],
          );
          raw.execute('PRAGMA user_version = 7');
        },
      ),
    );
    addTearDown(database.close);

    // La riga preesistente deve restare intatta (nessuna riconversione
    // spuria: matrix_blob era gia' corretto).
    final existing =
        await database.acquisitionDao.sensorWindowsForSession('s1');
    expect(existing, hasLength(1));
    expect(existing.single.matrixBlob.lengthInBytes, 1 * 6 * 4);

    // Il punto cruciale: un device gia' fermo a v7 deve comunque poter
    // registrare nuove finestre dopo l'aggiornamento a questo fix.
    await database.acquisitionDao.insertSensorWindow(
      sessionId: 's1',
      startTimestamp: DateTime.utc(2026, 1, 1),
      endTimestamp: DateTime.utc(2026, 1, 1, 0, 0, 5),
      sampleCount: 1,
      frequencyHz: 100,
      matrixBlob: Uint8List(24),
    );
    final afterInsert =
        await database.acquisitionDao.sensorWindowsForSession('s1');
    expect(afterInsert, hasLength(2));
  });
}

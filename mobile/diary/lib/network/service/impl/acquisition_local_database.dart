import 'dart:io';

import 'package:diary/model/entities/acquisition/sensor_matrix_blob.dart';
import 'package:diary/network/service/impl/acquisition_dao.dart';
import 'package:diary/network/service/impl/acquisition_tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Chi importa il database vuole quasi sempre anche il DAO, le tabelle e le
// costanti di stato: riesportarli evita che ogni chiamante debba conoscere la
// suddivisione interna di questo modulo.
export 'package:diary/network/service/impl/acquisition_dao.dart';
export 'package:diary/network/service/impl/acquisition_tables.dart';

part 'acquisition_local_database.g.dart';

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

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'mobility_diary.sqlite'));
    return NativeDatabase(file);
  });
}

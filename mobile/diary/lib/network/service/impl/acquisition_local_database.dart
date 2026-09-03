import 'dart:io';

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
  int get schemaVersion => 10;

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
                acquisitionSessions.remoteUploadId,
              );
            }
          }
          if (from < 9) {
            // Le matrici sensori tornano a essere JSON (colonna matrix_json
            // TEXT). Le finestre gia' su disco appartengono al formato binario
            // precedente e non sono convertibili senza tenere in vita il codec
            // binario: la tabella viene ricreata vuota. Si perdono solo le
            // finestre non ancora sincronizzate del viaggio in corso; sessioni,
            // GPS, transizioni e SyncJob restano intatti.
            await customStatement('DROP TABLE IF EXISTS sensor_windows');
            await customStatement(
              'DROP TABLE IF EXISTS sensor_windows_legacy_cleanup',
            );
            await m.createTable(sensorWindows);

            // `is_synced` non e' mai stata letta ne' scritta: lo stato di
            // sincronizzazione vive in sync_jobs (per sessione) e a fine
            // upload la sessione viene purgata in blocco. La colonna su
            // sensor_windows sparisce con la ricreazione qui sopra; su
            // gps_points va tolta esplicitamente per non lasciare una colonna
            // orfana come era gia' successo con matrix_json.
            final gpsColumns =
                await customSelect("PRAGMA table_info('gps_points')").get();
            final hasLegacyIsSynced = gpsColumns
                .any((row) => row.read<String>('name') == 'is_synced');
            if (hasLegacyIsSynced) {
              await customStatement(
                'ALTER TABLE gps_points DROP COLUMN is_synced',
              );
            }
          }
          if (from < 10) {
            // "ingestion" e' diventata "upload" in tutto il progetto: qui si
            // adegua il nome della colonna, senza toccarne il contenuto.
            for (final table in ['acquisition_sessions', 'sync_jobs']) {
              final columns =
                  await customSelect("PRAGMA table_info('$table')").get();
              final hasLegacyName = columns.any(
                (row) => row.read<String>('name') == 'remote_ingestion_id',
              );
              if (hasLegacyName) {
                await customStatement(
                  'ALTER TABLE $table '
                  'RENAME COLUMN remote_ingestion_id TO remote_upload_id',
                );
              }
            }
          }
        },
      );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'mobility_diary.sqlite'));
    return NativeDatabase(file);
  });
}

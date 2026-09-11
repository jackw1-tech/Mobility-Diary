import 'dart:io';

import 'package:diary/network/service/impl/acquisition_dao.dart';
import 'package:diary/network/service/impl/acquisition_tables.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (m, from, to) async {
      for (final table in allTables) {
        await customStatement('DROP TABLE IF EXISTS ${table.actualTableName}');
      }
      await m.createAll();
    },
  );
}

LazyDatabase _openConnection() {
  return LazyDatabase(() async {
    final directory = await getApplicationDocumentsDirectory();
    final file = File(p.join(directory.path, 'mobility_diary.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}

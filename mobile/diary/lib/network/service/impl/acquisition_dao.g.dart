// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acquisition_dao.dart';

// ignore_for_file: type=lint
mixin _$AcquisitionDaoMixin on DatabaseAccessor<AcquisitionLocalDatabase> {
  $AcquisitionSessionsTable get acquisitionSessions =>
      attachedDatabase.acquisitionSessions;
  $StateTransitionsTable get stateTransitions =>
      attachedDatabase.stateTransitions;
  $GpsPointsTable get gpsPoints => attachedDatabase.gpsPoints;
  $SensorWindowsTable get sensorWindows => attachedDatabase.sensorWindows;
  $SyncJobsTable get syncJobs => attachedDatabase.syncJobs;
  AcquisitionDaoManager get managers => AcquisitionDaoManager(this);
}

class AcquisitionDaoManager {
  final _$AcquisitionDaoMixin _db;
  AcquisitionDaoManager(this._db);
  $$AcquisitionSessionsTableTableManager get acquisitionSessions =>
      $$AcquisitionSessionsTableTableManager(
          _db.attachedDatabase, _db.acquisitionSessions);
  $$StateTransitionsTableTableManager get stateTransitions =>
      $$StateTransitionsTableTableManager(
          _db.attachedDatabase, _db.stateTransitions);
  $$GpsPointsTableTableManager get gpsPoints =>
      $$GpsPointsTableTableManager(_db.attachedDatabase, _db.gpsPoints);
  $$SensorWindowsTableTableManager get sensorWindows =>
      $$SensorWindowsTableTableManager(_db.attachedDatabase, _db.sensorWindows);
  $$SyncJobsTableTableManager get syncJobs =>
      $$SyncJobsTableTableManager(_db.attachedDatabase, _db.syncJobs);
}

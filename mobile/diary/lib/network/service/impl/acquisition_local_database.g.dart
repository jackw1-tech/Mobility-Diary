// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'acquisition_local_database.dart';

// ignore_for_file: type=lint
class $AcquisitionSessionsTable extends AcquisitionSessions
    with TableInfo<$AcquisitionSessionsTable, AcquisitionSession> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AcquisitionSessionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _remoteUploadIdMeta = const VerificationMeta(
    'remoteUploadId',
  );
  @override
  late final GeneratedColumn<int> remoteUploadId = GeneratedColumn<int>(
    'remote_upload_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _startedAtMeta = const VerificationMeta(
    'startedAt',
  );
  @override
  late final GeneratedColumn<DateTime> startedAt = GeneratedColumn<DateTime>(
    'started_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _endedAtMeta = const VerificationMeta(
    'endedAt',
  );
  @override
  late final GeneratedColumn<DateTime> endedAt = GeneratedColumn<DateTime>(
    'ended_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deviceId,
    remoteUploadId,
    startedAt,
    endedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'acquisition_sessions';
  @override
  VerificationContext validateIntegrity(
    Insertable<AcquisitionSession> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deviceIdMeta);
    }
    if (data.containsKey('remote_upload_id')) {
      context.handle(
        _remoteUploadIdMeta,
        remoteUploadId.isAcceptableOrUnknown(
          data['remote_upload_id']!,
          _remoteUploadIdMeta,
        ),
      );
    }
    if (data.containsKey('started_at')) {
      context.handle(
        _startedAtMeta,
        startedAt.isAcceptableOrUnknown(data['started_at']!, _startedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_startedAtMeta);
    }
    if (data.containsKey('ended_at')) {
      context.handle(
        _endedAtMeta,
        endedAt.isAcceptableOrUnknown(data['ended_at']!, _endedAtMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  AcquisitionSession map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AcquisitionSession(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      )!,
      remoteUploadId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_upload_id'],
      ),
      startedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}started_at'],
      )!,
      endedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}ended_at'],
      ),
    );
  }

  @override
  $AcquisitionSessionsTable createAlias(String alias) {
    return $AcquisitionSessionsTable(attachedDatabase, alias);
  }
}

class AcquisitionSession extends DataClass
    implements Insertable<AcquisitionSession> {
  final String id;
  final String deviceId;
  final int? remoteUploadId;
  final DateTime startedAt;
  final DateTime? endedAt;
  const AcquisitionSession({
    required this.id,
    required this.deviceId,
    this.remoteUploadId,
    required this.startedAt,
    this.endedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['device_id'] = Variable<String>(deviceId);
    if (!nullToAbsent || remoteUploadId != null) {
      map['remote_upload_id'] = Variable<int>(remoteUploadId);
    }
    map['started_at'] = Variable<DateTime>(startedAt);
    if (!nullToAbsent || endedAt != null) {
      map['ended_at'] = Variable<DateTime>(endedAt);
    }
    return map;
  }

  AcquisitionSessionsCompanion toCompanion(bool nullToAbsent) {
    return AcquisitionSessionsCompanion(
      id: Value(id),
      deviceId: Value(deviceId),
      remoteUploadId: remoteUploadId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteUploadId),
      startedAt: Value(startedAt),
      endedAt: endedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(endedAt),
    );
  }

  factory AcquisitionSession.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AcquisitionSession(
      id: serializer.fromJson<String>(json['id']),
      deviceId: serializer.fromJson<String>(json['deviceId']),
      remoteUploadId: serializer.fromJson<int?>(json['remoteUploadId']),
      startedAt: serializer.fromJson<DateTime>(json['startedAt']),
      endedAt: serializer.fromJson<DateTime?>(json['endedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deviceId': serializer.toJson<String>(deviceId),
      'remoteUploadId': serializer.toJson<int?>(remoteUploadId),
      'startedAt': serializer.toJson<DateTime>(startedAt),
      'endedAt': serializer.toJson<DateTime?>(endedAt),
    };
  }

  AcquisitionSession copyWith({
    String? id,
    String? deviceId,
    Value<int?> remoteUploadId = const Value.absent(),
    DateTime? startedAt,
    Value<DateTime?> endedAt = const Value.absent(),
  }) => AcquisitionSession(
    id: id ?? this.id,
    deviceId: deviceId ?? this.deviceId,
    remoteUploadId: remoteUploadId.present
        ? remoteUploadId.value
        : this.remoteUploadId,
    startedAt: startedAt ?? this.startedAt,
    endedAt: endedAt.present ? endedAt.value : this.endedAt,
  );
  AcquisitionSession copyWithCompanion(AcquisitionSessionsCompanion data) {
    return AcquisitionSession(
      id: data.id.present ? data.id.value : this.id,
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      remoteUploadId: data.remoteUploadId.present
          ? data.remoteUploadId.value
          : this.remoteUploadId,
      startedAt: data.startedAt.present ? data.startedAt.value : this.startedAt,
      endedAt: data.endedAt.present ? data.endedAt.value : this.endedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AcquisitionSession(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('remoteUploadId: $remoteUploadId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, deviceId, remoteUploadId, startedAt, endedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AcquisitionSession &&
          other.id == this.id &&
          other.deviceId == this.deviceId &&
          other.remoteUploadId == this.remoteUploadId &&
          other.startedAt == this.startedAt &&
          other.endedAt == this.endedAt);
}

class AcquisitionSessionsCompanion extends UpdateCompanion<AcquisitionSession> {
  final Value<String> id;
  final Value<String> deviceId;
  final Value<int?> remoteUploadId;
  final Value<DateTime> startedAt;
  final Value<DateTime?> endedAt;
  final Value<int> rowid;
  const AcquisitionSessionsCompanion({
    this.id = const Value.absent(),
    this.deviceId = const Value.absent(),
    this.remoteUploadId = const Value.absent(),
    this.startedAt = const Value.absent(),
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AcquisitionSessionsCompanion.insert({
    required String id,
    required String deviceId,
    this.remoteUploadId = const Value.absent(),
    required DateTime startedAt,
    this.endedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deviceId = Value(deviceId),
       startedAt = Value(startedAt);
  static Insertable<AcquisitionSession> custom({
    Expression<String>? id,
    Expression<String>? deviceId,
    Expression<int>? remoteUploadId,
    Expression<DateTime>? startedAt,
    Expression<DateTime>? endedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deviceId != null) 'device_id': deviceId,
      if (remoteUploadId != null) 'remote_upload_id': remoteUploadId,
      if (startedAt != null) 'started_at': startedAt,
      if (endedAt != null) 'ended_at': endedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AcquisitionSessionsCompanion copyWith({
    Value<String>? id,
    Value<String>? deviceId,
    Value<int?>? remoteUploadId,
    Value<DateTime>? startedAt,
    Value<DateTime?>? endedAt,
    Value<int>? rowid,
  }) {
    return AcquisitionSessionsCompanion(
      id: id ?? this.id,
      deviceId: deviceId ?? this.deviceId,
      remoteUploadId: remoteUploadId ?? this.remoteUploadId,
      startedAt: startedAt ?? this.startedAt,
      endedAt: endedAt ?? this.endedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (remoteUploadId.present) {
      map['remote_upload_id'] = Variable<int>(remoteUploadId.value);
    }
    if (startedAt.present) {
      map['started_at'] = Variable<DateTime>(startedAt.value);
    }
    if (endedAt.present) {
      map['ended_at'] = Variable<DateTime>(endedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AcquisitionSessionsCompanion(')
          ..write('id: $id, ')
          ..write('deviceId: $deviceId, ')
          ..write('remoteUploadId: $remoteUploadId, ')
          ..write('startedAt: $startedAt, ')
          ..write('endedAt: $endedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $StateTransitionsTable extends StateTransitions
    with TableInfo<$StateTransitionsTable, StateTransition> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $StateTransitionsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES acquisition_sessions (id)',
    ),
  );
  static const VerificationMeta _fromStateMeta = const VerificationMeta(
    'fromState',
  );
  @override
  late final GeneratedColumn<String> fromState = GeneratedColumn<String>(
    'from_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _toStateMeta = const VerificationMeta(
    'toState',
  );
  @override
  late final GeneratedColumn<String> toState = GeneratedColumn<String>(
    'to_state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sigmaMeta = const VerificationMeta('sigma');
  @override
  late final GeneratedColumn<double> sigma = GeneratedColumn<double>(
    'sigma',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _speedMpsMeta = const VerificationMeta(
    'speedMps',
  );
  @override
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
    'speed_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    fromState,
    toState,
    timestamp,
    sigma,
    speedMps,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'state_transitions';
  @override
  VerificationContext validateIntegrity(
    Insertable<StateTransition> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('from_state')) {
      context.handle(
        _fromStateMeta,
        fromState.isAcceptableOrUnknown(data['from_state']!, _fromStateMeta),
      );
    } else if (isInserting) {
      context.missing(_fromStateMeta);
    }
    if (data.containsKey('to_state')) {
      context.handle(
        _toStateMeta,
        toState.isAcceptableOrUnknown(data['to_state']!, _toStateMeta),
      );
    } else if (isInserting) {
      context.missing(_toStateMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('sigma')) {
      context.handle(
        _sigmaMeta,
        sigma.isAcceptableOrUnknown(data['sigma']!, _sigmaMeta),
      );
    }
    if (data.containsKey('speed_mps')) {
      context.handle(
        _speedMpsMeta,
        speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  StateTransition map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return StateTransition(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      fromState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}from_state'],
      )!,
      toState: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}to_state'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      sigma: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}sigma'],
      ),
      speedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_mps'],
      ),
    );
  }

  @override
  $StateTransitionsTable createAlias(String alias) {
    return $StateTransitionsTable(attachedDatabase, alias);
  }
}

class StateTransition extends DataClass implements Insertable<StateTransition> {
  final int id;
  final String sessionId;
  final String fromState;
  final String toState;
  final DateTime timestamp;
  final double? sigma;
  final double? speedMps;
  const StateTransition({
    required this.id,
    required this.sessionId,
    required this.fromState,
    required this.toState,
    required this.timestamp,
    this.sigma,
    this.speedMps,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['from_state'] = Variable<String>(fromState);
    map['to_state'] = Variable<String>(toState);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || sigma != null) {
      map['sigma'] = Variable<double>(sigma);
    }
    if (!nullToAbsent || speedMps != null) {
      map['speed_mps'] = Variable<double>(speedMps);
    }
    return map;
  }

  StateTransitionsCompanion toCompanion(bool nullToAbsent) {
    return StateTransitionsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      fromState: Value(fromState),
      toState: Value(toState),
      timestamp: Value(timestamp),
      sigma: sigma == null && nullToAbsent
          ? const Value.absent()
          : Value(sigma),
      speedMps: speedMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMps),
    );
  }

  factory StateTransition.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return StateTransition(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      fromState: serializer.fromJson<String>(json['fromState']),
      toState: serializer.fromJson<String>(json['toState']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      sigma: serializer.fromJson<double?>(json['sigma']),
      speedMps: serializer.fromJson<double?>(json['speedMps']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'fromState': serializer.toJson<String>(fromState),
      'toState': serializer.toJson<String>(toState),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'sigma': serializer.toJson<double?>(sigma),
      'speedMps': serializer.toJson<double?>(speedMps),
    };
  }

  StateTransition copyWith({
    int? id,
    String? sessionId,
    String? fromState,
    String? toState,
    DateTime? timestamp,
    Value<double?> sigma = const Value.absent(),
    Value<double?> speedMps = const Value.absent(),
  }) => StateTransition(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    fromState: fromState ?? this.fromState,
    toState: toState ?? this.toState,
    timestamp: timestamp ?? this.timestamp,
    sigma: sigma.present ? sigma.value : this.sigma,
    speedMps: speedMps.present ? speedMps.value : this.speedMps,
  );
  StateTransition copyWithCompanion(StateTransitionsCompanion data) {
    return StateTransition(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      fromState: data.fromState.present ? data.fromState.value : this.fromState,
      toState: data.toState.present ? data.toState.value : this.toState,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      sigma: data.sigma.present ? data.sigma.value : this.sigma,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
    );
  }

  @override
  String toString() {
    return (StringBuffer('StateTransition(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('fromState: $fromState, ')
          ..write('toState: $toState, ')
          ..write('timestamp: $timestamp, ')
          ..write('sigma: $sigma, ')
          ..write('speedMps: $speedMps')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    fromState,
    toState,
    timestamp,
    sigma,
    speedMps,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is StateTransition &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.fromState == this.fromState &&
          other.toState == this.toState &&
          other.timestamp == this.timestamp &&
          other.sigma == this.sigma &&
          other.speedMps == this.speedMps);
}

class StateTransitionsCompanion extends UpdateCompanion<StateTransition> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<String> fromState;
  final Value<String> toState;
  final Value<DateTime> timestamp;
  final Value<double?> sigma;
  final Value<double?> speedMps;
  const StateTransitionsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.fromState = const Value.absent(),
    this.toState = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.sigma = const Value.absent(),
    this.speedMps = const Value.absent(),
  });
  StateTransitionsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required String fromState,
    required String toState,
    required DateTime timestamp,
    this.sigma = const Value.absent(),
    this.speedMps = const Value.absent(),
  }) : sessionId = Value(sessionId),
       fromState = Value(fromState),
       toState = Value(toState),
       timestamp = Value(timestamp);
  static Insertable<StateTransition> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<String>? fromState,
    Expression<String>? toState,
    Expression<DateTime>? timestamp,
    Expression<double>? sigma,
    Expression<double>? speedMps,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (fromState != null) 'from_state': fromState,
      if (toState != null) 'to_state': toState,
      if (timestamp != null) 'timestamp': timestamp,
      if (sigma != null) 'sigma': sigma,
      if (speedMps != null) 'speed_mps': speedMps,
    });
  }

  StateTransitionsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<String>? fromState,
    Value<String>? toState,
    Value<DateTime>? timestamp,
    Value<double?>? sigma,
    Value<double?>? speedMps,
  }) {
    return StateTransitionsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      fromState: fromState ?? this.fromState,
      toState: toState ?? this.toState,
      timestamp: timestamp ?? this.timestamp,
      sigma: sigma ?? this.sigma,
      speedMps: speedMps ?? this.speedMps,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (fromState.present) {
      map['from_state'] = Variable<String>(fromState.value);
    }
    if (toState.present) {
      map['to_state'] = Variable<String>(toState.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (sigma.present) {
      map['sigma'] = Variable<double>(sigma.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('StateTransitionsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('fromState: $fromState, ')
          ..write('toState: $toState, ')
          ..write('timestamp: $timestamp, ')
          ..write('sigma: $sigma, ')
          ..write('speedMps: $speedMps')
          ..write(')'))
        .toString();
  }
}

class $GpsPointsTable extends GpsPoints
    with TableInfo<$GpsPointsTable, GpsPoint> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GpsPointsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES acquisition_sessions (id)',
    ),
  );
  static const VerificationMeta _latitudeMeta = const VerificationMeta(
    'latitude',
  );
  @override
  late final GeneratedColumn<double> latitude = GeneratedColumn<double>(
    'latitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _longitudeMeta = const VerificationMeta(
    'longitude',
  );
  @override
  late final GeneratedColumn<double> longitude = GeneratedColumn<double>(
    'longitude',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _timestampMeta = const VerificationMeta(
    'timestamp',
  );
  @override
  late final GeneratedColumn<DateTime> timestamp = GeneratedColumn<DateTime>(
    'timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _speedMpsMeta = const VerificationMeta(
    'speedMps',
  );
  @override
  late final GeneratedColumn<double> speedMps = GeneratedColumn<double>(
    'speed_mps',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _accuracyMetersMeta = const VerificationMeta(
    'accuracyMeters',
  );
  @override
  late final GeneratedColumn<double> accuracyMeters = GeneratedColumn<double>(
    'accuracy_meters',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    latitude,
    longitude,
    timestamp,
    speedMps,
    accuracyMeters,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'gps_points';
  @override
  VerificationContext validateIntegrity(
    Insertable<GpsPoint> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('latitude')) {
      context.handle(
        _latitudeMeta,
        latitude.isAcceptableOrUnknown(data['latitude']!, _latitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_latitudeMeta);
    }
    if (data.containsKey('longitude')) {
      context.handle(
        _longitudeMeta,
        longitude.isAcceptableOrUnknown(data['longitude']!, _longitudeMeta),
      );
    } else if (isInserting) {
      context.missing(_longitudeMeta);
    }
    if (data.containsKey('timestamp')) {
      context.handle(
        _timestampMeta,
        timestamp.isAcceptableOrUnknown(data['timestamp']!, _timestampMeta),
      );
    } else if (isInserting) {
      context.missing(_timestampMeta);
    }
    if (data.containsKey('speed_mps')) {
      context.handle(
        _speedMpsMeta,
        speedMps.isAcceptableOrUnknown(data['speed_mps']!, _speedMpsMeta),
      );
    }
    if (data.containsKey('accuracy_meters')) {
      context.handle(
        _accuracyMetersMeta,
        accuracyMeters.isAcceptableOrUnknown(
          data['accuracy_meters']!,
          _accuracyMetersMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GpsPoint map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GpsPoint(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      latitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}latitude'],
      )!,
      longitude: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}longitude'],
      )!,
      timestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}timestamp'],
      )!,
      speedMps: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}speed_mps'],
      ),
      accuracyMeters: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}accuracy_meters'],
      ),
    );
  }

  @override
  $GpsPointsTable createAlias(String alias) {
    return $GpsPointsTable(attachedDatabase, alias);
  }
}

class GpsPoint extends DataClass implements Insertable<GpsPoint> {
  final int id;
  final String sessionId;
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final double? speedMps;
  final double? accuracyMeters;
  const GpsPoint({
    required this.id,
    required this.sessionId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    this.speedMps,
    this.accuracyMeters,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['latitude'] = Variable<double>(latitude);
    map['longitude'] = Variable<double>(longitude);
    map['timestamp'] = Variable<DateTime>(timestamp);
    if (!nullToAbsent || speedMps != null) {
      map['speed_mps'] = Variable<double>(speedMps);
    }
    if (!nullToAbsent || accuracyMeters != null) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters);
    }
    return map;
  }

  GpsPointsCompanion toCompanion(bool nullToAbsent) {
    return GpsPointsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      latitude: Value(latitude),
      longitude: Value(longitude),
      timestamp: Value(timestamp),
      speedMps: speedMps == null && nullToAbsent
          ? const Value.absent()
          : Value(speedMps),
      accuracyMeters: accuracyMeters == null && nullToAbsent
          ? const Value.absent()
          : Value(accuracyMeters),
    );
  }

  factory GpsPoint.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GpsPoint(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      latitude: serializer.fromJson<double>(json['latitude']),
      longitude: serializer.fromJson<double>(json['longitude']),
      timestamp: serializer.fromJson<DateTime>(json['timestamp']),
      speedMps: serializer.fromJson<double?>(json['speedMps']),
      accuracyMeters: serializer.fromJson<double?>(json['accuracyMeters']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'latitude': serializer.toJson<double>(latitude),
      'longitude': serializer.toJson<double>(longitude),
      'timestamp': serializer.toJson<DateTime>(timestamp),
      'speedMps': serializer.toJson<double?>(speedMps),
      'accuracyMeters': serializer.toJson<double?>(accuracyMeters),
    };
  }

  GpsPoint copyWith({
    int? id,
    String? sessionId,
    double? latitude,
    double? longitude,
    DateTime? timestamp,
    Value<double?> speedMps = const Value.absent(),
    Value<double?> accuracyMeters = const Value.absent(),
  }) => GpsPoint(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    latitude: latitude ?? this.latitude,
    longitude: longitude ?? this.longitude,
    timestamp: timestamp ?? this.timestamp,
    speedMps: speedMps.present ? speedMps.value : this.speedMps,
    accuracyMeters: accuracyMeters.present
        ? accuracyMeters.value
        : this.accuracyMeters,
  );
  GpsPoint copyWithCompanion(GpsPointsCompanion data) {
    return GpsPoint(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      latitude: data.latitude.present ? data.latitude.value : this.latitude,
      longitude: data.longitude.present ? data.longitude.value : this.longitude,
      timestamp: data.timestamp.present ? data.timestamp.value : this.timestamp,
      speedMps: data.speedMps.present ? data.speedMps.value : this.speedMps,
      accuracyMeters: data.accuracyMeters.present
          ? data.accuracyMeters.value
          : this.accuracyMeters,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GpsPoint(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('timestamp: $timestamp, ')
          ..write('speedMps: $speedMps, ')
          ..write('accuracyMeters: $accuracyMeters')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    latitude,
    longitude,
    timestamp,
    speedMps,
    accuracyMeters,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GpsPoint &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.latitude == this.latitude &&
          other.longitude == this.longitude &&
          other.timestamp == this.timestamp &&
          other.speedMps == this.speedMps &&
          other.accuracyMeters == this.accuracyMeters);
}

class GpsPointsCompanion extends UpdateCompanion<GpsPoint> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<double> latitude;
  final Value<double> longitude;
  final Value<DateTime> timestamp;
  final Value<double?> speedMps;
  final Value<double?> accuracyMeters;
  const GpsPointsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.latitude = const Value.absent(),
    this.longitude = const Value.absent(),
    this.timestamp = const Value.absent(),
    this.speedMps = const Value.absent(),
    this.accuracyMeters = const Value.absent(),
  });
  GpsPointsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required double latitude,
    required double longitude,
    required DateTime timestamp,
    this.speedMps = const Value.absent(),
    this.accuracyMeters = const Value.absent(),
  }) : sessionId = Value(sessionId),
       latitude = Value(latitude),
       longitude = Value(longitude),
       timestamp = Value(timestamp);
  static Insertable<GpsPoint> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<double>? latitude,
    Expression<double>? longitude,
    Expression<DateTime>? timestamp,
    Expression<double>? speedMps,
    Expression<double>? accuracyMeters,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (latitude != null) 'latitude': latitude,
      if (longitude != null) 'longitude': longitude,
      if (timestamp != null) 'timestamp': timestamp,
      if (speedMps != null) 'speed_mps': speedMps,
      if (accuracyMeters != null) 'accuracy_meters': accuracyMeters,
    });
  }

  GpsPointsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<double>? latitude,
    Value<double>? longitude,
    Value<DateTime>? timestamp,
    Value<double?>? speedMps,
    Value<double?>? accuracyMeters,
  }) {
    return GpsPointsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      timestamp: timestamp ?? this.timestamp,
      speedMps: speedMps ?? this.speedMps,
      accuracyMeters: accuracyMeters ?? this.accuracyMeters,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (latitude.present) {
      map['latitude'] = Variable<double>(latitude.value);
    }
    if (longitude.present) {
      map['longitude'] = Variable<double>(longitude.value);
    }
    if (timestamp.present) {
      map['timestamp'] = Variable<DateTime>(timestamp.value);
    }
    if (speedMps.present) {
      map['speed_mps'] = Variable<double>(speedMps.value);
    }
    if (accuracyMeters.present) {
      map['accuracy_meters'] = Variable<double>(accuracyMeters.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GpsPointsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('latitude: $latitude, ')
          ..write('longitude: $longitude, ')
          ..write('timestamp: $timestamp, ')
          ..write('speedMps: $speedMps, ')
          ..write('accuracyMeters: $accuracyMeters')
          ..write(')'))
        .toString();
  }
}

class $SensorWindowsTable extends SensorWindows
    with TableInfo<$SensorWindowsTable, SensorWindow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SensorWindowsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES acquisition_sessions (id)',
    ),
  );
  static const VerificationMeta _startTimestampMeta = const VerificationMeta(
    'startTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> startTimestamp =
      GeneratedColumn<DateTime>(
        'start_timestamp',
        aliasedName,
        false,
        type: DriftSqlType.dateTime,
        requiredDuringInsert: true,
      );
  static const VerificationMeta _endTimestampMeta = const VerificationMeta(
    'endTimestamp',
  );
  @override
  late final GeneratedColumn<DateTime> endTimestamp = GeneratedColumn<DateTime>(
    'end_timestamp',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sampleCountMeta = const VerificationMeta(
    'sampleCount',
  );
  @override
  late final GeneratedColumn<int> sampleCount = GeneratedColumn<int>(
    'sample_count',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _frequencyHzMeta = const VerificationMeta(
    'frequencyHz',
  );
  @override
  late final GeneratedColumn<int> frequencyHz = GeneratedColumn<int>(
    'frequency_hz',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _matrixJsonMeta = const VerificationMeta(
    'matrixJson',
  );
  @override
  late final GeneratedColumn<String> matrixJson = GeneratedColumn<String>(
    'matrix_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    sessionId,
    startTimestamp,
    endTimestamp,
    sampleCount,
    frequencyHz,
    matrixJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sensor_windows';
  @override
  VerificationContext validateIntegrity(
    Insertable<SensorWindow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    } else if (isInserting) {
      context.missing(_sessionIdMeta);
    }
    if (data.containsKey('start_timestamp')) {
      context.handle(
        _startTimestampMeta,
        startTimestamp.isAcceptableOrUnknown(
          data['start_timestamp']!,
          _startTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_startTimestampMeta);
    }
    if (data.containsKey('end_timestamp')) {
      context.handle(
        _endTimestampMeta,
        endTimestamp.isAcceptableOrUnknown(
          data['end_timestamp']!,
          _endTimestampMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_endTimestampMeta);
    }
    if (data.containsKey('sample_count')) {
      context.handle(
        _sampleCountMeta,
        sampleCount.isAcceptableOrUnknown(
          data['sample_count']!,
          _sampleCountMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_sampleCountMeta);
    }
    if (data.containsKey('frequency_hz')) {
      context.handle(
        _frequencyHzMeta,
        frequencyHz.isAcceptableOrUnknown(
          data['frequency_hz']!,
          _frequencyHzMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_frequencyHzMeta);
    }
    if (data.containsKey('matrix_json')) {
      context.handle(
        _matrixJsonMeta,
        matrixJson.isAcceptableOrUnknown(data['matrix_json']!, _matrixJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_matrixJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SensorWindow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SensorWindow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      )!,
      startTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}start_timestamp'],
      )!,
      endTimestamp: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}end_timestamp'],
      )!,
      sampleCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sample_count'],
      )!,
      frequencyHz: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}frequency_hz'],
      )!,
      matrixJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}matrix_json'],
      )!,
    );
  }

  @override
  $SensorWindowsTable createAlias(String alias) {
    return $SensorWindowsTable(attachedDatabase, alias);
  }
}

class SensorWindow extends DataClass implements Insertable<SensorWindow> {
  final int id;
  final String sessionId;
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final int sampleCount;
  final int frequencyHz;
  final String matrixJson;
  const SensorWindow({
    required this.id,
    required this.sessionId,
    required this.startTimestamp,
    required this.endTimestamp,
    required this.sampleCount,
    required this.frequencyHz,
    required this.matrixJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['session_id'] = Variable<String>(sessionId);
    map['start_timestamp'] = Variable<DateTime>(startTimestamp);
    map['end_timestamp'] = Variable<DateTime>(endTimestamp);
    map['sample_count'] = Variable<int>(sampleCount);
    map['frequency_hz'] = Variable<int>(frequencyHz);
    map['matrix_json'] = Variable<String>(matrixJson);
    return map;
  }

  SensorWindowsCompanion toCompanion(bool nullToAbsent) {
    return SensorWindowsCompanion(
      id: Value(id),
      sessionId: Value(sessionId),
      startTimestamp: Value(startTimestamp),
      endTimestamp: Value(endTimestamp),
      sampleCount: Value(sampleCount),
      frequencyHz: Value(frequencyHz),
      matrixJson: Value(matrixJson),
    );
  }

  factory SensorWindow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SensorWindow(
      id: serializer.fromJson<int>(json['id']),
      sessionId: serializer.fromJson<String>(json['sessionId']),
      startTimestamp: serializer.fromJson<DateTime>(json['startTimestamp']),
      endTimestamp: serializer.fromJson<DateTime>(json['endTimestamp']),
      sampleCount: serializer.fromJson<int>(json['sampleCount']),
      frequencyHz: serializer.fromJson<int>(json['frequencyHz']),
      matrixJson: serializer.fromJson<String>(json['matrixJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'sessionId': serializer.toJson<String>(sessionId),
      'startTimestamp': serializer.toJson<DateTime>(startTimestamp),
      'endTimestamp': serializer.toJson<DateTime>(endTimestamp),
      'sampleCount': serializer.toJson<int>(sampleCount),
      'frequencyHz': serializer.toJson<int>(frequencyHz),
      'matrixJson': serializer.toJson<String>(matrixJson),
    };
  }

  SensorWindow copyWith({
    int? id,
    String? sessionId,
    DateTime? startTimestamp,
    DateTime? endTimestamp,
    int? sampleCount,
    int? frequencyHz,
    String? matrixJson,
  }) => SensorWindow(
    id: id ?? this.id,
    sessionId: sessionId ?? this.sessionId,
    startTimestamp: startTimestamp ?? this.startTimestamp,
    endTimestamp: endTimestamp ?? this.endTimestamp,
    sampleCount: sampleCount ?? this.sampleCount,
    frequencyHz: frequencyHz ?? this.frequencyHz,
    matrixJson: matrixJson ?? this.matrixJson,
  );
  SensorWindow copyWithCompanion(SensorWindowsCompanion data) {
    return SensorWindow(
      id: data.id.present ? data.id.value : this.id,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      startTimestamp: data.startTimestamp.present
          ? data.startTimestamp.value
          : this.startTimestamp,
      endTimestamp: data.endTimestamp.present
          ? data.endTimestamp.value
          : this.endTimestamp,
      sampleCount: data.sampleCount.present
          ? data.sampleCount.value
          : this.sampleCount,
      frequencyHz: data.frequencyHz.present
          ? data.frequencyHz.value
          : this.frequencyHz,
      matrixJson: data.matrixJson.present
          ? data.matrixJson.value
          : this.matrixJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SensorWindow(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('startTimestamp: $startTimestamp, ')
          ..write('endTimestamp: $endTimestamp, ')
          ..write('sampleCount: $sampleCount, ')
          ..write('frequencyHz: $frequencyHz, ')
          ..write('matrixJson: $matrixJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    startTimestamp,
    endTimestamp,
    sampleCount,
    frequencyHz,
    matrixJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SensorWindow &&
          other.id == this.id &&
          other.sessionId == this.sessionId &&
          other.startTimestamp == this.startTimestamp &&
          other.endTimestamp == this.endTimestamp &&
          other.sampleCount == this.sampleCount &&
          other.frequencyHz == this.frequencyHz &&
          other.matrixJson == this.matrixJson);
}

class SensorWindowsCompanion extends UpdateCompanion<SensorWindow> {
  final Value<int> id;
  final Value<String> sessionId;
  final Value<DateTime> startTimestamp;
  final Value<DateTime> endTimestamp;
  final Value<int> sampleCount;
  final Value<int> frequencyHz;
  final Value<String> matrixJson;
  const SensorWindowsCompanion({
    this.id = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.startTimestamp = const Value.absent(),
    this.endTimestamp = const Value.absent(),
    this.sampleCount = const Value.absent(),
    this.frequencyHz = const Value.absent(),
    this.matrixJson = const Value.absent(),
  });
  SensorWindowsCompanion.insert({
    this.id = const Value.absent(),
    required String sessionId,
    required DateTime startTimestamp,
    required DateTime endTimestamp,
    required int sampleCount,
    required int frequencyHz,
    required String matrixJson,
  }) : sessionId = Value(sessionId),
       startTimestamp = Value(startTimestamp),
       endTimestamp = Value(endTimestamp),
       sampleCount = Value(sampleCount),
       frequencyHz = Value(frequencyHz),
       matrixJson = Value(matrixJson);
  static Insertable<SensorWindow> custom({
    Expression<int>? id,
    Expression<String>? sessionId,
    Expression<DateTime>? startTimestamp,
    Expression<DateTime>? endTimestamp,
    Expression<int>? sampleCount,
    Expression<int>? frequencyHz,
    Expression<String>? matrixJson,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (sessionId != null) 'session_id': sessionId,
      if (startTimestamp != null) 'start_timestamp': startTimestamp,
      if (endTimestamp != null) 'end_timestamp': endTimestamp,
      if (sampleCount != null) 'sample_count': sampleCount,
      if (frequencyHz != null) 'frequency_hz': frequencyHz,
      if (matrixJson != null) 'matrix_json': matrixJson,
    });
  }

  SensorWindowsCompanion copyWith({
    Value<int>? id,
    Value<String>? sessionId,
    Value<DateTime>? startTimestamp,
    Value<DateTime>? endTimestamp,
    Value<int>? sampleCount,
    Value<int>? frequencyHz,
    Value<String>? matrixJson,
  }) {
    return SensorWindowsCompanion(
      id: id ?? this.id,
      sessionId: sessionId ?? this.sessionId,
      startTimestamp: startTimestamp ?? this.startTimestamp,
      endTimestamp: endTimestamp ?? this.endTimestamp,
      sampleCount: sampleCount ?? this.sampleCount,
      frequencyHz: frequencyHz ?? this.frequencyHz,
      matrixJson: matrixJson ?? this.matrixJson,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (startTimestamp.present) {
      map['start_timestamp'] = Variable<DateTime>(startTimestamp.value);
    }
    if (endTimestamp.present) {
      map['end_timestamp'] = Variable<DateTime>(endTimestamp.value);
    }
    if (sampleCount.present) {
      map['sample_count'] = Variable<int>(sampleCount.value);
    }
    if (frequencyHz.present) {
      map['frequency_hz'] = Variable<int>(frequencyHz.value);
    }
    if (matrixJson.present) {
      map['matrix_json'] = Variable<String>(matrixJson.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SensorWindowsCompanion(')
          ..write('id: $id, ')
          ..write('sessionId: $sessionId, ')
          ..write('startTimestamp: $startTimestamp, ')
          ..write('endTimestamp: $endTimestamp, ')
          ..write('sampleCount: $sampleCount, ')
          ..write('frequencyHz: $frequencyHz, ')
          ..write('matrixJson: $matrixJson')
          ..write(')'))
        .toString();
  }
}

class $SyncJobsTable extends SyncJobs with TableInfo<$SyncJobsTable, SyncJob> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _localSessionIdMeta = const VerificationMeta(
    'localSessionId',
  );
  @override
  late final GeneratedColumn<String> localSessionId = GeneratedColumn<String>(
    'local_session_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES acquisition_sessions (id)',
    ),
  );
  static const VerificationMeta _remoteUploadIdMeta = const VerificationMeta(
    'remoteUploadId',
  );
  @override
  late final GeneratedColumn<int> remoteUploadId = GeneratedColumn<int>(
    'remote_upload_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteTripIdMeta = const VerificationMeta(
    'remoteTripId',
  );
  @override
  late final GeneratedColumn<int> remoteTripId = GeneratedColumn<int>(
    'remote_trip_id',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _corePayloadSizeBytesMeta =
      const VerificationMeta('corePayloadSizeBytes');
  @override
  late final GeneratedColumn<int> corePayloadSizeBytes = GeneratedColumn<int>(
    'core_payload_size_bytes',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _coreMapAvailableMeta = const VerificationMeta(
    'coreMapAvailable',
  );
  @override
  late final GeneratedColumn<bool> coreMapAvailable = GeneratedColumn<bool>(
    'core_map_available',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("core_map_available" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _coreStatusMeta = const VerificationMeta(
    'coreStatus',
  );
  @override
  late final GeneratedColumn<String> coreStatus = GeneratedColumn<String>(
    'core_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(syncJobPending),
  );
  static const VerificationMeta _rawStatusMeta = const VerificationMeta(
    'rawStatus',
  );
  @override
  late final GeneratedColumn<String> rawStatus = GeneratedColumn<String>(
    'raw_status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(syncJobPending),
  );
  static const VerificationMeta _attemptsMeta = const VerificationMeta(
    'attempts',
  );
  @override
  late final GeneratedColumn<int> attempts = GeneratedColumn<int>(
    'attempts',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _nextRetryAtMeta = const VerificationMeta(
    'nextRetryAt',
  );
  @override
  late final GeneratedColumn<DateTime> nextRetryAt = GeneratedColumn<DateTime>(
    'next_retry_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastErrorMeta = const VerificationMeta(
    'lastError',
  );
  @override
  late final GeneratedColumn<String> lastError = GeneratedColumn<String>(
    'last_error',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<DateTime> createdAt = GeneratedColumn<DateTime>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<DateTime> updatedAt = GeneratedColumn<DateTime>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    localSessionId,
    remoteUploadId,
    remoteTripId,
    corePayloadSizeBytes,
    coreMapAvailable,
    coreStatus,
    rawStatus,
    attempts,
    nextRetryAt,
    lastError,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncJob> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('local_session_id')) {
      context.handle(
        _localSessionIdMeta,
        localSessionId.isAcceptableOrUnknown(
          data['local_session_id']!,
          _localSessionIdMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_localSessionIdMeta);
    }
    if (data.containsKey('remote_upload_id')) {
      context.handle(
        _remoteUploadIdMeta,
        remoteUploadId.isAcceptableOrUnknown(
          data['remote_upload_id']!,
          _remoteUploadIdMeta,
        ),
      );
    }
    if (data.containsKey('remote_trip_id')) {
      context.handle(
        _remoteTripIdMeta,
        remoteTripId.isAcceptableOrUnknown(
          data['remote_trip_id']!,
          _remoteTripIdMeta,
        ),
      );
    }
    if (data.containsKey('core_payload_size_bytes')) {
      context.handle(
        _corePayloadSizeBytesMeta,
        corePayloadSizeBytes.isAcceptableOrUnknown(
          data['core_payload_size_bytes']!,
          _corePayloadSizeBytesMeta,
        ),
      );
    }
    if (data.containsKey('core_map_available')) {
      context.handle(
        _coreMapAvailableMeta,
        coreMapAvailable.isAcceptableOrUnknown(
          data['core_map_available']!,
          _coreMapAvailableMeta,
        ),
      );
    }
    if (data.containsKey('core_status')) {
      context.handle(
        _coreStatusMeta,
        coreStatus.isAcceptableOrUnknown(data['core_status']!, _coreStatusMeta),
      );
    }
    if (data.containsKey('raw_status')) {
      context.handle(
        _rawStatusMeta,
        rawStatus.isAcceptableOrUnknown(data['raw_status']!, _rawStatusMeta),
      );
    }
    if (data.containsKey('attempts')) {
      context.handle(
        _attemptsMeta,
        attempts.isAcceptableOrUnknown(data['attempts']!, _attemptsMeta),
      );
    }
    if (data.containsKey('next_retry_at')) {
      context.handle(
        _nextRetryAtMeta,
        nextRetryAt.isAcceptableOrUnknown(
          data['next_retry_at']!,
          _nextRetryAtMeta,
        ),
      );
    }
    if (data.containsKey('last_error')) {
      context.handle(
        _lastErrorMeta,
        lastError.isAcceptableOrUnknown(data['last_error']!, _lastErrorMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  List<Set<GeneratedColumn>> get uniqueKeys => [
    {localSessionId},
  ];
  @override
  SyncJob map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncJob(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      localSessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}local_session_id'],
      )!,
      remoteUploadId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_upload_id'],
      ),
      remoteTripId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}remote_trip_id'],
      ),
      corePayloadSizeBytes: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}core_payload_size_bytes'],
      )!,
      coreMapAvailable: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}core_map_available'],
      )!,
      coreStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}core_status'],
      )!,
      rawStatus: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}raw_status'],
      )!,
      attempts: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}attempts'],
      )!,
      nextRetryAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}next_retry_at'],
      ),
      lastError: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_error'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $SyncJobsTable createAlias(String alias) {
    return $SyncJobsTable(attachedDatabase, alias);
  }
}

class SyncJob extends DataClass implements Insertable<SyncJob> {
  final int id;
  final String localSessionId;
  final int? remoteUploadId;
  final int? remoteTripId;
  final int corePayloadSizeBytes;
  final bool coreMapAvailable;
  final String coreStatus;
  final String rawStatus;
  final int attempts;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime createdAt;
  final DateTime updatedAt;
  const SyncJob({
    required this.id,
    required this.localSessionId,
    this.remoteUploadId,
    this.remoteTripId,
    required this.corePayloadSizeBytes,
    required this.coreMapAvailable,
    required this.coreStatus,
    required this.rawStatus,
    required this.attempts,
    this.nextRetryAt,
    this.lastError,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['local_session_id'] = Variable<String>(localSessionId);
    if (!nullToAbsent || remoteUploadId != null) {
      map['remote_upload_id'] = Variable<int>(remoteUploadId);
    }
    if (!nullToAbsent || remoteTripId != null) {
      map['remote_trip_id'] = Variable<int>(remoteTripId);
    }
    map['core_payload_size_bytes'] = Variable<int>(corePayloadSizeBytes);
    map['core_map_available'] = Variable<bool>(coreMapAvailable);
    map['core_status'] = Variable<String>(coreStatus);
    map['raw_status'] = Variable<String>(rawStatus);
    map['attempts'] = Variable<int>(attempts);
    if (!nullToAbsent || nextRetryAt != null) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt);
    }
    if (!nullToAbsent || lastError != null) {
      map['last_error'] = Variable<String>(lastError);
    }
    map['created_at'] = Variable<DateTime>(createdAt);
    map['updated_at'] = Variable<DateTime>(updatedAt);
    return map;
  }

  SyncJobsCompanion toCompanion(bool nullToAbsent) {
    return SyncJobsCompanion(
      id: Value(id),
      localSessionId: Value(localSessionId),
      remoteUploadId: remoteUploadId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteUploadId),
      remoteTripId: remoteTripId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteTripId),
      corePayloadSizeBytes: Value(corePayloadSizeBytes),
      coreMapAvailable: Value(coreMapAvailable),
      coreStatus: Value(coreStatus),
      rawStatus: Value(rawStatus),
      attempts: Value(attempts),
      nextRetryAt: nextRetryAt == null && nullToAbsent
          ? const Value.absent()
          : Value(nextRetryAt),
      lastError: lastError == null && nullToAbsent
          ? const Value.absent()
          : Value(lastError),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory SyncJob.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncJob(
      id: serializer.fromJson<int>(json['id']),
      localSessionId: serializer.fromJson<String>(json['localSessionId']),
      remoteUploadId: serializer.fromJson<int?>(json['remoteUploadId']),
      remoteTripId: serializer.fromJson<int?>(json['remoteTripId']),
      corePayloadSizeBytes: serializer.fromJson<int>(
        json['corePayloadSizeBytes'],
      ),
      coreMapAvailable: serializer.fromJson<bool>(json['coreMapAvailable']),
      coreStatus: serializer.fromJson<String>(json['coreStatus']),
      rawStatus: serializer.fromJson<String>(json['rawStatus']),
      attempts: serializer.fromJson<int>(json['attempts']),
      nextRetryAt: serializer.fromJson<DateTime?>(json['nextRetryAt']),
      lastError: serializer.fromJson<String?>(json['lastError']),
      createdAt: serializer.fromJson<DateTime>(json['createdAt']),
      updatedAt: serializer.fromJson<DateTime>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'localSessionId': serializer.toJson<String>(localSessionId),
      'remoteUploadId': serializer.toJson<int?>(remoteUploadId),
      'remoteTripId': serializer.toJson<int?>(remoteTripId),
      'corePayloadSizeBytes': serializer.toJson<int>(corePayloadSizeBytes),
      'coreMapAvailable': serializer.toJson<bool>(coreMapAvailable),
      'coreStatus': serializer.toJson<String>(coreStatus),
      'rawStatus': serializer.toJson<String>(rawStatus),
      'attempts': serializer.toJson<int>(attempts),
      'nextRetryAt': serializer.toJson<DateTime?>(nextRetryAt),
      'lastError': serializer.toJson<String?>(lastError),
      'createdAt': serializer.toJson<DateTime>(createdAt),
      'updatedAt': serializer.toJson<DateTime>(updatedAt),
    };
  }

  SyncJob copyWith({
    int? id,
    String? localSessionId,
    Value<int?> remoteUploadId = const Value.absent(),
    Value<int?> remoteTripId = const Value.absent(),
    int? corePayloadSizeBytes,
    bool? coreMapAvailable,
    String? coreStatus,
    String? rawStatus,
    int? attempts,
    Value<DateTime?> nextRetryAt = const Value.absent(),
    Value<String?> lastError = const Value.absent(),
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SyncJob(
    id: id ?? this.id,
    localSessionId: localSessionId ?? this.localSessionId,
    remoteUploadId: remoteUploadId.present
        ? remoteUploadId.value
        : this.remoteUploadId,
    remoteTripId: remoteTripId.present ? remoteTripId.value : this.remoteTripId,
    corePayloadSizeBytes: corePayloadSizeBytes ?? this.corePayloadSizeBytes,
    coreMapAvailable: coreMapAvailable ?? this.coreMapAvailable,
    coreStatus: coreStatus ?? this.coreStatus,
    rawStatus: rawStatus ?? this.rawStatus,
    attempts: attempts ?? this.attempts,
    nextRetryAt: nextRetryAt.present ? nextRetryAt.value : this.nextRetryAt,
    lastError: lastError.present ? lastError.value : this.lastError,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  SyncJob copyWithCompanion(SyncJobsCompanion data) {
    return SyncJob(
      id: data.id.present ? data.id.value : this.id,
      localSessionId: data.localSessionId.present
          ? data.localSessionId.value
          : this.localSessionId,
      remoteUploadId: data.remoteUploadId.present
          ? data.remoteUploadId.value
          : this.remoteUploadId,
      remoteTripId: data.remoteTripId.present
          ? data.remoteTripId.value
          : this.remoteTripId,
      corePayloadSizeBytes: data.corePayloadSizeBytes.present
          ? data.corePayloadSizeBytes.value
          : this.corePayloadSizeBytes,
      coreMapAvailable: data.coreMapAvailable.present
          ? data.coreMapAvailable.value
          : this.coreMapAvailable,
      coreStatus: data.coreStatus.present
          ? data.coreStatus.value
          : this.coreStatus,
      rawStatus: data.rawStatus.present ? data.rawStatus.value : this.rawStatus,
      attempts: data.attempts.present ? data.attempts.value : this.attempts,
      nextRetryAt: data.nextRetryAt.present
          ? data.nextRetryAt.value
          : this.nextRetryAt,
      lastError: data.lastError.present ? data.lastError.value : this.lastError,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncJob(')
          ..write('id: $id, ')
          ..write('localSessionId: $localSessionId, ')
          ..write('remoteUploadId: $remoteUploadId, ')
          ..write('remoteTripId: $remoteTripId, ')
          ..write('corePayloadSizeBytes: $corePayloadSizeBytes, ')
          ..write('coreMapAvailable: $coreMapAvailable, ')
          ..write('coreStatus: $coreStatus, ')
          ..write('rawStatus: $rawStatus, ')
          ..write('attempts: $attempts, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    localSessionId,
    remoteUploadId,
    remoteTripId,
    corePayloadSizeBytes,
    coreMapAvailable,
    coreStatus,
    rawStatus,
    attempts,
    nextRetryAt,
    lastError,
    createdAt,
    updatedAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncJob &&
          other.id == this.id &&
          other.localSessionId == this.localSessionId &&
          other.remoteUploadId == this.remoteUploadId &&
          other.remoteTripId == this.remoteTripId &&
          other.corePayloadSizeBytes == this.corePayloadSizeBytes &&
          other.coreMapAvailable == this.coreMapAvailable &&
          other.coreStatus == this.coreStatus &&
          other.rawStatus == this.rawStatus &&
          other.attempts == this.attempts &&
          other.nextRetryAt == this.nextRetryAt &&
          other.lastError == this.lastError &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class SyncJobsCompanion extends UpdateCompanion<SyncJob> {
  final Value<int> id;
  final Value<String> localSessionId;
  final Value<int?> remoteUploadId;
  final Value<int?> remoteTripId;
  final Value<int> corePayloadSizeBytes;
  final Value<bool> coreMapAvailable;
  final Value<String> coreStatus;
  final Value<String> rawStatus;
  final Value<int> attempts;
  final Value<DateTime?> nextRetryAt;
  final Value<String?> lastError;
  final Value<DateTime> createdAt;
  final Value<DateTime> updatedAt;
  const SyncJobsCompanion({
    this.id = const Value.absent(),
    this.localSessionId = const Value.absent(),
    this.remoteUploadId = const Value.absent(),
    this.remoteTripId = const Value.absent(),
    this.corePayloadSizeBytes = const Value.absent(),
    this.coreMapAvailable = const Value.absent(),
    this.coreStatus = const Value.absent(),
    this.rawStatus = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
  });
  SyncJobsCompanion.insert({
    this.id = const Value.absent(),
    required String localSessionId,
    this.remoteUploadId = const Value.absent(),
    this.remoteTripId = const Value.absent(),
    this.corePayloadSizeBytes = const Value.absent(),
    this.coreMapAvailable = const Value.absent(),
    this.coreStatus = const Value.absent(),
    this.rawStatus = const Value.absent(),
    this.attempts = const Value.absent(),
    this.nextRetryAt = const Value.absent(),
    this.lastError = const Value.absent(),
    required DateTime createdAt,
    required DateTime updatedAt,
  }) : localSessionId = Value(localSessionId),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<SyncJob> custom({
    Expression<int>? id,
    Expression<String>? localSessionId,
    Expression<int>? remoteUploadId,
    Expression<int>? remoteTripId,
    Expression<int>? corePayloadSizeBytes,
    Expression<bool>? coreMapAvailable,
    Expression<String>? coreStatus,
    Expression<String>? rawStatus,
    Expression<int>? attempts,
    Expression<DateTime>? nextRetryAt,
    Expression<String>? lastError,
    Expression<DateTime>? createdAt,
    Expression<DateTime>? updatedAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (localSessionId != null) 'local_session_id': localSessionId,
      if (remoteUploadId != null) 'remote_upload_id': remoteUploadId,
      if (remoteTripId != null) 'remote_trip_id': remoteTripId,
      if (corePayloadSizeBytes != null)
        'core_payload_size_bytes': corePayloadSizeBytes,
      if (coreMapAvailable != null) 'core_map_available': coreMapAvailable,
      if (coreStatus != null) 'core_status': coreStatus,
      if (rawStatus != null) 'raw_status': rawStatus,
      if (attempts != null) 'attempts': attempts,
      if (nextRetryAt != null) 'next_retry_at': nextRetryAt,
      if (lastError != null) 'last_error': lastError,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
    });
  }

  SyncJobsCompanion copyWith({
    Value<int>? id,
    Value<String>? localSessionId,
    Value<int?>? remoteUploadId,
    Value<int?>? remoteTripId,
    Value<int>? corePayloadSizeBytes,
    Value<bool>? coreMapAvailable,
    Value<String>? coreStatus,
    Value<String>? rawStatus,
    Value<int>? attempts,
    Value<DateTime?>? nextRetryAt,
    Value<String?>? lastError,
    Value<DateTime>? createdAt,
    Value<DateTime>? updatedAt,
  }) {
    return SyncJobsCompanion(
      id: id ?? this.id,
      localSessionId: localSessionId ?? this.localSessionId,
      remoteUploadId: remoteUploadId ?? this.remoteUploadId,
      remoteTripId: remoteTripId ?? this.remoteTripId,
      corePayloadSizeBytes: corePayloadSizeBytes ?? this.corePayloadSizeBytes,
      coreMapAvailable: coreMapAvailable ?? this.coreMapAvailable,
      coreStatus: coreStatus ?? this.coreStatus,
      rawStatus: rawStatus ?? this.rawStatus,
      attempts: attempts ?? this.attempts,
      nextRetryAt: nextRetryAt ?? this.nextRetryAt,
      lastError: lastError ?? this.lastError,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (localSessionId.present) {
      map['local_session_id'] = Variable<String>(localSessionId.value);
    }
    if (remoteUploadId.present) {
      map['remote_upload_id'] = Variable<int>(remoteUploadId.value);
    }
    if (remoteTripId.present) {
      map['remote_trip_id'] = Variable<int>(remoteTripId.value);
    }
    if (corePayloadSizeBytes.present) {
      map['core_payload_size_bytes'] = Variable<int>(
        corePayloadSizeBytes.value,
      );
    }
    if (coreMapAvailable.present) {
      map['core_map_available'] = Variable<bool>(coreMapAvailable.value);
    }
    if (coreStatus.present) {
      map['core_status'] = Variable<String>(coreStatus.value);
    }
    if (rawStatus.present) {
      map['raw_status'] = Variable<String>(rawStatus.value);
    }
    if (attempts.present) {
      map['attempts'] = Variable<int>(attempts.value);
    }
    if (nextRetryAt.present) {
      map['next_retry_at'] = Variable<DateTime>(nextRetryAt.value);
    }
    if (lastError.present) {
      map['last_error'] = Variable<String>(lastError.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<DateTime>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<DateTime>(updatedAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncJobsCompanion(')
          ..write('id: $id, ')
          ..write('localSessionId: $localSessionId, ')
          ..write('remoteUploadId: $remoteUploadId, ')
          ..write('remoteTripId: $remoteTripId, ')
          ..write('corePayloadSizeBytes: $corePayloadSizeBytes, ')
          ..write('coreMapAvailable: $coreMapAvailable, ')
          ..write('coreStatus: $coreStatus, ')
          ..write('rawStatus: $rawStatus, ')
          ..write('attempts: $attempts, ')
          ..write('nextRetryAt: $nextRetryAt, ')
          ..write('lastError: $lastError, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AcquisitionLocalDatabase extends GeneratedDatabase {
  _$AcquisitionLocalDatabase(QueryExecutor e) : super(e);
  $AcquisitionLocalDatabaseManager get managers =>
      $AcquisitionLocalDatabaseManager(this);
  late final $AcquisitionSessionsTable acquisitionSessions =
      $AcquisitionSessionsTable(this);
  late final $StateTransitionsTable stateTransitions = $StateTransitionsTable(
    this,
  );
  late final $GpsPointsTable gpsPoints = $GpsPointsTable(this);
  late final $SensorWindowsTable sensorWindows = $SensorWindowsTable(this);
  late final $SyncJobsTable syncJobs = $SyncJobsTable(this);
  late final AcquisitionDao acquisitionDao = AcquisitionDao(
    this as AcquisitionLocalDatabase,
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    acquisitionSessions,
    stateTransitions,
    gpsPoints,
    sensorWindows,
    syncJobs,
  ];
}

typedef $$AcquisitionSessionsTableCreateCompanionBuilder =
    AcquisitionSessionsCompanion Function({
      required String id,
      required String deviceId,
      Value<int?> remoteUploadId,
      required DateTime startedAt,
      Value<DateTime?> endedAt,
      Value<int> rowid,
    });
typedef $$AcquisitionSessionsTableUpdateCompanionBuilder =
    AcquisitionSessionsCompanion Function({
      Value<String> id,
      Value<String> deviceId,
      Value<int?> remoteUploadId,
      Value<DateTime> startedAt,
      Value<DateTime?> endedAt,
      Value<int> rowid,
    });

final class $$AcquisitionSessionsTableReferences
    extends
        BaseReferences<
          _$AcquisitionLocalDatabase,
          $AcquisitionSessionsTable,
          AcquisitionSession
        > {
  $$AcquisitionSessionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static MultiTypedResultKey<$StateTransitionsTable, List<StateTransition>>
  _stateTransitionsRefsTable(_$AcquisitionLocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.stateTransitions,
        aliasName: 'acquisition_sessions__id__state_transitions__session_id',
      );

  $$StateTransitionsTableProcessedTableManager get stateTransitionsRefs {
    final manager = $$StateTransitionsTableTableManager(
      $_db,
      $_db.stateTransitions,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(
      _stateTransitionsRefsTable($_db),
    );
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$GpsPointsTable, List<GpsPoint>>
  _gpsPointsRefsTable(_$AcquisitionLocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.gpsPoints,
        aliasName: 'acquisition_sessions__id__gps_points__session_id',
      );

  $$GpsPointsTableProcessedTableManager get gpsPointsRefs {
    final manager = $$GpsPointsTableTableManager(
      $_db,
      $_db.gpsPoints,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_gpsPointsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SensorWindowsTable, List<SensorWindow>>
  _sensorWindowsRefsTable(_$AcquisitionLocalDatabase db) =>
      MultiTypedResultKey.fromTable(
        db.sensorWindows,
        aliasName: 'acquisition_sessions__id__sensor_windows__session_id',
      );

  $$SensorWindowsTableProcessedTableManager get sensorWindowsRefs {
    final manager = $$SensorWindowsTableTableManager(
      $_db,
      $_db.sensorWindows,
    ).filter((f) => f.sessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_sensorWindowsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }

  static MultiTypedResultKey<$SyncJobsTable, List<SyncJob>> _syncJobsRefsTable(
    _$AcquisitionLocalDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.syncJobs,
    aliasName: 'acquisition_sessions__id__sync_jobs__local_session_id',
  );

  $$SyncJobsTableProcessedTableManager get syncJobsRefs {
    final manager = $$SyncJobsTableTableManager(
      $_db,
      $_db.syncJobs,
    ).filter((f) => f.localSessionId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_syncJobsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$AcquisitionSessionsTableFilterComposer
    extends Composer<_$AcquisitionLocalDatabase, $AcquisitionSessionsTable> {
  $$AcquisitionSessionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteUploadId => $composableBuilder(
    column: $table.remoteUploadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> stateTransitionsRefs(
    Expression<bool> Function($$StateTransitionsTableFilterComposer f) f,
  ) {
    final $$StateTransitionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stateTransitions,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StateTransitionsTableFilterComposer(
            $db: $db,
            $table: $db.stateTransitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> gpsPointsRefs(
    Expression<bool> Function($$GpsPointsTableFilterComposer f) f,
  ) {
    final $$GpsPointsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gpsPoints,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GpsPointsTableFilterComposer(
            $db: $db,
            $table: $db.gpsPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> sensorWindowsRefs(
    Expression<bool> Function($$SensorWindowsTableFilterComposer f) f,
  ) {
    final $$SensorWindowsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sensorWindows,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SensorWindowsTableFilterComposer(
            $db: $db,
            $table: $db.sensorWindows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<bool> syncJobsRefs(
    Expression<bool> Function($$SyncJobsTableFilterComposer f) f,
  ) {
    final $$SyncJobsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncJobs,
      getReferencedColumn: (t) => t.localSessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncJobsTableFilterComposer(
            $db: $db,
            $table: $db.syncJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AcquisitionSessionsTableOrderingComposer
    extends Composer<_$AcquisitionLocalDatabase, $AcquisitionSessionsTable> {
  $$AcquisitionSessionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteUploadId => $composableBuilder(
    column: $table.remoteUploadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startedAt => $composableBuilder(
    column: $table.startedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endedAt => $composableBuilder(
    column: $table.endedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AcquisitionSessionsTableAnnotationComposer
    extends Composer<_$AcquisitionLocalDatabase, $AcquisitionSessionsTable> {
  $$AcquisitionSessionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<int> get remoteUploadId => $composableBuilder(
    column: $table.remoteUploadId,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get startedAt =>
      $composableBuilder(column: $table.startedAt, builder: (column) => column);

  GeneratedColumn<DateTime> get endedAt =>
      $composableBuilder(column: $table.endedAt, builder: (column) => column);

  Expression<T> stateTransitionsRefs<T extends Object>(
    Expression<T> Function($$StateTransitionsTableAnnotationComposer a) f,
  ) {
    final $$StateTransitionsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.stateTransitions,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$StateTransitionsTableAnnotationComposer(
            $db: $db,
            $table: $db.stateTransitions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> gpsPointsRefs<T extends Object>(
    Expression<T> Function($$GpsPointsTableAnnotationComposer a) f,
  ) {
    final $$GpsPointsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.gpsPoints,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$GpsPointsTableAnnotationComposer(
            $db: $db,
            $table: $db.gpsPoints,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> sensorWindowsRefs<T extends Object>(
    Expression<T> Function($$SensorWindowsTableAnnotationComposer a) f,
  ) {
    final $$SensorWindowsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.sensorWindows,
      getReferencedColumn: (t) => t.sessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SensorWindowsTableAnnotationComposer(
            $db: $db,
            $table: $db.sensorWindows,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }

  Expression<T> syncJobsRefs<T extends Object>(
    Expression<T> Function($$SyncJobsTableAnnotationComposer a) f,
  ) {
    final $$SyncJobsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.syncJobs,
      getReferencedColumn: (t) => t.localSessionId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$SyncJobsTableAnnotationComposer(
            $db: $db,
            $table: $db.syncJobs,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$AcquisitionSessionsTableTableManager
    extends
        RootTableManager<
          _$AcquisitionLocalDatabase,
          $AcquisitionSessionsTable,
          AcquisitionSession,
          $$AcquisitionSessionsTableFilterComposer,
          $$AcquisitionSessionsTableOrderingComposer,
          $$AcquisitionSessionsTableAnnotationComposer,
          $$AcquisitionSessionsTableCreateCompanionBuilder,
          $$AcquisitionSessionsTableUpdateCompanionBuilder,
          (AcquisitionSession, $$AcquisitionSessionsTableReferences),
          AcquisitionSession,
          PrefetchHooks Function({
            bool stateTransitionsRefs,
            bool gpsPointsRefs,
            bool sensorWindowsRefs,
            bool syncJobsRefs,
          })
        > {
  $$AcquisitionSessionsTableTableManager(
    _$AcquisitionLocalDatabase db,
    $AcquisitionSessionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AcquisitionSessionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AcquisitionSessionsTableOrderingComposer(
                $db: db,
                $table: table,
              ),
          createComputedFieldComposer: () =>
              $$AcquisitionSessionsTableAnnotationComposer(
                $db: db,
                $table: table,
              ),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deviceId = const Value.absent(),
                Value<int?> remoteUploadId = const Value.absent(),
                Value<DateTime> startedAt = const Value.absent(),
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AcquisitionSessionsCompanion(
                id: id,
                deviceId: deviceId,
                remoteUploadId: remoteUploadId,
                startedAt: startedAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deviceId,
                Value<int?> remoteUploadId = const Value.absent(),
                required DateTime startedAt,
                Value<DateTime?> endedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AcquisitionSessionsCompanion.insert(
                id: id,
                deviceId: deviceId,
                remoteUploadId: remoteUploadId,
                startedAt: startedAt,
                endedAt: endedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$AcquisitionSessionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback:
              ({
                stateTransitionsRefs = false,
                gpsPointsRefs = false,
                sensorWindowsRefs = false,
                syncJobsRefs = false,
              }) {
                return PrefetchHooks(
                  db: db,
                  explicitlyWatchedTables: [
                    if (stateTransitionsRefs) db.stateTransitions,
                    if (gpsPointsRefs) db.gpsPoints,
                    if (sensorWindowsRefs) db.sensorWindows,
                    if (syncJobsRefs) db.syncJobs,
                  ],
                  addJoins: null,
                  getPrefetchedDataCallback: (items) async {
                    return [
                      if (stateTransitionsRefs)
                        await $_getPrefetchedData<
                          AcquisitionSession,
                          $AcquisitionSessionsTable,
                          StateTransition
                        >(
                          currentTable: table,
                          referencedTable: $$AcquisitionSessionsTableReferences
                              ._stateTransitionsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AcquisitionSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).stateTransitionsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (gpsPointsRefs)
                        await $_getPrefetchedData<
                          AcquisitionSession,
                          $AcquisitionSessionsTable,
                          GpsPoint
                        >(
                          currentTable: table,
                          referencedTable: $$AcquisitionSessionsTableReferences
                              ._gpsPointsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AcquisitionSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).gpsPointsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (sensorWindowsRefs)
                        await $_getPrefetchedData<
                          AcquisitionSession,
                          $AcquisitionSessionsTable,
                          SensorWindow
                        >(
                          currentTable: table,
                          referencedTable: $$AcquisitionSessionsTableReferences
                              ._sensorWindowsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AcquisitionSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).sensorWindowsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.sessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                      if (syncJobsRefs)
                        await $_getPrefetchedData<
                          AcquisitionSession,
                          $AcquisitionSessionsTable,
                          SyncJob
                        >(
                          currentTable: table,
                          referencedTable: $$AcquisitionSessionsTableReferences
                              ._syncJobsRefsTable(db),
                          managerFromTypedResult: (p0) =>
                              $$AcquisitionSessionsTableReferences(
                                db,
                                table,
                                p0,
                              ).syncJobsRefs,
                          referencedItemsForCurrentItem:
                              (item, referencedItems) => referencedItems.where(
                                (e) => e.localSessionId == item.id,
                              ),
                          typedResults: items,
                        ),
                    ];
                  },
                );
              },
        ),
      );
}

typedef $$AcquisitionSessionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AcquisitionLocalDatabase,
      $AcquisitionSessionsTable,
      AcquisitionSession,
      $$AcquisitionSessionsTableFilterComposer,
      $$AcquisitionSessionsTableOrderingComposer,
      $$AcquisitionSessionsTableAnnotationComposer,
      $$AcquisitionSessionsTableCreateCompanionBuilder,
      $$AcquisitionSessionsTableUpdateCompanionBuilder,
      (AcquisitionSession, $$AcquisitionSessionsTableReferences),
      AcquisitionSession,
      PrefetchHooks Function({
        bool stateTransitionsRefs,
        bool gpsPointsRefs,
        bool sensorWindowsRefs,
        bool syncJobsRefs,
      })
    >;
typedef $$StateTransitionsTableCreateCompanionBuilder =
    StateTransitionsCompanion Function({
      Value<int> id,
      required String sessionId,
      required String fromState,
      required String toState,
      required DateTime timestamp,
      Value<double?> sigma,
      Value<double?> speedMps,
    });
typedef $$StateTransitionsTableUpdateCompanionBuilder =
    StateTransitionsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<String> fromState,
      Value<String> toState,
      Value<DateTime> timestamp,
      Value<double?> sigma,
      Value<double?> speedMps,
    });

final class $$StateTransitionsTableReferences
    extends
        BaseReferences<
          _$AcquisitionLocalDatabase,
          $StateTransitionsTable,
          StateTransition
        > {
  $$StateTransitionsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AcquisitionSessionsTable _sessionIdTable(
    _$AcquisitionLocalDatabase db,
  ) => db.acquisitionSessions.createAlias(
    'state_transitions__session_id__acquisition_sessions__id',
  );

  $$AcquisitionSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$AcquisitionSessionsTableTableManager(
      $_db,
      $_db.acquisitionSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$StateTransitionsTableFilterComposer
    extends Composer<_$AcquisitionLocalDatabase, $StateTransitionsTable> {
  $$StateTransitionsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fromState => $composableBuilder(
    column: $table.fromState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get toState => $composableBuilder(
    column: $table.toState,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get sigma => $composableBuilder(
    column: $table.sigma,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnFilters(column),
  );

  $$AcquisitionSessionsTableFilterComposer get sessionId {
    final $$AcquisitionSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.acquisitionSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcquisitionSessionsTableFilterComposer(
            $db: $db,
            $table: $db.acquisitionSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$StateTransitionsTableOrderingComposer
    extends Composer<_$AcquisitionLocalDatabase, $StateTransitionsTable> {
  $$StateTransitionsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fromState => $composableBuilder(
    column: $table.fromState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get toState => $composableBuilder(
    column: $table.toState,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get sigma => $composableBuilder(
    column: $table.sigma,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnOrderings(column),
  );

  $$AcquisitionSessionsTableOrderingComposer get sessionId {
    final $$AcquisitionSessionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableOrderingComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$StateTransitionsTableAnnotationComposer
    extends Composer<_$AcquisitionLocalDatabase, $StateTransitionsTable> {
  $$StateTransitionsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get fromState =>
      $composableBuilder(column: $table.fromState, builder: (column) => column);

  GeneratedColumn<String> get toState =>
      $composableBuilder(column: $table.toState, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get sigma =>
      $composableBuilder(column: $table.sigma, builder: (column) => column);

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  $$AcquisitionSessionsTableAnnotationComposer get sessionId {
    final $$AcquisitionSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$StateTransitionsTableTableManager
    extends
        RootTableManager<
          _$AcquisitionLocalDatabase,
          $StateTransitionsTable,
          StateTransition,
          $$StateTransitionsTableFilterComposer,
          $$StateTransitionsTableOrderingComposer,
          $$StateTransitionsTableAnnotationComposer,
          $$StateTransitionsTableCreateCompanionBuilder,
          $$StateTransitionsTableUpdateCompanionBuilder,
          (StateTransition, $$StateTransitionsTableReferences),
          StateTransition,
          PrefetchHooks Function({bool sessionId})
        > {
  $$StateTransitionsTableTableManager(
    _$AcquisitionLocalDatabase db,
    $StateTransitionsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$StateTransitionsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$StateTransitionsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$StateTransitionsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<String> fromState = const Value.absent(),
                Value<String> toState = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<double?> sigma = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
              }) => StateTransitionsCompanion(
                id: id,
                sessionId: sessionId,
                fromState: fromState,
                toState: toState,
                timestamp: timestamp,
                sigma: sigma,
                speedMps: speedMps,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required String fromState,
                required String toState,
                required DateTime timestamp,
                Value<double?> sigma = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
              }) => StateTransitionsCompanion.insert(
                id: id,
                sessionId: sessionId,
                fromState: fromState,
                toState: toState,
                timestamp: timestamp,
                sigma: sigma,
                speedMps: speedMps,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$StateTransitionsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable:
                                    $$StateTransitionsTableReferences
                                        ._sessionIdTable(db),
                                referencedColumn:
                                    $$StateTransitionsTableReferences
                                        ._sessionIdTable(db)
                                        .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$StateTransitionsTableProcessedTableManager =
    ProcessedTableManager<
      _$AcquisitionLocalDatabase,
      $StateTransitionsTable,
      StateTransition,
      $$StateTransitionsTableFilterComposer,
      $$StateTransitionsTableOrderingComposer,
      $$StateTransitionsTableAnnotationComposer,
      $$StateTransitionsTableCreateCompanionBuilder,
      $$StateTransitionsTableUpdateCompanionBuilder,
      (StateTransition, $$StateTransitionsTableReferences),
      StateTransition,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$GpsPointsTableCreateCompanionBuilder =
    GpsPointsCompanion Function({
      Value<int> id,
      required String sessionId,
      required double latitude,
      required double longitude,
      required DateTime timestamp,
      Value<double?> speedMps,
      Value<double?> accuracyMeters,
    });
typedef $$GpsPointsTableUpdateCompanionBuilder =
    GpsPointsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<double> latitude,
      Value<double> longitude,
      Value<DateTime> timestamp,
      Value<double?> speedMps,
      Value<double?> accuracyMeters,
    });

final class $$GpsPointsTableReferences
    extends
        BaseReferences<_$AcquisitionLocalDatabase, $GpsPointsTable, GpsPoint> {
  $$GpsPointsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AcquisitionSessionsTable _sessionIdTable(
    _$AcquisitionLocalDatabase db,
  ) => db.acquisitionSessions.createAlias(
    'gps_points__session_id__acquisition_sessions__id',
  );

  $$AcquisitionSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$AcquisitionSessionsTableTableManager(
      $_db,
      $_db.acquisitionSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$GpsPointsTableFilterComposer
    extends Composer<_$AcquisitionLocalDatabase, $GpsPointsTable> {
  $$GpsPointsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => ColumnFilters(column),
  );

  $$AcquisitionSessionsTableFilterComposer get sessionId {
    final $$AcquisitionSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.acquisitionSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcquisitionSessionsTableFilterComposer(
            $db: $db,
            $table: $db.acquisitionSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$GpsPointsTableOrderingComposer
    extends Composer<_$AcquisitionLocalDatabase, $GpsPointsTable> {
  $$GpsPointsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get latitude => $composableBuilder(
    column: $table.latitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get longitude => $composableBuilder(
    column: $table.longitude,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get timestamp => $composableBuilder(
    column: $table.timestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get speedMps => $composableBuilder(
    column: $table.speedMps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => ColumnOrderings(column),
  );

  $$AcquisitionSessionsTableOrderingComposer get sessionId {
    final $$AcquisitionSessionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableOrderingComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$GpsPointsTableAnnotationComposer
    extends Composer<_$AcquisitionLocalDatabase, $GpsPointsTable> {
  $$GpsPointsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<double> get latitude =>
      $composableBuilder(column: $table.latitude, builder: (column) => column);

  GeneratedColumn<double> get longitude =>
      $composableBuilder(column: $table.longitude, builder: (column) => column);

  GeneratedColumn<DateTime> get timestamp =>
      $composableBuilder(column: $table.timestamp, builder: (column) => column);

  GeneratedColumn<double> get speedMps =>
      $composableBuilder(column: $table.speedMps, builder: (column) => column);

  GeneratedColumn<double> get accuracyMeters => $composableBuilder(
    column: $table.accuracyMeters,
    builder: (column) => column,
  );

  $$AcquisitionSessionsTableAnnotationComposer get sessionId {
    final $$AcquisitionSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$GpsPointsTableTableManager
    extends
        RootTableManager<
          _$AcquisitionLocalDatabase,
          $GpsPointsTable,
          GpsPoint,
          $$GpsPointsTableFilterComposer,
          $$GpsPointsTableOrderingComposer,
          $$GpsPointsTableAnnotationComposer,
          $$GpsPointsTableCreateCompanionBuilder,
          $$GpsPointsTableUpdateCompanionBuilder,
          (GpsPoint, $$GpsPointsTableReferences),
          GpsPoint,
          PrefetchHooks Function({bool sessionId})
        > {
  $$GpsPointsTableTableManager(
    _$AcquisitionLocalDatabase db,
    $GpsPointsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GpsPointsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GpsPointsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GpsPointsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<double> latitude = const Value.absent(),
                Value<double> longitude = const Value.absent(),
                Value<DateTime> timestamp = const Value.absent(),
                Value<double?> speedMps = const Value.absent(),
                Value<double?> accuracyMeters = const Value.absent(),
              }) => GpsPointsCompanion(
                id: id,
                sessionId: sessionId,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
                speedMps: speedMps,
                accuracyMeters: accuracyMeters,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required double latitude,
                required double longitude,
                required DateTime timestamp,
                Value<double?> speedMps = const Value.absent(),
                Value<double?> accuracyMeters = const Value.absent(),
              }) => GpsPointsCompanion.insert(
                id: id,
                sessionId: sessionId,
                latitude: latitude,
                longitude: longitude,
                timestamp: timestamp,
                speedMps: speedMps,
                accuracyMeters: accuracyMeters,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$GpsPointsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$GpsPointsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$GpsPointsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$GpsPointsTableProcessedTableManager =
    ProcessedTableManager<
      _$AcquisitionLocalDatabase,
      $GpsPointsTable,
      GpsPoint,
      $$GpsPointsTableFilterComposer,
      $$GpsPointsTableOrderingComposer,
      $$GpsPointsTableAnnotationComposer,
      $$GpsPointsTableCreateCompanionBuilder,
      $$GpsPointsTableUpdateCompanionBuilder,
      (GpsPoint, $$GpsPointsTableReferences),
      GpsPoint,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$SensorWindowsTableCreateCompanionBuilder =
    SensorWindowsCompanion Function({
      Value<int> id,
      required String sessionId,
      required DateTime startTimestamp,
      required DateTime endTimestamp,
      required int sampleCount,
      required int frequencyHz,
      required String matrixJson,
    });
typedef $$SensorWindowsTableUpdateCompanionBuilder =
    SensorWindowsCompanion Function({
      Value<int> id,
      Value<String> sessionId,
      Value<DateTime> startTimestamp,
      Value<DateTime> endTimestamp,
      Value<int> sampleCount,
      Value<int> frequencyHz,
      Value<String> matrixJson,
    });

final class $$SensorWindowsTableReferences
    extends
        BaseReferences<
          _$AcquisitionLocalDatabase,
          $SensorWindowsTable,
          SensorWindow
        > {
  $$SensorWindowsTableReferences(
    super.$_db,
    super.$_table,
    super.$_typedResult,
  );

  static $AcquisitionSessionsTable _sessionIdTable(
    _$AcquisitionLocalDatabase db,
  ) => db.acquisitionSessions.createAlias(
    'sensor_windows__session_id__acquisition_sessions__id',
  );

  $$AcquisitionSessionsTableProcessedTableManager get sessionId {
    final $_column = $_itemColumn<String>('session_id')!;

    final manager = $$AcquisitionSessionsTableTableManager(
      $_db,
      $_db.acquisitionSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_sessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SensorWindowsTableFilterComposer
    extends Composer<_$AcquisitionLocalDatabase, $SensorWindowsTable> {
  $$SensorWindowsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get startTimestamp => $composableBuilder(
    column: $table.startTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get endTimestamp => $composableBuilder(
    column: $table.endTimestamp,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get frequencyHz => $composableBuilder(
    column: $table.frequencyHz,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get matrixJson => $composableBuilder(
    column: $table.matrixJson,
    builder: (column) => ColumnFilters(column),
  );

  $$AcquisitionSessionsTableFilterComposer get sessionId {
    final $$AcquisitionSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.sessionId,
      referencedTable: $db.acquisitionSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcquisitionSessionsTableFilterComposer(
            $db: $db,
            $table: $db.acquisitionSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SensorWindowsTableOrderingComposer
    extends Composer<_$AcquisitionLocalDatabase, $SensorWindowsTable> {
  $$SensorWindowsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get startTimestamp => $composableBuilder(
    column: $table.startTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get endTimestamp => $composableBuilder(
    column: $table.endTimestamp,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get frequencyHz => $composableBuilder(
    column: $table.frequencyHz,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get matrixJson => $composableBuilder(
    column: $table.matrixJson,
    builder: (column) => ColumnOrderings(column),
  );

  $$AcquisitionSessionsTableOrderingComposer get sessionId {
    final $$AcquisitionSessionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableOrderingComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$SensorWindowsTableAnnotationComposer
    extends Composer<_$AcquisitionLocalDatabase, $SensorWindowsTable> {
  $$SensorWindowsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<DateTime> get startTimestamp => $composableBuilder(
    column: $table.startTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<DateTime> get endTimestamp => $composableBuilder(
    column: $table.endTimestamp,
    builder: (column) => column,
  );

  GeneratedColumn<int> get sampleCount => $composableBuilder(
    column: $table.sampleCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get frequencyHz => $composableBuilder(
    column: $table.frequencyHz,
    builder: (column) => column,
  );

  GeneratedColumn<String> get matrixJson => $composableBuilder(
    column: $table.matrixJson,
    builder: (column) => column,
  );

  $$AcquisitionSessionsTableAnnotationComposer get sessionId {
    final $$AcquisitionSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.sessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$SensorWindowsTableTableManager
    extends
        RootTableManager<
          _$AcquisitionLocalDatabase,
          $SensorWindowsTable,
          SensorWindow,
          $$SensorWindowsTableFilterComposer,
          $$SensorWindowsTableOrderingComposer,
          $$SensorWindowsTableAnnotationComposer,
          $$SensorWindowsTableCreateCompanionBuilder,
          $$SensorWindowsTableUpdateCompanionBuilder,
          (SensorWindow, $$SensorWindowsTableReferences),
          SensorWindow,
          PrefetchHooks Function({bool sessionId})
        > {
  $$SensorWindowsTableTableManager(
    _$AcquisitionLocalDatabase db,
    $SensorWindowsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SensorWindowsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SensorWindowsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SensorWindowsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> sessionId = const Value.absent(),
                Value<DateTime> startTimestamp = const Value.absent(),
                Value<DateTime> endTimestamp = const Value.absent(),
                Value<int> sampleCount = const Value.absent(),
                Value<int> frequencyHz = const Value.absent(),
                Value<String> matrixJson = const Value.absent(),
              }) => SensorWindowsCompanion(
                id: id,
                sessionId: sessionId,
                startTimestamp: startTimestamp,
                endTimestamp: endTimestamp,
                sampleCount: sampleCount,
                frequencyHz: frequencyHz,
                matrixJson: matrixJson,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String sessionId,
                required DateTime startTimestamp,
                required DateTime endTimestamp,
                required int sampleCount,
                required int frequencyHz,
                required String matrixJson,
              }) => SensorWindowsCompanion.insert(
                id: id,
                sessionId: sessionId,
                startTimestamp: startTimestamp,
                endTimestamp: endTimestamp,
                sampleCount: sampleCount,
                frequencyHz: frequencyHz,
                matrixJson: matrixJson,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SensorWindowsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({sessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (sessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.sessionId,
                                referencedTable: $$SensorWindowsTableReferences
                                    ._sessionIdTable(db),
                                referencedColumn: $$SensorWindowsTableReferences
                                    ._sessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SensorWindowsTableProcessedTableManager =
    ProcessedTableManager<
      _$AcquisitionLocalDatabase,
      $SensorWindowsTable,
      SensorWindow,
      $$SensorWindowsTableFilterComposer,
      $$SensorWindowsTableOrderingComposer,
      $$SensorWindowsTableAnnotationComposer,
      $$SensorWindowsTableCreateCompanionBuilder,
      $$SensorWindowsTableUpdateCompanionBuilder,
      (SensorWindow, $$SensorWindowsTableReferences),
      SensorWindow,
      PrefetchHooks Function({bool sessionId})
    >;
typedef $$SyncJobsTableCreateCompanionBuilder =
    SyncJobsCompanion Function({
      Value<int> id,
      required String localSessionId,
      Value<int?> remoteUploadId,
      Value<int?> remoteTripId,
      Value<int> corePayloadSizeBytes,
      Value<bool> coreMapAvailable,
      Value<String> coreStatus,
      Value<String> rawStatus,
      Value<int> attempts,
      Value<DateTime?> nextRetryAt,
      Value<String?> lastError,
      required DateTime createdAt,
      required DateTime updatedAt,
    });
typedef $$SyncJobsTableUpdateCompanionBuilder =
    SyncJobsCompanion Function({
      Value<int> id,
      Value<String> localSessionId,
      Value<int?> remoteUploadId,
      Value<int?> remoteTripId,
      Value<int> corePayloadSizeBytes,
      Value<bool> coreMapAvailable,
      Value<String> coreStatus,
      Value<String> rawStatus,
      Value<int> attempts,
      Value<DateTime?> nextRetryAt,
      Value<String?> lastError,
      Value<DateTime> createdAt,
      Value<DateTime> updatedAt,
    });

final class $$SyncJobsTableReferences
    extends
        BaseReferences<_$AcquisitionLocalDatabase, $SyncJobsTable, SyncJob> {
  $$SyncJobsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $AcquisitionSessionsTable _localSessionIdTable(
    _$AcquisitionLocalDatabase db,
  ) => db.acquisitionSessions.createAlias(
    'sync_jobs__local_session_id__acquisition_sessions__id',
  );

  $$AcquisitionSessionsTableProcessedTableManager get localSessionId {
    final $_column = $_itemColumn<String>('local_session_id')!;

    final manager = $$AcquisitionSessionsTableTableManager(
      $_db,
      $_db.acquisitionSessions,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_localSessionIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$SyncJobsTableFilterComposer
    extends Composer<_$AcquisitionLocalDatabase, $SyncJobsTable> {
  $$SyncJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteUploadId => $composableBuilder(
    column: $table.remoteUploadId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get remoteTripId => $composableBuilder(
    column: $table.remoteTripId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get corePayloadSizeBytes => $composableBuilder(
    column: $table.corePayloadSizeBytes,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get coreMapAvailable => $composableBuilder(
    column: $table.coreMapAvailable,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get coreStatus => $composableBuilder(
    column: $table.coreStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rawStatus => $composableBuilder(
    column: $table.rawStatus,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$AcquisitionSessionsTableFilterComposer get localSessionId {
    final $$AcquisitionSessionsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.localSessionId,
      referencedTable: $db.acquisitionSessions,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$AcquisitionSessionsTableFilterComposer(
            $db: $db,
            $table: $db.acquisitionSessions,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$SyncJobsTableOrderingComposer
    extends Composer<_$AcquisitionLocalDatabase, $SyncJobsTable> {
  $$SyncJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteUploadId => $composableBuilder(
    column: $table.remoteUploadId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get remoteTripId => $composableBuilder(
    column: $table.remoteTripId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get corePayloadSizeBytes => $composableBuilder(
    column: $table.corePayloadSizeBytes,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get coreMapAvailable => $composableBuilder(
    column: $table.coreMapAvailable,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get coreStatus => $composableBuilder(
    column: $table.coreStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rawStatus => $composableBuilder(
    column: $table.rawStatus,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get attempts => $composableBuilder(
    column: $table.attempts,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastError => $composableBuilder(
    column: $table.lastError,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$AcquisitionSessionsTableOrderingComposer get localSessionId {
    final $$AcquisitionSessionsTableOrderingComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localSessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableOrderingComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$SyncJobsTableAnnotationComposer
    extends Composer<_$AcquisitionLocalDatabase, $SyncJobsTable> {
  $$SyncJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get remoteUploadId => $composableBuilder(
    column: $table.remoteUploadId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get remoteTripId => $composableBuilder(
    column: $table.remoteTripId,
    builder: (column) => column,
  );

  GeneratedColumn<int> get corePayloadSizeBytes => $composableBuilder(
    column: $table.corePayloadSizeBytes,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get coreMapAvailable => $composableBuilder(
    column: $table.coreMapAvailable,
    builder: (column) => column,
  );

  GeneratedColumn<String> get coreStatus => $composableBuilder(
    column: $table.coreStatus,
    builder: (column) => column,
  );

  GeneratedColumn<String> get rawStatus =>
      $composableBuilder(column: $table.rawStatus, builder: (column) => column);

  GeneratedColumn<int> get attempts =>
      $composableBuilder(column: $table.attempts, builder: (column) => column);

  GeneratedColumn<DateTime> get nextRetryAt => $composableBuilder(
    column: $table.nextRetryAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get lastError =>
      $composableBuilder(column: $table.lastError, builder: (column) => column);

  GeneratedColumn<DateTime> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<DateTime> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$AcquisitionSessionsTableAnnotationComposer get localSessionId {
    final $$AcquisitionSessionsTableAnnotationComposer composer =
        $composerBuilder(
          composer: this,
          getCurrentColumn: (t) => t.localSessionId,
          referencedTable: $db.acquisitionSessions,
          getReferencedColumn: (t) => t.id,
          builder:
              (
                joinBuilder, {
                $addJoinBuilderToRootComposer,
                $removeJoinBuilderFromRootComposer,
              }) => $$AcquisitionSessionsTableAnnotationComposer(
                $db: $db,
                $table: $db.acquisitionSessions,
                $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
                joinBuilder: joinBuilder,
                $removeJoinBuilderFromRootComposer:
                    $removeJoinBuilderFromRootComposer,
              ),
        );
    return composer;
  }
}

class $$SyncJobsTableTableManager
    extends
        RootTableManager<
          _$AcquisitionLocalDatabase,
          $SyncJobsTable,
          SyncJob,
          $$SyncJobsTableFilterComposer,
          $$SyncJobsTableOrderingComposer,
          $$SyncJobsTableAnnotationComposer,
          $$SyncJobsTableCreateCompanionBuilder,
          $$SyncJobsTableUpdateCompanionBuilder,
          (SyncJob, $$SyncJobsTableReferences),
          SyncJob,
          PrefetchHooks Function({bool localSessionId})
        > {
  $$SyncJobsTableTableManager(
    _$AcquisitionLocalDatabase db,
    $SyncJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> localSessionId = const Value.absent(),
                Value<int?> remoteUploadId = const Value.absent(),
                Value<int?> remoteTripId = const Value.absent(),
                Value<int> corePayloadSizeBytes = const Value.absent(),
                Value<bool> coreMapAvailable = const Value.absent(),
                Value<String> coreStatus = const Value.absent(),
                Value<String> rawStatus = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                Value<DateTime> createdAt = const Value.absent(),
                Value<DateTime> updatedAt = const Value.absent(),
              }) => SyncJobsCompanion(
                id: id,
                localSessionId: localSessionId,
                remoteUploadId: remoteUploadId,
                remoteTripId: remoteTripId,
                corePayloadSizeBytes: corePayloadSizeBytes,
                coreMapAvailable: coreMapAvailable,
                coreStatus: coreStatus,
                rawStatus: rawStatus,
                attempts: attempts,
                nextRetryAt: nextRetryAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String localSessionId,
                Value<int?> remoteUploadId = const Value.absent(),
                Value<int?> remoteTripId = const Value.absent(),
                Value<int> corePayloadSizeBytes = const Value.absent(),
                Value<bool> coreMapAvailable = const Value.absent(),
                Value<String> coreStatus = const Value.absent(),
                Value<String> rawStatus = const Value.absent(),
                Value<int> attempts = const Value.absent(),
                Value<DateTime?> nextRetryAt = const Value.absent(),
                Value<String?> lastError = const Value.absent(),
                required DateTime createdAt,
                required DateTime updatedAt,
              }) => SyncJobsCompanion.insert(
                id: id,
                localSessionId: localSessionId,
                remoteUploadId: remoteUploadId,
                remoteTripId: remoteTripId,
                corePayloadSizeBytes: corePayloadSizeBytes,
                coreMapAvailable: coreMapAvailable,
                coreStatus: coreStatus,
                rawStatus: rawStatus,
                attempts: attempts,
                nextRetryAt: nextRetryAt,
                lastError: lastError,
                createdAt: createdAt,
                updatedAt: updatedAt,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable(table),
                  $$SyncJobsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({localSessionId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (localSessionId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.localSessionId,
                                referencedTable: $$SyncJobsTableReferences
                                    ._localSessionIdTable(db),
                                referencedColumn: $$SyncJobsTableReferences
                                    ._localSessionIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$SyncJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AcquisitionLocalDatabase,
      $SyncJobsTable,
      SyncJob,
      $$SyncJobsTableFilterComposer,
      $$SyncJobsTableOrderingComposer,
      $$SyncJobsTableAnnotationComposer,
      $$SyncJobsTableCreateCompanionBuilder,
      $$SyncJobsTableUpdateCompanionBuilder,
      (SyncJob, $$SyncJobsTableReferences),
      SyncJob,
      PrefetchHooks Function({bool localSessionId})
    >;

class $AcquisitionLocalDatabaseManager {
  final _$AcquisitionLocalDatabase _db;
  $AcquisitionLocalDatabaseManager(this._db);
  $$AcquisitionSessionsTableTableManager get acquisitionSessions =>
      $$AcquisitionSessionsTableTableManager(_db, _db.acquisitionSessions);
  $$StateTransitionsTableTableManager get stateTransitions =>
      $$StateTransitionsTableTableManager(_db, _db.stateTransitions);
  $$GpsPointsTableTableManager get gpsPoints =>
      $$GpsPointsTableTableManager(_db, _db.gpsPoints);
  $$SensorWindowsTableTableManager get sensorWindows =>
      $$SensorWindowsTableTableManager(_db, _db.sensorWindows);
  $$SyncJobsTableTableManager get syncJobs =>
      $$SyncJobsTableTableManager(_db, _db.syncJobs);
}

import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

typedef DiagnosticsDirectoryProvider = Future<Directory> Function();

/// Registra una riga JSON per ogni decisione della FSM senza bloccare il flusso
/// dei sensori. Coordinate e identificativo del dispositivo non vengono scritti.
class FsmDiagnosticsRecorder {
  static const String consolePrefix = '[DEBUG-FSM-SENSITIVITY-c91d]';

  final DiagnosticsDirectoryProvider _directoryProvider;
  final bool _mirrorToConsole;

  IOSink? _sink;
  File? _file;
  String? _sessionId;
  DateTime? _startedAt;
  int _decisionCount = 0;
  Object? _writeFailure;

  FsmDiagnosticsRecorder({
    DiagnosticsDirectoryProvider? directoryProvider,
    bool mirrorToConsole = true,
  })  : _directoryProvider = directoryProvider ?? _defaultDirectory,
        _mirrorToConsole = mirrorToConsole;

  static Future<Directory> _defaultDirectory() async {
    final documents = await getApplicationDocumentsDirectory();
    return Directory(path.join(documents.path, 'fsm_diagnostics'));
  }

  Future<void> start({
    required String sessionId,
    required DateTime startedAt,
    bool append = false,
  }) async {
    await _closeSink();
    _sessionId = sessionId;
    _startedAt = startedAt.toUtc();
    _decisionCount = 0;
    _writeFailure = null;

    try {
      final directory = await _directoryProvider();
      await directory.create(recursive: true);
      final safeSessionId =
          sessionId.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
      final file = File(
        path.join(directory.path, 'fsm-diagnostics-$safeSessionId.jsonl'),
      );
      if (!append && await file.exists()) {
        await file.writeAsString('');
      }
      final alreadyExists = await file.exists() && await file.length() > 0;
      if (alreadyExists && append) {
        _decisionCount = (await file.readAsLines())
            .where((line) => line.contains('"type":"fsm_decision"'))
            .length;
      }
      _file = file;
      _sink = file.openWrite(mode: FileMode.append);
      _writeRow({
        'type':
            alreadyExists && append ? 'recording_resumed' : 'recording_started',
        'session_id': sessionId,
        'timestamp': startedAt.toUtc().toIso8601String(),
        'schema_version': 1,
      });
    } catch (error, stackTrace) {
      _writeFailure = error;
      _file = null;
      _sink = null;
      _logFailure('Impossibile avviare il file diagnostico', error, stackTrace);
    }
  }

  void record({
    required TrackingEvent event,
    required FsmDecision decision,
    required FsmConfig config,
  }) {
    final diagnostics = decision.diagnostics;
    final sigmaAge = diagnostics.sigmaAge;
    final gpsAge = diagnostics.gpsSpeedAge;
    final sigmaFresh =
        sigmaAge != null && sigmaAge <= config.motionSigmaFreshness;
    final gpsFresh = gpsAge != null && gpsAge <= config.gpsSpeedFreshness;
    final row = <String, Object?>{
      'type': 'fsm_decision',
      'session_id': _sessionId,
      'event': switch (event) {
        MotionWindowEvaluated() => 'motion_window',
        GpsFixReceived() => 'gps_fix',
      },
      'timestamp': event.timestamp.toUtc().toIso8601String(),
      'mode': diagnostics.evidenceMode.name,
      'state_before': diagnostics.previousState.name,
      'state_after': decision.state.name,
      'evidence': diagnostics.evidence.name,
      'sigma': diagnostics.sigma,
      'sigma_age_ms': sigmaAge?.inMilliseconds,
      'sigma_fresh': sigmaFresh,
      'sigma_stationary':
          diagnostics.sigma < config.stationaryMotionSigmaThreshold,
      'gps_mps': diagnostics.gpsSpeedMetersPerSecond,
      'gps_age_ms': gpsAge?.inMilliseconds,
      'gps_fresh': gpsFresh,
      'gps_stationary': diagnostics.gpsSpeedMetersPerSecond <
          config.stationaryGpsSpeedThresholdMps,
      'timer_action': diagnostics.stationaryTimerAction.name,
      'stationary_elapsed_ms':
          diagnostics.stationaryEvidenceElapsed?.inMilliseconds,
      'stationary_required_ms':
          config.stationaryEvidenceRequired.inMilliseconds,
      'transition': decision.didTransition,
    };

    _decisionCount++;
    _writeRow(row);
    if (_mirrorToConsole && kDebugMode) {
      developer.log(
        '$consolePrefix ${jsonEncode(row)}',
        name: 'mobility_diary.fsm_sensitivity',
      );
    }
  }

  Future<AcquisitionDiagnosticsReport?> finish({
    required DateTime endedAt,
  }) async {
    final file = _file;
    final sessionId = _sessionId;
    final startedAt = _startedAt;
    if (file == null || sessionId == null || startedAt == null) {
      await _closeSink();
      return null;
    }

    _writeRow({
      'type': 'recording_stopped',
      'session_id': sessionId,
      'timestamp': endedAt.toUtc().toIso8601String(),
      'decision_count': _decisionCount,
      if (_writeFailure != null) 'write_error': _writeFailure.toString(),
    });

    try {
      await _closeSink();
      final content = await file.readAsString();
      final report = AcquisitionDiagnosticsReport(
        sessionId: sessionId,
        filePath: file.path,
        fileName: path.basename(file.path),
        content: content,
        sizeBytes: await file.length(),
        decisionCount: _decisionCount,
        startedAt: startedAt,
        endedAt: endedAt.toUtc(),
      );
      _clearSession();
      return report;
    } catch (error, stackTrace) {
      _logFailure(
          'Impossibile finalizzare il file diagnostico', error, stackTrace);
      _clearSession();
      return null;
    }
  }

  void _writeRow(Map<String, Object?> row) {
    final sink = _sink;
    if (sink == null || _writeFailure != null) {
      return;
    }
    try {
      sink.writeln(jsonEncode(row));
    } catch (error, stackTrace) {
      _writeFailure = error;
      _logFailure('Scrittura diagnostica fallita', error, stackTrace);
    }
  }

  Future<void> _closeSink() async {
    final sink = _sink;
    _sink = null;
    if (sink == null) return;
    try {
      await sink.flush();
      await sink.close();
    } catch (error, stackTrace) {
      _writeFailure ??= error;
      _logFailure('Chiusura file diagnostico fallita', error, stackTrace);
    }
  }

  void dispose() {
    _sink?.close();
    _sink = null;
  }

  void _clearSession() {
    _file = null;
    _sessionId = null;
    _startedAt = null;
    _decisionCount = 0;
    _writeFailure = null;
  }

  void _logFailure(String message, Object error, StackTrace stackTrace) {
    developer.log(
      message,
      name: 'mobility_diary.fsm_sensitivity',
      error: error,
      stackTrace: stackTrace,
    );
  }
}

import 'dart:io';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/repositories/impl/acquisition/fsm_diagnostics_recorder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('records FSM decisions without precise location and finalizes the file',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'mobility-diary-fsm-diagnostics-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final recorder = FsmDiagnosticsRecorder(
      directoryProvider: () async => directory,
      mirrorToConsole: false,
    );
    final startedAt = DateTime.utc(2026, 9, 4, 10);
    final event = GpsFixReceived(
      timestamp: startedAt.add(const Duration(seconds: 1)),
      latitude: 45.4642,
      longitude: 9.19,
      speedMetersPerSecond: 0.2,
      accuracyMeters: 4,
    );
    final decision = AcquisitionFsm().apply(event);

    await recorder.start(
        sessionId: 'session/with unsafe chars', startedAt: startedAt);
    recorder.record(
        event: event, decision: decision, config: const FsmConfig());
    final report = await recorder.finish(
      endedAt: startedAt.add(const Duration(seconds: 2)),
    );

    expect(report, isNotNull);
    expect(report!.fileName, matches(r'^fsm-diagnostics-.+\.jsonl$'));
    expect(await File(report.filePath).exists(), isTrue);
    expect(report.decisionCount, 1);
    expect(report.content, contains('"type":"fsm_decision"'));
    expect(report.content, contains('"evidence":"uncertain"'));
    expect(report.content, contains('"platform_speed_mps":0.2'));
    expect(report.content, contains('"speed_valid":true'));
    expect(
        report.content, contains('"session_id":"session/with unsafe chars"'));
    expect(report.content, isNot(contains('45.4642')));
    expect(report.content, isNot(contains('9.19')));
    expect(report.content, isNot(contains('latitude')));
    expect(report.content, isNot(contains('longitude')));
  });

  test('continues the same file when an active session is restored', () async {
    final directory = await Directory.systemTemp.createTemp(
      'mobility-diary-fsm-resume-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final startedAt = DateTime.utc(2026, 9, 4, 10);
    final event = GpsFixReceived(
      timestamp: startedAt.add(const Duration(seconds: 1)),
      speedMetersPerSecond: 1,
    );
    final decision = AcquisitionFsm().apply(event);
    final firstRecorder = FsmDiagnosticsRecorder(
      directoryProvider: () async => directory,
      mirrorToConsole: false,
    );
    await firstRecorder.start(sessionId: 'session-id', startedAt: startedAt);
    firstRecorder.record(
      event: event,
      decision: decision,
      config: const FsmConfig(),
    );
    await firstRecorder.finish(
      endedAt: startedAt.add(const Duration(seconds: 2)),
    );

    final resumedRecorder = FsmDiagnosticsRecorder(
      directoryProvider: () async => directory,
      mirrorToConsole: false,
    );
    await resumedRecorder.start(
      sessionId: 'session-id',
      startedAt: startedAt,
      append: true,
    );
    resumedRecorder.record(
      event: event,
      decision: decision,
      config: const FsmConfig(),
    );
    final report = await resumedRecorder.finish(
      endedAt: startedAt.add(const Duration(seconds: 3)),
    );

    expect(report!.decisionCount, 2);
    expect(report.content, contains('"type":"recording_resumed"'));
    expect(
      '"type":"fsm_decision"'.allMatches(report.content),
      hasLength(2),
    );
  });

  test('records a rejected platform speed without treating it as zero',
      () async {
    final directory = await Directory.systemTemp.createTemp(
      'mobility-diary-invalid-speed-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final timestamp = DateTime.utc(2026, 9, 4, 10);
    final event = GpsFixReceived.fromPlatform(
      timestamp: timestamp,
      latitude: 45,
      longitude: 9,
      accuracyMeters: 5,
      platformSpeedMetersPerSecond: -1,
    );
    final recorder = FsmDiagnosticsRecorder(
      directoryProvider: () async => directory,
      mirrorToConsole: false,
    );
    final decision = AcquisitionFsm().apply(event);

    await recorder.start(sessionId: 'session-id', startedAt: timestamp);
    recorder.record(
      event: event,
      decision: decision,
      config: const FsmConfig(),
    );
    final report = await recorder.finish(endedAt: timestamp);

    expect(report!.content, contains('"platform_speed_mps":-1.0'));
    expect(report.content, contains('"speed_valid":false'));
    expect(decision.diagnostics.gpsSpeedAge, isNull);
  });
}

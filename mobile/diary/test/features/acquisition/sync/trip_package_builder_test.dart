import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/sensor_matrix_blob.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AcquisitionLocalDatabase database;
  late Directory tempDir;

  setUp(() async {
    database = AcquisitionLocalDatabase(NativeDatabase.memory());
    tempDir = await Directory.systemTemp.createTemp('trip_pkg_test');
  });

  tearDown(() async {
    await database.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  Future<void> seedSession(String id) async {
    final dao = database.acquisitionDao;
    await dao.createSession(
      id: id,
      deviceId: 'dev',
      startedAt: DateTime.utc(2026, 6, 12, 10),
    );
    await dao.endSession(id: id, endedAt: DateTime.utc(2026, 6, 12, 10, 35));
    await dao.insertGpsPoint(
      sessionId: id,
      latitude: 45.4642,
      longitude: 9.19,
      timestamp: DateTime.utc(2026, 6, 12, 10, 0, 3),
      speedMps: 3.2,
      accuracyMeters: 12,
    );
    await dao.insertTransition(
      sessionId: id,
      fromState: 'STATIONARY',
      toState: 'MOVEMENT',
      reason: 'movement_sigma_above_threshold',
      timestamp: DateTime.utc(2026, 6, 12, 10, 1, 10),
      sigma: 1.2,
      speedMps: 0.8,
    );
  }

  Future<void> seedWindows(String id, int count) async {
    final dao = database.acquisitionDao;
    for (var i = 0; i < count; i += 1) {
      await dao.insertSensorWindow(
        sessionId: id,
        startTimestamp: DateTime.utc(2026, 6, 12, 10, 2, i * 5),
        endTimestamp: DateTime.utc(2026, 6, 12, 10, 2, i * 5 + 5),
        sampleCount: 1,
        frequencyHz: 100,
        matrixBlob: encodeSensorMatrixJsonToBlob(
          '[[0.1,0.2,9.7,0.01,0.02,0.03,20.1,12.2,40.0]]',
        ),
      );
    }
  }

  TripPackageBuilder builder({int budget = 12 * 1024 * 1024}) {
    return TripPackageBuilder(
      dao: database.acquisitionDao,
      baseDirProvider: () async => tempDir,
      sensorWindowsPartBudgetBytes: budget,
    );
  }

  test('builds deterministic inline core and raw sensor window blobs',
      () async {
    await seedSession('s1');
    await seedWindows('s1', 1);

    final pkg = await builder().build('s1');

    // Le parti core (gps_points/state_transitions) sono sempre costruite
    // insieme al payload inline: fallback per quando il core e' troppo
    // grande per l'inline (413) — vedi TripSyncQueueImpl.
    expect(pkg.expectedCoreParts, {'gps_points': 1, 'state_transitions': 1});
    expect(pkg.expectedRawParts, {'sensor_windows': 1});
    expect(pkg.startedAt, DateTime.utc(2026, 6, 12, 10));
    expect(pkg.endedAt, DateTime.utc(2026, 6, 12, 10, 35));
    expect(pkg.corePayload, isNotNull);

    final coreBody = pkg.corePayload!.requestBody;
    expect(coreBody['client_session_id'], 's1');
    expect(coreBody['started_at'], '2026-06-12T10:00:00Z');
    expect(coreBody['ended_at'], '2026-06-12T10:35:00Z');
    expect(coreBody['expected_raw_parts'], {'sensor_windows': 1});
    final points = coreBody['gps_points'] as List<dynamic>;
    expect(points, hasLength(1));
    expect((points.first as Map)['latitude'], 45.4642);
    expect((points.first as Map)['speed_mps'], 3.2);
    final transitions = coreBody['state_transitions'] as List<dynamic>;
    expect(transitions, hasLength(1));
    expect((transitions.first as Map)['to_state'], 'MOVEMENT');
    expect(coreBody['core_payload_sha256'], pkg.corePayload!.sha256);
    expect(
        pkg.corePayload!.sizeBytes, utf8.encode(jsonEncode(coreBody)).length);

    // Le parti core rispecchiano esattamente il contenuto del payload
    // inline, solo incapsulate come blob gzip per l'upload presigned.
    final gpsPart = pkg.coreParts.singleWhere((p) => p.kind == 'gps_points');
    expect(gpsPart.file.path, endsWith('gps_points.json.gz'));
    final gpsDecoded = jsonDecode(
      utf8.decode(gzip.decode(await gpsPart.file.readAsBytes())),
    ) as Map<String, dynamic>;
    expect(gpsDecoded['points'], points);

    final transitionsPart =
        pkg.coreParts.singleWhere((p) => p.kind == 'state_transitions');
    expect(transitionsPart.file.path, endsWith('state_transitions.json.gz'));
    final transitionsDecoded = jsonDecode(
      utf8.decode(gzip.decode(await transitionsPart.file.readAsBytes())),
    ) as Map<String, dynamic>;
    expect(transitionsDecoded['transitions'], transitions);

    final sensor = pkg.parts.singleWhere((p) => p.kind == 'sensor_windows');
    expect(sensor.file.path, endsWith('.bin.gz'));
    final bytes = await sensor.file.readAsBytes();
    expect(sensor.sizeBytes, bytes.length);
    expect(sensor.sha256, sha256.convert(bytes).toString());
    final decoded = _decodeSensorWindowPart(bytes);
    expect(decoded, hasLength(1));
    expect(decoded.single.sampleRateHz, 100);
    expect(decoded.single.samples, hasLength(1));
    expect(decoded.single.samples.single, [
      closeTo(0.1, 0.000001),
      closeTo(0.2, 0.000001),
      closeTo(9.7, 0.000001),
      closeTo(0.01, 0.000001),
      closeTo(0.02, 0.000001),
      closeTo(0.03, 0.000001),
    ]);
  });

  test('builds the same inline core hash for the same local evidence',
      () async {
    await seedSession('s-hash');

    final first = await builder().build('s-hash');
    final second = await builder().build('s-hash');

    expect(first.corePayload!.canonicalJson, second.corePayload!.canonicalJson);
    expect(first.corePayload!.sha256, second.corePayload!.sha256);
  });

  test('splits sensor windows into multiple parts when over budget', () async {
    await seedSession('s2');
    await seedWindows('s2', 5);

    // Budget minuscolo: forza una parte per finestra.
    final pkg = await builder(budget: 10).build('s2');

    final sensorParts =
        pkg.parts.where((p) => p.kind == 'sensor_windows').toList();
    expect(sensorParts, hasLength(5));
    expect(sensorParts.map((p) => p.sequence).toList(), [1, 2, 3, 4, 5]);
    expect(pkg.expectedRawParts['sensor_windows'], 5);

    // Ogni parte e' un binario valido con una finestra.
    for (final part in sensorParts) {
      final decoded = _decodeSensorWindowPart(await part.file.readAsBytes());
      expect(decoded, hasLength(1));
    }
  });

  test('omits parts for empty data', () async {
    final dao = database.acquisitionDao;
    await dao.createSession(
      id: 's3',
      deviceId: 'dev',
      startedAt: DateTime.utc(2026, 6, 12, 10),
    );

    final pkg = await builder().build('s3');

    expect(pkg.corePayload, isNull);
    expect(pkg.parts, isEmpty);
    expect(pkg.expectedCoreParts, isEmpty);
    expect(pkg.expectedRawParts, isEmpty);
  });
}

const List<int> _sensorWindowsBinaryMagic = [
  0x4d,
  0x44,
  0x48,
  0x41,
  0x52,
  0x57,
  0x31,
  0x00,
];
const int _binaryHeaderBytes = 12;
const int _binaryWindowHeaderBytes = 28;
const int _sensorChannelCount = 6;

({int sampleRateHz, List<List<double>> samples}) _decodeWindow(
  ByteData data,
  int start,
) {
  final sampleRateHz = data.getUint32(start + 16, Endian.little);
  final sampleCount = data.getUint32(start + 20, Endian.little);
  final channelCount = data.getUint32(start + 24, Endian.little);
  expect(channelCount, _sensorChannelCount);

  var cursor = start + _binaryWindowHeaderBytes;
  final samples = <List<double>>[];
  for (var sample = 0; sample < sampleCount; sample += 1) {
    final row = <double>[];
    for (var channel = 0; channel < channelCount; channel += 1) {
      row.add(data.getFloat32(cursor, Endian.little));
      cursor += Float32List.bytesPerElement;
    }
    samples.add(row);
  }
  return (sampleRateHz: sampleRateHz, samples: samples);
}

List<({int sampleRateHz, List<List<double>> samples})> _decodeSensorWindowPart(
  List<int> gzipped,
) {
  final bytes = Uint8List.fromList(gzip.decode(gzipped));
  expect(bytes.sublist(0, _sensorWindowsBinaryMagic.length),
      _sensorWindowsBinaryMagic);
  final data = ByteData.sublistView(bytes);
  final windowCount = data.getUint32(8, Endian.little);
  var cursor = _binaryHeaderBytes;
  final windows = <({int sampleRateHz, List<List<double>> samples})>[];
  for (var i = 0; i < windowCount; i += 1) {
    final window = _decodeWindow(data, cursor);
    windows.add(window);
    cursor += _binaryWindowHeaderBytes +
        (window.samples.length *
            _sensorChannelCount *
            Float32List.bytesPerElement);
  }
  expect(cursor, bytes.length);
  return windows;
}

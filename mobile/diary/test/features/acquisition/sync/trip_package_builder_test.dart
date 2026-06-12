import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
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
      toState: 'POTENTIAL_MOTION',
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
        matrixJson: '[[0.1,0.2,9.7,0.01,0.02,0.03,20.1,12.2,40.0]]',
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

  test('builds gps, transitions and a sensor window part with valid blobs',
      () async {
    await seedSession('s1');
    await seedWindows('s1', 1);

    final pkg = await builder().build('s1');

    expect(pkg.expectedParts,
        {'gps_points': 1, 'state_transitions': 1, 'sensor_windows': 1});
    expect(pkg.startedAt, DateTime.utc(2026, 6, 12, 10));
    expect(pkg.endedAt, DateTime.utc(2026, 6, 12, 10, 35));

    final gps = pkg.parts.firstWhere((p) => p.kind == 'gps_points');
    final bytes = await gps.file.readAsBytes();
    // Checksum e dimensione coerenti con il file scritto.
    expect(gps.sizeBytes, bytes.length);
    expect(gps.sha256, sha256.convert(bytes).toString());
    // Il blob e' gzip + JSON valido col formato atteso dal backend.
    final decoded = jsonDecode(utf8.decode(gzip.decode(bytes)))
        as Map<String, dynamic>;
    final points = decoded['points'] as List<dynamic>;
    expect(points, hasLength(1));
    expect((points.first as Map)['latitude'], 45.4642);
    expect((points.first as Map)['speed_mps'], 3.2);
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
    expect(pkg.expectedParts['sensor_windows'], 5);

    // Ogni parte e' un JSON valido con una finestra.
    for (final part in sensorParts) {
      final decoded =
          jsonDecode(utf8.decode(gzip.decode(await part.file.readAsBytes())))
              as Map<String, dynamic>;
      expect((decoded['windows'] as List<dynamic>), hasLength(1));
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

    expect(pkg.parts, isEmpty);
    expect(pkg.expectedParts, isEmpty);
  });
}

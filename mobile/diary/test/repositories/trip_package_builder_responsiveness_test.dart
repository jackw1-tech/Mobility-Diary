import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/repositories/impl/acquisition/trip_package_builder.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDirectory;
  late AcquisitionLocalDatabase database;
  late AcquisitionDao dao;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp(
      'trip-package-responsiveness-',
    );
    database = AcquisitionLocalDatabase(
      NativeDatabase.createInBackground(
        File('${tempDirectory.path}/acquisition.sqlite'),
      ),
    );
    dao = AcquisitionDao(database);
  });

  tearDown(() async {
    await database.close();
    if (await tempDirectory.exists()) {
      await tempDirectory.delete(recursive: true);
    }
  });

  test('keeps the main isolate responsive while packaging a large trip',
      () async {
    final startedAt = DateTime.utc(2026, 9, 3, 8);
    await dao.createSession(
      id: 'long-session',
      deviceId: 'iphone',
      startedAt: startedAt,
    );
    await dao.endSession(
      id: 'long-session',
      endedAt: startedAt.add(const Duration(hours: 2)),
    );

    // Circa 13 MB di JSON realistico: abbastanza da rendere visibile un gzip
    // eseguito accidentalmente sul main isolate, senza appesantire la suite.
    final matrix = StringBuffer('[');
    for (var index = 0; index < 220000; index += 1) {
      if (index > 0) matrix.write(',');
      final variation = index % 1000000;
      matrix.write(
        '[0.$variation,-9.806649,0.112346,0.001235,-0.004321,0.000765]',
      );
    }
    matrix.write(']');

    await dao.insertSensorWindow(
      sessionId: 'long-session',
      startTimestamp: startedAt,
      endTimestamp: startedAt.add(const Duration(seconds: 5)),
      sampleCount: 220000,
      frequencyHz: 100,
      matrixJson: matrix.toString(),
    );

    final stopwatch = Stopwatch()..start();
    final gaps = <Duration>[];
    var previousTick = stopwatch.elapsed;
    final heartbeat = Timer.periodic(const Duration(milliseconds: 5), (_) {
      final now = stopwatch.elapsed;
      gaps.add(now - previousTick);
      previousTick = now;
    });

    await Future<void>.delayed(const Duration(milliseconds: 20));
    final package = await TripPackageBuilder(
      dao: dao,
      baseDirProvider: () async => tempDirectory,
      sensorWindowsPartBudgetBytes: 32 * 1024 * 1024,
    ).build('long-session');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    heartbeat.cancel();

    expect(package.rawParts, hasLength(1));
    expect(gaps, isNotEmpty);
    final longestGap =
        gaps.reduce((left, right) => left > right ? left : right);
    expect(
      longestGap,
      lessThan(const Duration(milliseconds: 150)),
      reason: 'Il packaging ha bloccato il main isolate del client mobile',
    );
  });

  test('packages every window across bounded database pages', () async {
    final startedAt = DateTime.utc(2026, 9, 3, 8);
    await dao.createSession(
      id: 'paged-session',
      deviceId: 'iphone',
      startedAt: startedAt,
    );
    await dao.endSession(
      id: 'paged-session',
      endedAt: startedAt.add(const Duration(minutes: 5)),
    );
    for (var minute = 4; minute >= 0; minute -= 1) {
      final windowStart = startedAt.add(Duration(minutes: minute));
      await dao.insertSensorWindow(
        sessionId: 'paged-session',
        startTimestamp: windowStart,
        endTimestamp: windowStart.add(const Duration(seconds: 5)),
        sampleCount: 1,
        frequencyHz: 100,
        matrixJson: '[[0,$minute,2,3,4,5]]',
      );
    }

    final package = await TripPackageBuilder(
      dao: dao,
      baseDirProvider: () async => tempDirectory,
      sensorWindowsPartBudgetBytes: 500,
      sensorWindowsPageSize: 2,
    ).build('paged-session');

    final starts = <String>[];
    for (final part in package.rawParts) {
      final compressedBytes = await part.file.readAsBytes();
      expect(
        part.sha256,
        crypto.sha256.convert(compressedBytes).toString(),
      );
      final payload = jsonDecode(
        utf8.decode(gzip.decode(compressedBytes)),
      ) as Map<String, dynamic>;
      final windows = payload['windows'] as List<dynamic>;
      starts.addAll(
        windows.map(
          (window) =>
              (window as Map<String, dynamic>)['window_start']! as String,
        ),
      );
    }

    expect(package.rawParts.map((part) => part.sequence), [1, 2, 3]);
    expect(starts, [
      for (var minute = 0; minute < 5; minute += 1)
        startedAt.add(Duration(minutes: minute)).toIso8601String(),
    ]);
  });
}

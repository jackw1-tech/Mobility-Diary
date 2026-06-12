import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Una parte fisica del pacchetto viaggio: un file .json.gz su disco con il suo
/// checksum e dimensione, pronto per l'upload presigned.
class TripPackagePart {
  final String kind; // gps_points | state_transitions | sensor_windows
  final int sequence;
  final File file;
  final String sha256;
  final int sizeBytes;

  const TripPackagePart({
    required this.kind,
    required this.sequence,
    required this.file,
    required this.sha256,
    required this.sizeBytes,
  });
}

/// Il pacchetto viaggio locale: metadati + parti compresse su disco
/// (REPORT_STRATEGIA_INGESTION_ASINCRONA.md, "Creazione del Pacchetto Locale").
class TripPackage {
  final String localSessionId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Directory directory;
  final List<TripPackagePart> parts;

  const TripPackage({
    required this.localSessionId,
    required this.startedAt,
    required this.endedAt,
    required this.directory,
    required this.parts,
  });

  /// Conteggio parti per kind, da dichiarare al backend in `create`.
  Map<String, int> get expectedParts {
    final counts = <String, int>{};
    for (final part in parts) {
      counts[part.kind] = (counts[part.kind] ?? 0) + 1;
    }
    return counts;
  }
}

/// Costruisce il pacchetto viaggio leggendo il DB locale e scrivendo blob
/// gzip su disco. Le sensor window vengono spezzate in piu' parti per stare
/// sotto la soglia di dimensione (chunk con retry parziale).
class TripPackageBuilder {
  final AcquisitionDao _dao;
  final Future<Directory> Function() _baseDirProvider;

  // Budget per parte sensor window, misurato sul JSON NON compresso. Una parte
  // gzip risultante e' molto piu' piccola. ~12 MB -> qualche MB compressi.
  final int _sensorWindowsPartBudgetBytes;

  TripPackageBuilder({
    required AcquisitionDao dao,
    Future<Directory> Function()? baseDirProvider,
    int sensorWindowsPartBudgetBytes = 12 * 1024 * 1024,
  })  : _dao = dao,
        _baseDirProvider = baseDirProvider ?? getTemporaryDirectory,
        _sensorWindowsPartBudgetBytes = sensorWindowsPartBudgetBytes;

  Future<TripPackage> build(String localSessionId) async {
    final session = await _dao.findSession(localSessionId);
    final directory = await _packageDirectory(localSessionId);

    final parts = <TripPackagePart>[];
    final gpsPart = await _buildGpsPart(localSessionId, directory);
    if (gpsPart != null) parts.add(gpsPart);
    final transitionsPart =
        await _buildTransitionsPart(localSessionId, directory);
    if (transitionsPart != null) parts.add(transitionsPart);
    parts.addAll(await _buildSensorWindowParts(localSessionId, directory));

    return TripPackage(
      localSessionId: localSessionId,
      startedAt: session?.startedAt,
      endedAt: session?.endedAt,
      directory: directory,
      parts: parts,
    );
  }

  Future<Directory> _packageDirectory(String localSessionId) async {
    final base = await _baseDirProvider();
    final dir = Directory(p.join(base.path, 'trip_package_$localSessionId'));
    if (await dir.exists()) {
      await dir.delete(recursive: true);
    }
    await dir.create(recursive: true);
    return dir;
  }

  Future<TripPackagePart?> _buildGpsPart(
    String sessionId,
    Directory directory,
  ) async {
    final points = await _dao.gpsPointsForSession(sessionId);
    if (points.isEmpty) return null;

    final json = jsonEncode({
      'points': [
        for (final point in points)
          {
            'timestamp': point.timestamp.toUtc().toIso8601String(),
            'latitude': point.latitude,
            'longitude': point.longitude,
            'speed_mps': point.speedMps,
            'accuracy_meters': point.accuracyMeters,
          }
      ],
    });
    return _writePart(directory, 'gps_points', 1, json);
  }

  Future<TripPackagePart?> _buildTransitionsPart(
    String sessionId,
    Directory directory,
  ) async {
    final transitions = await _dao.transitionsForSession(sessionId);
    if (transitions.isEmpty) return null;

    final json = jsonEncode({
      'transitions': [
        for (final t in transitions)
          {
            'timestamp': t.timestamp.toUtc().toIso8601String(),
            'from_state': t.fromState,
            'to_state': t.toState,
            'reason': t.reason,
            'sigma': t.sigma,
            'speed_mps': t.speedMps,
          }
      ],
    });
    return _writePart(directory, 'state_transitions', 1, json);
  }

  Future<List<TripPackagePart>> _buildSensorWindowParts(
    String sessionId,
    Directory directory,
  ) async {
    final windows = await _dao.sensorWindowsForSession(sessionId);
    if (windows.isEmpty) return const [];

    final parts = <TripPackagePart>[];
    var sequence = 1;
    var buffer = StringBuffer();
    var bufferedBytes = 0;
    var bufferedCount = 0;

    Future<void> flush() async {
      if (bufferedCount == 0) return;
      final json = '{"windows":[${buffer.toString()}]}';
      parts.add(await _writePart(directory, 'sensor_windows', sequence, json));
      sequence += 1;
      buffer = StringBuffer();
      bufferedBytes = 0;
      bufferedCount = 0;
    }

    for (final window in windows) {
      // `matrixJson` e' gia' un array JSON valido: lo si incastra direttamente
      // come valore di "samples" senza decodificarlo/ricodificarlo.
      final windowJson = '{'
          '"window_start":"${window.startTimestamp.toUtc().toIso8601String()}",'
          '"window_end":"${window.endTimestamp.toUtc().toIso8601String()}",'
          '"sample_rate_hz":${window.frequencyHz},'
          '"sample_count":${window.sampleCount},'
          '"samples":${window.matrixJson}}';

      if (bufferedCount > 0 &&
          bufferedBytes + windowJson.length > _sensorWindowsPartBudgetBytes) {
        await flush();
      }

      if (bufferedCount > 0) buffer.write(',');
      buffer.write(windowJson);
      bufferedBytes += windowJson.length;
      bufferedCount += 1;
    }
    await flush();

    return parts;
  }

  Future<TripPackagePart> _writePart(
    Directory directory,
    String kind,
    int sequence,
    String json,
  ) async {
    final fileName = kind == 'sensor_windows'
        ? 'sensor_windows_part_${sequence.toString().padLeft(4, '0')}.json.gz'
        : '$kind.json.gz';
    final file = File(p.join(directory.path, fileName));

    final gzipped = gzip.encode(utf8.encode(json));
    await file.writeAsBytes(gzipped, flush: true);

    return TripPackagePart(
      kind: kind,
      sequence: sequence,
      file: file,
      sha256: sha256.convert(gzipped).toString(),
      sizeBytes: gzipped.length,
    );
  }
}

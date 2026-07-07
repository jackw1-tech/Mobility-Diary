import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/domain/sensor_matrix_blob.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Una parte fisica del pacchetto viaggio: un file gzip su disco con il suo
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

class TripCorePayload {
  final Map<String, dynamic> bodyWithoutHash;
  final String sha256;

  TripCorePayload._({
    required this.bodyWithoutHash,
    required this.sha256,
  });

  factory TripCorePayload(Map<String, dynamic> bodyWithoutHash) {
    final stableBody =
        _stableJsonValue(bodyWithoutHash) as Map<String, dynamic>;
    final canonicalJson = jsonEncode(stableBody);
    return TripCorePayload._(
      bodyWithoutHash: stableBody,
      sha256: crypto.sha256.convert(utf8.encode(canonicalJson)).toString(),
    );
  }

  Map<String, dynamic> get requestBody => {
        ...bodyWithoutHash,
        'core_payload_sha256': sha256,
      };

  String get canonicalJson => jsonEncode(bodyWithoutHash);

  int get sizeBytes => utf8.encode(jsonEncode(requestBody)).length;
}

/// Il pacchetto viaggio locale: metadati + parti compresse su disco
/// (REPORT_STRATEGIA_INGESTION_ASINCRONA.md, "Creazione del Pacchetto Locale").
class TripPackage {
  final String localSessionId;
  final int? remoteIngestionId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Directory directory;
  final TripCorePayload? corePayload;
  final List<TripPackagePart> parts;

  const TripPackage({
    required this.localSessionId,
    required this.remoteIngestionId,
    required this.startedAt,
    required this.endedAt,
    required this.directory,
    required this.corePayload,
    required this.parts,
  });

  /// Parti core (gps_points/state_transitions) pronte per l'upload presigned:
  /// fallback usato solo quando il core inline viene rifiutato per dimensione
  /// (vedi [TripSyncQueueImpl]).
  Map<String, int> get expectedCoreParts => _expectedParts(coreParts);

  Map<String, int> get expectedRawParts => _expectedParts(rawParts);

  List<TripPackagePart> get coreParts {
    return parts
        .where(
          (part) =>
              part.kind == 'gps_points' || part.kind == 'state_transitions',
        )
        .toList(growable: false);
  }

  List<TripPackagePart> get rawParts {
    return parts
        .where((part) => part.kind == 'sensor_windows')
        .toList(growable: false);
  }
}

/// Costruisce il pacchetto viaggio leggendo il DB locale e scrivendo blob
/// gzip su disco. Le sensor window vengono spezzate in piu' parti per stare
/// sotto la soglia di dimensione (chunk con retry parziale).
class TripPackageBuilder {
  final AcquisitionDao _dao;
  final Future<Directory> Function() _baseDirProvider;

  // Budget per parte sensor window, misurato sul binario NON compresso. Una
  // parte gzip risultante e' piu' piccola. ~12 MB -> qualche MB compressi.
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
    final remoteIngestionId = session?.remoteIngestionId;
    final directory = await _packageDirectory(localSessionId);

    final gpsPoints = await _buildInlineGpsPoints(localSessionId);
    final transitions = await _buildInlineTransitions(localSessionId);
    final parts = <TripPackagePart>[];
    parts.addAll(await _buildSensorWindowParts(localSessionId, directory));
    final corePayload = gpsPoints.isEmpty && transitions.isEmpty
        ? null
        : TripCorePayload({
            'app_version': '',
            'client_session_id': localSessionId,
            'device_id': session?.deviceId ?? '',
            'device_platform': '',
            'ended_at': _utcIsoOrNull(session?.endedAt),
            'expected_raw_parts': _expectedParts(parts),
            'gps_points': gpsPoints,
            if (remoteIngestionId != null) 'ingestion_id': remoteIngestionId,
            'schema_version': 1,
            'started_at': _utcIsoOrNull(session?.startedAt),
            'state_transitions': transitions,
            'timezone': '',
          });
    // Costruite sempre insieme al payload inline (costo minimo): se il core
    // inline viene rifiutato per dimensione, la coda di sync le usa come
    // fallback a parti presigned invece di perdere il viaggio.
    parts.addAll(
      await _buildCoreParts(
        directory,
        gpsPoints: gpsPoints,
        transitions: transitions,
      ),
    );

    return TripPackage(
      localSessionId: localSessionId,
      remoteIngestionId: remoteIngestionId,
      startedAt: session?.startedAt,
      endedAt: session?.endedAt,
      directory: directory,
      corePayload: corePayload,
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

  Future<List<Map<String, dynamic>>> _buildInlineGpsPoints(
    String sessionId,
  ) async {
    final points = await _dao.gpsPointsForSession(sessionId);
    return [
      for (final point in points)
        {
          'accuracy_meters': point.accuracyMeters,
          'latitude': point.latitude,
          'longitude': point.longitude,
          'speed_mps': point.speedMps,
          'timestamp': _utcIso(point.timestamp),
        }
    ];
  }

  Future<List<Map<String, dynamic>>> _buildInlineTransitions(
    String sessionId,
  ) async {
    final transitions = await _dao.transitionsForSession(sessionId);
    return [
      for (final t in transitions)
        {
          'from_state': t.fromState,
          'reason': t.reason,
          'sigma': t.sigma,
          'speed_mps': t.speedMps,
          'timestamp': _utcIso(t.timestamp),
          'to_state': t.toState,
        }
    ];
  }

  /// Stessi punti/transizioni del payload inline, incapsulati come parte
  /// gzip presigned (fallback per core troppo grande per l'inline).
  Future<List<TripPackagePart>> _buildCoreParts(
    Directory directory, {
    required List<Map<String, dynamic>> gpsPoints,
    required List<Map<String, dynamic>> transitions,
  }) async {
    final parts = <TripPackagePart>[];
    if (gpsPoints.isNotEmpty) {
      final json = jsonEncode({'points': gpsPoints});
      parts.add(
        await _writeGzipPart(directory, 'gps_points', 1, utf8.encode(json)),
      );
    }
    if (transitions.isNotEmpty) {
      final json = jsonEncode({'transitions': transitions});
      parts.add(
        await _writeGzipPart(
          directory,
          'state_transitions',
          1,
          utf8.encode(json),
        ),
      );
    }
    return parts;
  }

  Future<List<TripPackagePart>> _buildSensorWindowParts(
    String sessionId,
    Directory directory,
  ) async {
    final windows = await _dao.sensorWindowsForSession(sessionId);
    if (windows.isEmpty) return const [];

    final parts = <TripPackagePart>[];
    var sequence = 1;
    var bufferedWindows = <SensorWindow>[];
    var bufferedBytes = 0;

    Future<void> flush() async {
      if (bufferedWindows.isEmpty) return;
      final bytes = _encodeSensorWindowsBinary(bufferedWindows);
      parts.add(
        await _writeGzipPart(
          directory,
          'sensor_windows',
          sequence,
          bytes,
        ),
      );
      sequence += 1;
      bufferedWindows = <SensorWindow>[];
      bufferedBytes = 0;
    }

    for (final window in windows) {
      final windowBytes = _sensorWindowBinaryByteSize(window);

      if (bufferedWindows.isNotEmpty &&
          bufferedBytes + windowBytes > _sensorWindowsPartBudgetBytes) {
        await flush();
      }

      bufferedWindows.add(window);
      bufferedBytes += windowBytes;
    }
    await flush();

    return parts;
  }

  Future<TripPackagePart> _writeGzipPart(
    Directory directory,
    String kind,
    int sequence,
    List<int> payload,
  ) async {
    final fileName = kind == 'sensor_windows'
        ? 'sensor_windows_part_${sequence.toString().padLeft(4, '0')}.bin.gz'
        : '$kind.json.gz';
    final file = File(p.join(directory.path, fileName));

    final gzipped = gzip.encode(payload);
    await file.writeAsBytes(gzipped, flush: true);

    return TripPackagePart(
      kind: kind,
      sequence: sequence,
      file: file,
      sha256: crypto.sha256.convert(gzipped).toString(),
      sizeBytes: gzipped.length,
    );
  }
}

const List<int> _sensorWindowsBinaryMagic = [
  0x4d, // M
  0x44, // D
  0x48, // H
  0x41, // A
  0x52, // R
  0x57, // W
  0x31, // 1
  0x00,
];
const int _binaryHeaderBytes = 12;
const int _binaryWindowHeaderBytes = 28;

int _sensorWindowBinaryByteSize(SensorWindow window) {
  return _binaryWindowHeaderBytes +
      (window.sampleCount *
          sensorMatrixChannelCount *
          Float32List.bytesPerElement);
}

Uint8List _encodeSensorWindowsBinary(List<SensorWindow> windows) {
  final builder = BytesBuilder(copy: false);
  final header = ByteData(_binaryHeaderBytes);
  for (var i = 0; i < _sensorWindowsBinaryMagic.length; i += 1) {
    header.setUint8(i, _sensorWindowsBinaryMagic[i]);
  }
  header.setUint32(8, windows.length, Endian.little);
  builder.add(header.buffer.asUint8List());

  for (final window in windows) {
    final sampleCount = window.sampleCount;
    final expectedBlobBytes =
        sampleCount * sensorMatrixChannelCount * Float32List.bytesPerElement;
    if (window.matrixBlob.lengthInBytes != expectedBlobBytes) {
      throw const FormatException('sensor window matrix blob non valido');
    }
    final windowHeader = ByteData(_binaryWindowHeaderBytes);
    windowHeader.setInt64(
      0,
      window.startTimestamp.toUtc().microsecondsSinceEpoch,
      Endian.little,
    );
    windowHeader.setInt64(
      8,
      window.endTimestamp.toUtc().microsecondsSinceEpoch,
      Endian.little,
    );
    windowHeader.setUint32(16, window.frequencyHz, Endian.little);
    windowHeader.setUint32(20, sampleCount, Endian.little);
    windowHeader.setUint32(24, sensorMatrixChannelCount, Endian.little);
    builder.add(windowHeader.buffer.asUint8List());
    builder.add(window.matrixBlob);
  }

  return builder.toBytes();
}

Map<String, int> _expectedParts(List<TripPackagePart> sourceParts) {
  final counts = <String, int>{};
  for (final part in sourceParts) {
    counts[part.kind] = (counts[part.kind] ?? 0) + 1;
  }
  return counts;
}

Object? _stableJsonValue(Object? value) {
  if (value is Map) {
    final sorted = SplayTreeMap<String, dynamic>();
    for (final entry in value.entries) {
      sorted[entry.key as String] = _stableJsonValue(entry.value);
    }
    return sorted;
  }
  if (value is List) {
    return [for (final item in value) _stableJsonValue(item)];
  }
  return value;
}

String? _utcIsoOrNull(DateTime? value) => value == null ? null : _utcIso(value);

String _utcIso(DateTime value) {
  final utc = value.toUtc();
  final year = utc.year.toString().padLeft(4, '0');
  final month = utc.month.toString().padLeft(2, '0');
  final day = utc.day.toString().padLeft(2, '0');
  final hour = utc.hour.toString().padLeft(2, '0');
  final minute = utc.minute.toString().padLeft(2, '0');
  final second = utc.second.toString().padLeft(2, '0');
  final fractionMicros = utc.millisecond * 1000 + utc.microsecond;
  final base = '$year-$month-${day}T$hour:$minute:$second';
  if (fractionMicros == 0) return '${base}Z';
  return '$base.${fractionMicros.toString().padLeft(6, '0')}Z';
}

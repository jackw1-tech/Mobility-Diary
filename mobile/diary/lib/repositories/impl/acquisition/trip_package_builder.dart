import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:diary/mappers/acquisition_mapper.dart';
import 'package:diary/mappers/ingestion_mapper.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/model/entities/acquisition/sensor_matrix_json.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Una parte fisica del pacchetto viaggio: un file gzip su disco con il suo
/// checksum e dimensione, pronto per l'upload presigned.
class TripPackagePart {
  final int sequence;
  final File file;
  final String sha256;

  const TripPackagePart({
    required this.sequence,
    required this.file,
    required this.sha256,
  });
}

class TripCorePayload {
  final Map<String, dynamic> body;

  TripCorePayload._({required this.body});

  factory TripCorePayload(Map<String, dynamic> body) {
    return TripCorePayload._(
      body: _stableJsonValue(body) as Map<String, dynamic>,
    );
  }

  Map<String, dynamic> get requestBody => body;

  String get canonicalJson => jsonEncode(body);

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

  int get expectedRawParts => rawParts.length;

  List<TripPackagePart> get rawParts {
    return parts.toList(growable: false);
  }
}

/// Costruisce il pacchetto viaggio leggendo il DB locale e scrivendo file
/// JSON gzippati su disco. Le sensor window vengono spezzate in piu' parti per
/// stare sotto la soglia di dimensione (chunk con retry parziale).
class TripPackageBuilder {
  final AcquisitionDao _dao;
  final Future<Directory> Function() _baseDirProvider;

  final int _sensorWindowsPartBudgetBytes;

  final AcquisitionMapper _acquisitionMapper;
  final IngestionMapper _ingestionMapper;

  TripPackageBuilder({
    required AcquisitionDao dao,
    AcquisitionMapper? acquisitionMapper,
    IngestionMapper? ingestionMapper,
    Future<Directory> Function()? baseDirProvider,
    // Budget misurato sul JSON non compresso: una finestra pesa ~29 KB, quindi
    // ~12 MB sono circa 430 finestre (~36 min di registrazione) e diventano
    // ~5 MB dopo gzip. Tenerlo basso limita il picco di memoria della
    // serializzazione sul telefono.
    int sensorWindowsPartBudgetBytes = 12 * 1024 * 1024,
  })  : _dao = dao,
        _acquisitionMapper = acquisitionMapper ?? AcquisitionMapper(),
        _ingestionMapper = ingestionMapper ?? IngestionMapper(),
        _baseDirProvider = baseDirProvider ?? getTemporaryDirectory,
        _sensorWindowsPartBudgetBytes = sensorWindowsPartBudgetBytes;

  Future<TripPackage> build(String localSessionId) async {
    final session = await _dao.findSession(localSessionId);
    final remoteIngestionId = session?.remoteIngestionId;
    final directory = await _packageDirectory(localSessionId);

    final gpsPoints = _acquisitionMapper
        .mapGpsPoints(await _dao.gpsPointsForSession(localSessionId))
        .where((point) => _belongsToSession(point.timestamp, session))
        .toList(growable: false);
    final transitions = _acquisitionMapper
        .mapStateTransitions(await _dao.transitionsForSession(localSessionId))
        .where((transition) => _belongsToSession(transition.timestamp, session))
        .toList(growable: false);
    final parts = <TripPackagePart>[];
    parts.addAll(await _buildSensorWindowParts(localSessionId, directory));
    final corePayload = gpsPoints.isEmpty && transitions.isEmpty
        ? null
        : TripCorePayload(
            _ingestionMapper.toCorePayloadJson(
              clientSessionId: localSessionId,
              deviceId: session?.deviceId ?? '',
              gpsPoints: gpsPoints,
              transitions: transitions,
              expectedRawParts: parts.length,
              startedAt: session?.startedAt,
              endedAt: session?.endedAt,
              ingestionId: remoteIngestionId,
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

  // Divide in parti le sensor window, circa 12 MB ciascuna
  Future<List<TripPackagePart>> _buildSensorWindowParts(
    String sessionId,
    Directory directory,
  ) async {
    final windows = await _dao.sensorWindowsForSession(sessionId);
    if (windows.isEmpty) return const [];

    final parts = <TripPackagePart>[];
    var sequence = 1;
    var bufferedWindows = <SensorWindow>[]; // Buffer di accumulo
    var bufferedBytes = 0;

    Future<void> flush() async {
      if (bufferedWindows.isEmpty) return;
      final payload = utf8.encode(_encodeSensorWindowsJson(bufferedWindows));
      parts.add(
        await _writeGzipPart(
          directory,
          sequence,
          payload,
        ),
      );
      sequence += 1;
      bufferedWindows = <SensorWindow>[];
      bufferedBytes = 0;
    }

    for (final window in windows) {
      final windowBytes = _sensorWindowJsonByteSize(window);

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
    int sequence,
    List<int> payload,
  ) async {
    final fileName =
        'sensor_windows_part_${sequence.toString().padLeft(4, '0')}.json.gz';
    final file = File(p.join(directory.path, fileName));

    // Il testo decimale e' ridondante: gzip lo riduce di circa 2,5x, il che
    // porta la parte quasi in pari con il vecchio formato binario (i float32
    // grezzi erano quasi incomprimibili).
    final gzipped = gzip.encode(payload);
    await file.writeAsBytes(gzipped, flush: true);

    return TripPackagePart(
      sequence: sequence,
      file: file,
      sha256: crypto.sha256.convert(gzipped).toString(),
    );
  }
}

bool _belongsToSession(DateTime timestamp, AcquisitionSession? session) {
  if (session == null) return true;
  if (timestamp.isBefore(session.startedAt)) return false;
  final endedAt = session.endedAt;
  return endedAt == null || !timestamp.isAfter(endedAt);
}

// Overhead JSON di una finestra oltre alla matrice: chiavi, timestamp ISO,
// contatori e punteggiatura. Stima usata solo per decidere dove tagliare le
// parti, non deve essere esatta.
const int _windowJsonOverheadBytes = 220;

int _sensorWindowJsonByteSize(SensorWindow window) {
  // La matrice e' gia' JSON su disco: la sua lunghezza e' la dimensione reale.
  return _windowJsonOverheadBytes + window.matrixJson.length;
}

/// Serializza le finestre nel formato atteso dal backend
/// (`decode_sensor_windows_payload`). La matrice viene inserita verbatim dal
/// DB: e' gia' JSON valido e arrotondato, quindi non serve decodificarla e
/// ricodificarla — si risparmia il giro piu' costoso dell'intero packaging.
String _encodeSensorWindowsJson(List<SensorWindow> windows) {
  final buffer = StringBuffer('{"windows":[');
  for (var i = 0; i < windows.length; i += 1) {
    final window = windows[i];
    if (i > 0) buffer.write(',');
    buffer
      ..write('{"window_start":"')
      ..write(window.startTimestamp.toUtc().toIso8601String())
      ..write('","window_end":"')
      ..write(window.endTimestamp.toUtc().toIso8601String())
      ..write('","sample_rate_hz":')
      ..write(window.frequencyHz)
      ..write(',"sample_count":')
      ..write(window.sampleCount)
      ..write(',"channel_count":')
      ..write(sensorMatrixChannelCount)
      ..write(',"samples":')
      ..write(window.matrixJson)
      ..write('}');
  }
  buffer.write(']}');
  return buffer.toString();
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

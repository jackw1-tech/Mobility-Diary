import 'dart:collection';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart' as crypto;
import 'package:diary/mappers/acquisition_mapper.dart';
import 'package:diary/mappers/upload_mapper.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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
/// (REPORT_STRATEGIA_UPLOAD_ASINCRONA.md, "Creazione del Pacchetto Locale").
class TripPackage {
  final String localSessionId;
  final int? remoteUploadId;
  final DateTime? startedAt;
  final DateTime? endedAt;
  final Directory directory;
  final TripCorePayload? corePayload;
  final List<TripPackagePart> parts;

  const TripPackage({
    required this.localSessionId,
    required this.remoteUploadId,
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
  final int _sensorWindowsPageSize;

  final AcquisitionMapper _acquisitionMapper;
  final UploadMapper _uploadMapper;

  TripPackageBuilder({
    required AcquisitionDao dao,
    AcquisitionMapper? acquisitionMapper,
    UploadMapper? uploadMapper,
    Future<Directory> Function()? baseDirProvider,
    // Budget misurato sul JSON non compresso: una finestra pesa ~29 KB, quindi
    // ~12 MB sono circa 430 finestre (~36 min di registrazione) e diventano
    // ~5 MB dopo gzip. Tenerlo basso limita il picco di memoria della
    // serializzazione sul telefono.
    int sensorWindowsPartBudgetBytes = 12 * 1024 * 1024,
    // La pagina e' intenzionalmente molto piu' piccola di una parte: il picco
    // di memoria dipende dal budget della parte e non dalla durata del viaggio.
    int sensorWindowsPageSize = 128,
  })  : _dao = dao,
        _acquisitionMapper = acquisitionMapper ?? AcquisitionMapper(),
        _uploadMapper = uploadMapper ?? UploadMapper(),
        _baseDirProvider = baseDirProvider ?? getTemporaryDirectory,
        _sensorWindowsPartBudgetBytes = sensorWindowsPartBudgetBytes,
        _sensorWindowsPageSize =
            sensorWindowsPageSize < 1 ? 1 : sensorWindowsPageSize;

  Future<TripPackage> build(String localSessionId) async {
    final session = await _dao.findSession(localSessionId);
    final remoteUploadId = session?.remoteUploadId;
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
            _uploadMapper.toCorePayloadJson(
              clientSessionId: localSessionId,
              deviceId: session?.deviceId ?? '',
              gpsPoints: gpsPoints,
              transitions: transitions,
              expectedRawParts: parts.length,
              startedAt: session?.startedAt,
              endedAt: session?.endedAt,
              uploadId: remoteUploadId,
            ),
          );
    return TripPackage(
      localSessionId: localSessionId,
      remoteUploadId: remoteUploadId,
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
    final parts = <TripPackagePart>[];
    var sequence = 1;
    var bufferedWindows = <SensorWindow>[];
    var bufferedBytes = 0;
    var offset = 0;

    Future<void> flush() async {
      if (bufferedWindows.isEmpty) return;
      parts.add(
        await _writeGzipPart(
          directory,
          sequence,
          bufferedWindows,
        ),
      );
      sequence += 1;
      bufferedWindows = <SensorWindow>[];
      bufferedBytes = 0;
    }

    while (true) {
      final page = await _dao.sensorWindowsPageForSession(
        sessionId,
        limit: _sensorWindowsPageSize,
        offset: offset,
      );
      if (page.isEmpty) break;

      for (final window in page) {
        final windowBytes = _sensorWindowJsonByteSize(window);

        if (bufferedWindows.isNotEmpty &&
            bufferedBytes + windowBytes > _sensorWindowsPartBudgetBytes) {
          await flush();
        }

        bufferedWindows.add(window);
        bufferedBytes += windowBytes;
      }

      offset += page.length;
      if (page.length < _sensorWindowsPageSize) break;
    }
    await flush();

    return parts;
  }

  Future<TripPackagePart> _writeGzipPart(
    Directory directory,
    int sequence,
    List<SensorWindow> windows,
  ) async {
    final fileName =
        'sensor_windows_part_${sequence.toString().padLeft(4, '0')}.json.gz';
    final file = File(p.join(directory.path, fileName));

    final partWindows = [
      for (final window in windows)
        _PartSensorWindow(
          startTimestamp: window.startTimestamp,
          endTimestamp: window.endTimestamp,
          frequencyHz: window.frequencyHz,
          matrixJson: window.matrixJson,
        ),
    ];

    // Serializzazione, UTF-8, gzip, checksum e scrittura sono fuori dal main
    // isolate. Il gzip riceve una finestra alla volta: non esistono piu' ne'
    // la String JSON dell'intera parte ne' la sua copia completa in byte.
    final sha256 = await Isolate.run(
      () => _streamCompressedPart(file.path, partWindows),
    );

    return TripPackagePart(
      sequence: sequence,
      file: file,
      sha256: sha256,
    );
  }
}

class _PartSensorWindow {
  final DateTime startTimestamp;
  final DateTime endTimestamp;
  final int frequencyHz;
  final String matrixJson;

  const _PartSensorWindow({
    required this.startTimestamp,
    required this.endTimestamp,
    required this.frequencyHz,
    required this.matrixJson,
  });
}

String _streamCompressedPart(
  String filePath,
  List<_PartSensorWindow> windows,
) {
  final output = _CompressedFileAndHashSink(
    File(filePath).openSync(mode: FileMode.write),
  );
  final gzipInput = gzip.encoder.startChunkedConversion(output);

  try {
    gzipInput.add(utf8.encode('{"windows":['));
    for (var index = 0; index < windows.length; index += 1) {
      final window = windows[index];
      if (index > 0) gzipInput.add(const [44]); // `,`

      // Solo i metadati piccoli vengono concatenati. La matrice, che e' quasi
      // tutto il payload, entra direttamente nel convertitore UTF-8/gzip.
      gzipInput.add(
        utf8.encode(
          '{"window_start":"${window.startTimestamp.toUtc().toIso8601String()}"'
          ',"window_end":"${window.endTimestamp.toUtc().toIso8601String()}"'
          ',"sample_rate_hz":${window.frequencyHz}'
          ',"samples":',
        ),
      );
      gzipInput.add(utf8.encode(window.matrixJson));
      gzipInput.add(const [125]); // `}`
    }
    gzipInput.add(const [93, 125]); // `]}`
    gzipInput.close();
    return output.sha256;
  } catch (_) {
    output.close();
    rethrow;
  }
}

class _CompressedFileAndHashSink implements Sink<List<int>> {
  final RandomAccessFile _file;
  final _DigestSink _digestOutput = _DigestSink();
  late final Sink<List<int>> _hashInput;
  bool _closed = false;

  _CompressedFileAndHashSink(this._file) {
    _hashInput = crypto.sha256.startChunkedConversion(_digestOutput);
  }

  @override
  void add(List<int> data) {
    if (_closed) throw StateError('compressed sink gia chiuso');
    _file.writeFromSync(data);
    _hashInput.add(data);
  }

  @override
  void close() {
    if (_closed) return;
    _closed = true;
    try {
      _hashInput.close();
    } finally {
      _file.closeSync();
    }
  }

  String get sha256 {
    if (!_closed) throw StateError('compressed sink ancora aperto');
    final digest = _digestOutput.value;
    if (digest == null) throw StateError('digest SHA-256 non disponibile');
    return digest.toString();
  }
}

class _DigestSink implements Sink<crypto.Digest> {
  crypto.Digest? value;

  @override
  void add(crypto.Digest data) => value = data;

  @override
  void close() {}
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

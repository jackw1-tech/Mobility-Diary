import 'dart:developer' as developer;

/// Motore condiviso delle tracce diagnostiche temporanee (Dettaglio Viaggio,
/// caricamento diretto delle tracce riutilizzabili, ...).
///
/// Ogni traccia e' legata a un id tecnico (l'id del viaggio) e produce righe
/// di log con un prefisso dedicato, cosi' che l'intero flusso si estragga dai
/// log del dispositivo con un solo filtro. I messaggi contengono solo id
/// tecnici, conteggi e durate: mai token, header, body HTTP, coordinate o dati
/// dell'utente.
class DiagnosticsTracer {
  /// Marcatore univoco del flusso, es. `[DEBUG-TRIP-DETAIL-a7f3]`.
  final String prefix;

  /// Nome logger passato a `dart:developer`.
  final String loggerName;

  /// Prefisso degli id di traccia generati, es. `td` -> `td-1712...-3`.
  final String tracePrefix;

  /// Nome del campo che porta l'id tecnico nella riga di log.
  final String idField;

  final Map<String, _TraceState> _traces = {};
  final Map<int, String> _traceByEntity = {};
  int _sequence = 0;

  DiagnosticsTracer({
    required this.prefix,
    required this.loggerName,
    required this.tracePrefix,
    this.idField = 'trip',
  });

  String start(int entityId, {required String source}) {
    final previous = _traceByEntity[entityId];
    if (previous != null) {
      event(previous, 'trace_superseded');
      _traces.remove(previous);
    }

    final traceId =
        '$tracePrefix-${DateTime.now().millisecondsSinceEpoch}-${++_sequence}';
    _traceByEntity[entityId] = traceId;
    _traces[traceId] = _TraceState(entityId);
    event(traceId, 'trace_started', fields: {'source': source});
    return traceId;
  }

  String ensureFor(int entityId, {required String source}) {
    return _traceByEntity[entityId] ?? start(entityId, source: source);
  }

  String? traceFor(int entityId) => _traceByEntity[entityId];

  void eventFor(
    int entityId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) {
    final traceId = _traceByEntity[entityId];
    if (traceId != null) event(traceId, stage, fields: fields);
  }

  void event(
    String? traceId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) {
    if (traceId == null) return;
    final trace = _traces[traceId];
    if (trace == null) return;

    final elapsedMs = trace.stopwatch.elapsedMicroseconds / 1000;
    final details = StringBuffer(
      '$prefix trace=$traceId $idField=${trace.entityId} '
      'elapsed_ms=${elapsedMs.toStringAsFixed(1)} stage=$stage',
    );
    for (final entry in fields.entries) {
      details.write(' ${entry.key}=${entry.value}');
    }
    developer.log(details.toString(), name: loggerName);
  }

  void finish(String? traceId, {required String reason}) {
    if (traceId == null) return;
    final trace = _traces[traceId];
    if (trace == null) return;
    event(traceId, 'trace_finished', fields: {'reason': reason});
    _traces.remove(traceId);
    if (_traceByEntity[trace.entityId] == traceId) {
      _traceByEntity.remove(trace.entityId);
    }
  }
}

class _TraceState {
  final int entityId;
  final Stopwatch stopwatch = Stopwatch()..start();

  _TraceState(this.entityId);
}

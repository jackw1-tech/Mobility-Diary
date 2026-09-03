import 'dart:developer' as developer;

/// Traccia temporanea del percorso Dettaglio Viaggio.
///
/// I messaggi contengono solo ID tecnici, conteggi e durate: mai token,
/// header, body HTTP, coordinate o dati dell'utente. Il prefisso permette di
/// estrarre l'intera traccia con un solo filtro dai log del dispositivo.
class TripDetailDiagnostics {
  static const String prefix = '[DEBUG-TRIP-DETAIL-a7f3]';
  static const String loggerName = 'mobility.trip_detail';

  static final Map<String, _TripDetailTraceState> _traces = {};
  static final Map<int, String> _traceByTrip = {};
  static int _sequence = 0;

  static String start(int tripId, {required String source}) {
    final previous = _traceByTrip[tripId];
    if (previous != null) {
      event(previous, 'trace_superseded');
      _traces.remove(previous);
    }

    final traceId =
        'td-${DateTime.now().millisecondsSinceEpoch}-${++_sequence}';
    _traceByTrip[tripId] = traceId;
    _traces[traceId] = _TripDetailTraceState(tripId);
    event(traceId, 'trace_started', fields: {'source': source});
    return traceId;
  }

  static String ensureForTrip(int tripId, {required String source}) {
    return _traceByTrip[tripId] ?? start(tripId, source: source);
  }

  static String? traceForTrip(int tripId) => _traceByTrip[tripId];

  static void eventForTrip(
    int tripId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) {
    final traceId = _traceByTrip[tripId];
    if (traceId != null) event(traceId, stage, fields: fields);
  }

  static void event(
    String? traceId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) {
    if (traceId == null) return;
    final trace = _traces[traceId];
    if (trace == null) return;

    final elapsedMs = trace.stopwatch.elapsedMicroseconds / 1000;
    final details = StringBuffer(
      '$prefix trace=$traceId trip=${trace.tripId} '
      'elapsed_ms=${elapsedMs.toStringAsFixed(1)} stage=$stage',
    );
    for (final entry in fields.entries) {
      details.write(' ${entry.key}=${entry.value}');
    }
    developer.log(details.toString(), name: loggerName);
  }

  static void finish(String? traceId, {required String reason}) {
    if (traceId == null) return;
    final trace = _traces[traceId];
    if (trace == null) return;
    event(traceId, 'trace_finished', fields: {'reason': reason});
    _traces.remove(traceId);
    if (_traceByTrip[trace.tripId] == traceId) {
      _traceByTrip.remove(trace.tripId);
    }
  }
}

class _TripDetailTraceState {
  final int tripId;
  final Stopwatch stopwatch = Stopwatch()..start();

  _TripDetailTraceState(this.tripId);
}

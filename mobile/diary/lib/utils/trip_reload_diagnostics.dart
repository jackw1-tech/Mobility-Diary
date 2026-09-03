import 'package:diary/utils/diagnostics_tracer.dart';

/// Traccia temporanea del caricamento diretto di una traccia riutilizzabile
/// (pulsante "Carica" del drawer): scelta dello slot, POST di reload, viaggio
/// derivato e apertura del dettaglio.
///
/// Stessa logica della traccia Dettaglio Viaggio: la traccia e' indicizzata sull'id
/// del viaggio sorgente, cosi' i layer piu' bassi (cubit, repository, service)
/// possono loggare senza ricevere il trace id per parametro. I messaggi
/// contengono solo ID tecnici, conteggi e durate: mai token, header, body
/// HTTP, coordinate o dati dell'utente.
class TripReloadDiagnostics {
  static const String prefix = '[DEBUG-TRIP-RELOAD-b4e1]';
  static const String loggerName = 'mobility.trip_reload';

  static final DiagnosticsTracer tracer = DiagnosticsTracer(
    prefix: prefix,
    loggerName: loggerName,
    tracePrefix: 'tr',
    idField: 'source_trip',
  );

  static String start(int sourceTripId, {required String source}) =>
      tracer.start(sourceTripId, source: source);

  static String ensureForTrip(int sourceTripId, {required String source}) =>
      tracer.ensureFor(sourceTripId, source: source);

  static String? traceForTrip(int sourceTripId) =>
      tracer.traceFor(sourceTripId);

  static void eventForTrip(
    int sourceTripId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) =>
      tracer.eventFor(sourceTripId, stage, fields: fields);

  static void event(
    String? traceId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) =>
      tracer.event(traceId, stage, fields: fields);

  static void finish(String? traceId, {required String reason}) =>
      tracer.finish(traceId, reason: reason);
}

import 'package:diary/utils/diagnostics_tracer.dart';

/// Traccia temporanea del percorso Dettaglio Viaggio.
///
/// I messaggi contengono solo ID tecnici, conteggi e durate: mai token,
/// header, body HTTP, coordinate o dati dell'utente. Il prefisso permette di
/// estrarre l'intera traccia con un solo filtro dai log del dispositivo.
class TripDetailDiagnostics {
  static const String prefix = '[DEBUG-TRIP-DETAIL-a7f3]';
  static const String loggerName = 'mobility.trip_detail';

  static final DiagnosticsTracer tracer = DiagnosticsTracer(
    prefix: prefix,
    loggerName: loggerName,
    tracePrefix: 'td',
  );

  static String start(int tripId, {required String source}) =>
      tracer.start(tripId, source: source);

  static String ensureForTrip(int tripId, {required String source}) =>
      tracer.ensureFor(tripId, source: source);

  static String? traceForTrip(int tripId) => tracer.traceFor(tripId);

  static void eventForTrip(
    int tripId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) =>
      tracer.eventFor(tripId, stage, fields: fields);

  static void event(
    String? traceId,
    String stage, {
    Map<String, Object?> fields = const {},
  }) =>
      tracer.event(traceId, stage, fields: fields);

  static void finish(String? traceId, {required String reason}) =>
      tracer.finish(traceId, reason: reason);
}

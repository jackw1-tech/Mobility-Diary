/// Coda di sincronizzazione dei viaggi verso il backend.
///
/// Lo STOP del viaggio si limita a creare un SyncJob persistente e a "kick"are
/// la coda, senza attendere la rete (REPORT_STRATEGIA_UPLOAD_ASINCRONA.md D5).
/// L'implementazione concreta (packaging + upload presigned + polling) vive in
/// [TripSyncQueueImpl] ed e' introdotta nello step successivo.
abstract class TripSyncQueue {
  /// Avvia, se non gia' in corso, l'elaborazione opportunistica dei SyncJob
  /// pronti. Fire-and-forget: non va atteso dal chiamante.
  Future<void> kick();
}

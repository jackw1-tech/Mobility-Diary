import 'package:diary/model/entities/acquisition/acquisition_domain.dart';

class ActiveTripOnAnotherDeviceException implements Exception {
  static const defaultMessage =
      "Hai gia' un viaggio in corso su un altro dispositivo";

  final String message;

  const ActiveTripOnAnotherDeviceException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

class PendingTripSyncException implements Exception {
  static const defaultMessage =
      'Hai un viaggio in chiusura. Attendi la sincronizzazione prima di iniziarne un altro.';

  final String message;

  const PendingTripSyncException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

class StartRequiresConnectionException implements Exception {
  static const defaultMessage =
      'Serve connessione al backend per avviare un nuovo viaggio.';

  final String message;

  const StartRequiresConnectionException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

class AcquisitionPermissionException implements Exception {
  static const defaultMessage =
      'Per registrare un viaggio serve il permesso di posizione "Sempre": '
      'impostalo dalle impostazioni del telefono.';

  final String message;

  const AcquisitionPermissionException([this.message = defaultMessage]);

  @override
  String toString() => message;
}

abstract class AcquisitionTrackingRepository {
  Stream<AcquisitionSnapshot> get snapshots;

  AcquisitionSnapshot get currentSnapshot;

  Future<void> startTracking();

  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  });

  Future<ReplayStopResult> stopReplay();

  Future<void> stopTracking();

  Future<void> ingestEvent(TrackingEvent event);

  /// Percorso GPS accettato della sessione di tracking attualmente ripristinata,
  /// in ordine cronologico. Vuoto se non si sta tracciando. Serve a ridisegnare
  /// subito la polyline sulla mappa quando si riapre l'app su un viaggio in corso.
  Future<List<AcquisitionRoutePoint>> currentSessionRoute();

  /// Ultima finestra sensori (500x6) della sessione di tracking reale in corso,
  /// per la classificazione live dell'assistente di percorso. Vuota se non c'e'
  /// un Viaggio in Corso reale (il replay non persiste su SQLite).
  Future<List<List<double>>> currentSensorWindow();

  void dispose();
}

abstract class AcquisitionSyncRepository {
  Stream<AcquisitionSyncSnapshot> get syncSnapshots;

  AcquisitionSyncSnapshot get currentSyncSnapshot;

  /// Riprende in modo opportunistico la sincronizzazione dei SyncJob pendenti
  /// (es. all'avvio app). Non blocca: la coda lavora in background.
  Future<void> resumeSync();
}

abstract class AcquisitionLocalTripPurger {
  /// Ripulisce l'eventuale sessione locale residua di un Trip appena
  /// eliminato dal backend. Normalmente non c'e' nulla da fare (un fallimento
  /// definitivo si scarta gia' da solo, una sync riuscita pulisce gia' tutto),
  /// ma l'utente puo' eliminare un Trip mentre il suo raw e' ancora in coda
  /// (non ancora fallito ne' completato): in quel caso va ripulita anche
  /// quella. No-op se non esiste nessuna sessione locale per quel Trip.
  Future<void> purgeLocalDataForRemoteTrip(int tripId);
}

abstract class AcquisitionRepository
    implements
        AcquisitionTrackingRepository,
        AcquisitionSyncRepository,
        AcquisitionLocalTripPurger {}

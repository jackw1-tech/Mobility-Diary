import 'dart:async';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

class AcquisitionCubit extends Cubit<AcquisitionCubitState> {
  final AcquisitionTrackingRepository _trackingRepository;
  final AcquisitionSyncRepository _syncRepository;
  late final StreamSubscription<AcquisitionSnapshot> _snapshotSubscription;
  late final StreamSubscription<AcquisitionSyncSnapshot>
      _syncSnapshotSubscription;

  Future<void>? _restoreInFlight;

  // Flag per indicare che il prossimo snapshot deve resettare i punti disegnati sulla mappa
  bool _resetRouteOnNextSnapshot = false;
  // Flag per indicare che  ...
  bool _clearCompletedReplayOnNextSnapshot = false;

  AcquisitionCubit({
    required AcquisitionTrackingRepository trackingRepository,
    required AcquisitionSyncRepository syncRepository,
  })  : _trackingRepository = trackingRepository,
        _syncRepository = syncRepository,
        super(
          AcquisitionCubitState.fromSnapshot(
            trackingRepository.currentSnapshot,
            syncSnapshot: syncRepository.currentSyncSnapshot,
          ),
        ) {
    _snapshotSubscription = _trackingRepository.snapshots.listen(_onSnapshot);
    _syncSnapshotSubscription =
        _syncRepository.syncSnapshots.listen(_emitSyncSnapshot);

    //Prova fin dall'inizializzazione a ripristinare un viaggio in corso
    unawaited(_restoreAndResume());
  }

  /// Ogni volta che faccio l'autologin viene eseguita
  Future<void> restoreActiveTrip() => _restoreAndResume();

  /// Controlla se ci sono viaggi ancora in corso oppure upload di viaggi in sospeso
  Future<void> _restoreAndResume() {
    if (_restoreInFlight != null) {
      return _restoreInFlight!;
    }

    final restore = _runRestoreAndResume();
    _restoreInFlight = restore;

    // Quando il restore finisce (successo o errore), liberiamo lo slot cosi'
    // una chiamata futura ne potra' avviare uno nuovo.
    restore.whenComplete(() {
      _restoreInFlight = null;
    });

    return restore;
  }

  // Controlla se ci sono upload da completare
  // Dopo controlla se ci sono viaggi in corso
  Future<void> _runRestoreAndResume() async {
    await _syncRepository.resumeSync();
    await _restoreRouteFromRestoredSession();
  }

  Future<void> _restoreRouteFromRestoredSession() async {
    if (!_trackingRepository.currentSnapshot.isTracking) {
      return;
    }
    final route = await _trackingRepository.currentSessionRoute();
    if (isClosed) {
      return;
    }
    // Ricostruisce la polyline della sessione di tracking attuale
    emit(
      state.copyWith(
        routePoints: [
          for (final point in route) LatLng(point.latitude, point.longitude),
        ],
      ),
    );
  }

  Future<void> startTracking() async {
    if (_trackingRepository.currentSnapshot.isTracking) {
      return;
    }
    _prepareFreshAcquisitionState();
    try {
      await _trackingRepository.startTracking();
    } catch (error) {
      _cancelFreshAcquisitionState();
      emit(state.copyWith(errorMessage: error.toString()));
      rethrow;
    }
  }

  Future<AcquisitionDiagnosticsReport?> stopTracking() async {
    if (state.isReplay) {
      await stopReplay();
      return null;
    }
    return _trackingRepository.stopTracking();
  }

  Future<void> ingestEvent(TrackingEvent event) async {
    await _trackingRepository.ingestEvent(event);
  }

  bool _isStoppingReplay = false;
  bool _isStartingReplay = false;

  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  }) async {
    if (_trackingRepository.currentSnapshot.isTracking) {
      return;
    }
    _prepareFreshAcquisitionState();
    _isStartingReplay = true;
    try {
      await _trackingRepository.startReplay(
        sourceTripId,
        scheduledStartAt: scheduledStartAt,
        replaySpeedMultiplier: replaySpeedMultiplier,
      );
      _isStartingReplay = false;
      _isStoppingReplay = false;
      _stopReplayIfCompleted(_trackingRepository.currentSnapshot);
    } catch (error) {
      _isStartingReplay = false;
      _cancelFreshAcquisitionState();
      emit(state.copyWith(errorMessage: error.toString()));
      rethrow;
    }
  }

  Future<void> stopReplay() async {
    if (_isStoppingReplay) return;
    _isStoppingReplay = true;
    try {
      final result = await _trackingRepository.stopReplay();
      emit(state.copyWith(completedReplayTripId: result.tripId));
    } catch (error) {
      _isStoppingReplay = false;
      emit(state.copyWith(errorMessage: error.toString()));
      rethrow;
    }
  }

  // Azzera lo stato del cubit, lo si fa quando avvio un nuovo replay o un nuovo
  // tracking live
  void _prepareFreshAcquisitionState() {
    _resetRouteOnNextSnapshot = true;
    _clearCompletedReplayOnNextSnapshot = true;
  }

  // Ripristina lo stato del cubit allo snapshot corrente senza modifiche
  void _cancelFreshAcquisitionState() {
    _resetRouteOnNextSnapshot = false;
    _clearCompletedReplayOnNextSnapshot = false;
  }

  // Primo snapshot? -> reset dei punti disegnati sulla mappa
  // Altro snapshot? -> aggiorna i punti disegnati sulla mappa
  void _onSnapshot(AcquisitionSnapshot snapshot) {
    final resetRoute = _resetRouteOnNextSnapshot;
    final clearCompletedReplayTripId = _clearCompletedReplayOnNextSnapshot;
    _cancelFreshAcquisitionState();
    _emitSnapshot(
      snapshot,
      resetRoute: resetRoute,
      clearCompletedReplayTripId: clearCompletedReplayTripId,
    );
  }

  void _stopReplayIfCompleted(AcquisitionSnapshot snapshot) {
    if (snapshot.isTracking &&
        snapshot.replaySecondsRemaining == 0 &&
        !_isStartingReplay &&
        !_isStoppingReplay) {
      unawaited(stopReplay());
    }
  }

// Funzione che o aggiorna i punti della polyline o li resetta
  void _emitSnapshot(
    AcquisitionSnapshot snapshot, {
    bool resetRoute = false,
    bool clearCompletedReplayTripId = false,
  }) {
    _stopReplayIfCompleted(snapshot);

    final routePoints = resetRoute ? <LatLng>[] : _updatedRoutePoints(snapshot);
    emit(
      AcquisitionCubitState.fromSnapshot(
        snapshot,
        syncSnapshot: state.syncSnapshot,
        routePoints: routePoints,
        completedReplayTripId:
            clearCompletedReplayTripId ? null : state.completedReplayTripId,
      ),
    );
  }

  /// Aggiunge il nuovo GPS alla route
  List<LatLng> _updatedRoutePoints(AcquisitionSnapshot snapshot) {
    if (!snapshot.isTracking || !snapshot.hasPosition) {
      return state.routePoints;
    }

    final next = LatLng(snapshot.latitude!, snapshot.longitude!);
    final current = state.routePoints;
    if (current.isNotEmpty &&
        current.last.latitude == next.latitude &&
        current.last.longitude == next.longitude) {
      return current;
    }

    return List<LatLng>.from(current)..add(next);
  }

  void _emitSyncSnapshot(AcquisitionSyncSnapshot snapshot) {
    emit(state.copyWith(syncSnapshot: snapshot));
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription.cancel();
    await _syncSnapshotSubscription.cancel();
    return super.close();
  }
}

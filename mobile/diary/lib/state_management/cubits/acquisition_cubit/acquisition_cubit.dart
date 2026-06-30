import 'dart:async';

import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart';

class AcquisitionCubit extends Cubit<AcquisitionCubitState> {
  static const int _maxMetricClusters = 60;
  static const Duration _metricClusterDuration = Duration(seconds: 1);

  final AcquisitionRepository _repository;
  late final StreamSubscription<AcquisitionSnapshot> _snapshotSubscription;
  late final StreamSubscription<AcquisitionSyncSnapshot>
      _syncSnapshotSubscription;

  /// Ripristino in corso: coalescenza delle chiamate sovrapposte (costruttore +
  /// trigger post-autologin) per evitare due `resumeSync` concorrenti.
  Future<void>? _restoreInFlight;

  AcquisitionCubit(this._repository)
      : super(
          AcquisitionCubitState.fromSnapshot(
            _repository.currentSnapshot,
            syncSnapshot: _repository.currentSyncSnapshot,
          ),
        ) {
    _snapshotSubscription = _repository.snapshots.listen(_emitSnapshot);
    _syncSnapshotSubscription =
        _repository.syncSnapshots.listen(_emitSyncSnapshot);
    // All'avvio (post-login) riprende eventuali upload rimasti in sospeso e
    // ripristina sulla mappa il percorso di un eventuale viaggio in corso.
    unawaited(_restoreAndResume());
  }

  /// Da invocare a ogni avvio autenticato (incluso l'autologin): verifica se
  /// esiste un viaggio in corso per questo dispositivo e, se device id e
  /// sessione SQLite corrispondono, lo riprende ridisegnando il percorso sulla
  /// mappa. Idempotente: se si sta gia' tracciando non riavvia nulla.
  Future<void> restoreActiveTrip() => _restoreAndResume();

  /// Riprende la sync pendente e, se l'app si riapre su un viaggio ancora in
  /// corso (stesso dispositivo, sessione locale presente), ridisegna subito il
  /// percorso accumulato finora ripopolando `routePoints`. Le chiamate
  /// sovrapposte condividono lo stesso Future per non eseguire `resumeSync` in
  /// parallelo; una chiamata successiva a ripristino concluso ne avvia uno nuovo.
  Future<void> _restoreAndResume() {
    return _restoreInFlight ??= _runRestoreAndResume().whenComplete(() {
      _restoreInFlight = null;
    });
  }

  Future<void> _runRestoreAndResume() async {
    await _repository.resumeSync();
    await _restoreRouteFromRestoredSession();
  }

  Future<void> _restoreRouteFromRestoredSession() async {
    if (!_repository.currentSnapshot.isTracking) {
      return;
    }
    final route = await _repository.currentSessionRoute();
    // Il ripristino e' fire-and-forget dal costruttore: se il cubit e' stato
    // chiuso durante gli await (logout/navigazione) non dobbiamo emettere.
    if (isClosed) {
      return;
    }
    // Se nel frattempo sono gia' arrivati fix live piu' recenti, non li
    // sovrascriviamo: il percorso ripristinato serve solo a riempire il vuoto
    // iniziale lasciato dallo snapshot di resume (una sola posizione).
    if (route.length <= state.routePoints.length) {
      return;
    }
    emit(
      state.copyWith(
        routePoints: [
          for (final point in route) LatLng(point.latitude, point.longitude),
        ],
      ),
    );
  }

  Future<void> startTracking() async {
    try {
      await _repository.startTracking();
      _emitSnapshot(_repository.currentSnapshot, resetMetrics: true);
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
      rethrow;
    }
  }

  Future<void> stopTracking() async {
    await _repository.stopTracking();
    _emitSnapshot(_repository.currentSnapshot);
  }

  Future<void> ingestEvent(TrackingEvent event) async {
    await _repository.ingestEvent(event);
    _emitSnapshot(_repository.currentSnapshot);
  }

  Future<void> resumeSync() async {
    await _repository.resumeSync();
  }

  void dismissNonRecoverableSync() {
    if (state.syncSnapshot.isNonRecoverable) {
      emit(state.copyWith(syncSnapshot: const AcquisitionSyncSnapshot.none()));
    }
  }

  bool _isStoppingReplay = false;

  Future<void> startReplay(int sourceTripId) async {
    try {
      await _repository.startReplay(sourceTripId);
      _isStoppingReplay = false;
      _emitSnapshot(_repository.currentSnapshot, resetMetrics: true);
    } catch (error) {
      emit(state.copyWith(errorMessage: error.toString()));
      rethrow;
    }
  }

  Future<void> stopReplay() async {
    if (_isStoppingReplay) return;
    _isStoppingReplay = true;
    try {
      final result = await _repository.stopReplay();
      emit(state.copyWith(completedReplayTripId: result.tripId));
      _emitSnapshot(_repository.currentSnapshot);
    } catch (error) {
      _isStoppingReplay = false;
      emit(state.copyWith(errorMessage: error.toString()));
      rethrow;
    }
  }

  void _emitSnapshot(
    AcquisitionSnapshot snapshot, {
    bool resetMetrics = false,
  }) {
    if (snapshot.isTracking &&
        snapshot.replaySecondsRemaining == 0 &&
        !_isStoppingReplay) {
      unawaited(stopReplay());
    }

    final metricClusters = resetMetrics
        ? <AcquisitionMetricCluster>[]
        : _updatedMetricClusters(snapshot);
    final routePoints =
        resetMetrics ? <LatLng>[] : _updatedRoutePoints(snapshot);
    emit(
      AcquisitionCubitState.fromSnapshot(
        snapshot,
        syncSnapshot: state.syncSnapshot,
        metricClusters: metricClusters,
        routePoints: routePoints,
        completedReplayTripId: state.completedReplayTripId,
      ),
    );
  }

  /// Aggiunge il nuovo fix GPS alla route, scartando i duplicati consecutivi
  /// (lo snapshot viene riemesso anche per eventi non-GPS, mantenendo l'ultima
  /// posizione nota).
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

  List<AcquisitionMetricCluster> _updatedMetricClusters(
    AcquisitionSnapshot snapshot,
  ) {
    if (!snapshot.isTracking) {
      return state.metricClusters;
    }

    final clusters = List<AcquisitionMetricCluster>.from(
      state.metricClusters,
    );

    if (clusters.isNotEmpty &&
        snapshot.updatedAt.difference(clusters.first.startedAt) <
            _metricClusterDuration) {
      clusters[0] = clusters.first.merge(snapshot);
    } else {
      clusters.insert(0, AcquisitionMetricCluster.fromSnapshot(snapshot));
    }

    if (clusters.length > _maxMetricClusters) {
      return clusters.take(_maxMetricClusters).toList(growable: false);
    }

    return clusters;
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription.cancel();
    await _syncSnapshotSubscription.cancel();
    return super.close();
  }
}

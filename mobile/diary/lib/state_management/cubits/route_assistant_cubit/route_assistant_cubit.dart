import 'dart:async';

import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/repositories/route_assistant_repository.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Assistente di percorso, completamente separato dall'AcquisitionCubit.
/// Il punto A e' la posizione attiva della sessione, quando disponibile, oppure
/// la posizione GPS corrente (via `_locationProvider`); il punto B arriva dal
/// geocoding. Il percorso e' effimero: chiudendo si azzera tutto.
///
/// In modalita' Live la modalita' di mobilita' e' riconosciuta ogni
/// [_tickInterval] classificando la finestra sensori di `_sensorWindowProvider`.
class RouteAssistantCubit extends Cubit<RouteAssistantState> {
  final RouteAssistantRepository _repository;
  final Future<ll.LatLng?> Function() _locationProvider;
  final ll.LatLng? Function()? _activeLocationProvider;
  final Future<List<List<double>>> Function() _sensorWindowProvider;
  final Duration _tickInterval;
  int _searchGeneration = 0;
  int _routeGeneration = 0;
  Timer? _liveTimer;
  bool _passiveModeDetectionEnabled = false;
  RouteMode? _lastDetectedMode;
  bool _hasLastDetectedModeResult = false;

  RouteAssistantCubit(
    this._repository, {
    required Future<ll.LatLng?> Function() locationProvider,
    ll.LatLng? Function()? activeLocationProvider,
    required Future<List<List<double>>> Function() sensorWindowProvider,
    Duration tickInterval = const Duration(seconds: 15),
  })  : _locationProvider = locationProvider,
        _activeLocationProvider = activeLocationProvider,
        _sensorWindowProvider = sensorWindowProvider,
        _tickInterval = tickInterval,
        super(const RouteAssistantState());

  void openSearch() => emit(state.copyWith(isSearchOpen: true));

  void closeSearch() => emit(state.copyWith(isSearchOpen: false));

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      _searchGeneration++;
      emit(state.copyWith(
        searchResults: const [],
        isSearching: false,
        clearError: true,
      ));
      return;
    }
    final generation = ++_searchGeneration;
    emit(state.copyWith(isSearching: true, clearError: true));
    try {
      final proximity = await _currentOrigin();
      final result =
          await _repository.searchPlaces(query, proximity: proximity);
      if (isClosed || generation != _searchGeneration) return;
      final failure = result.failure;
      if (failure != null) {
        emit(state.copyWith(
          isSearching: false,
          errorMessage: failure.message,
        ));
        return;
      }
      emit(state.copyWith(
        searchResults: result.requireValue,
        isSearching: false,
      ));
    } catch (error) {
      if (isClosed || generation != _searchGeneration) return;
      emit(state.copyWith(isSearching: false, errorMessage: error.toString()));
    }
  }

  void selectDestination(GeocodingPlace place) =>
      emit(state.copyWith(destination: place));

  /// "Vai": chiude la ricerca e calcola il percorso verso la destinazione.
  Future<void> confirmDestination() async {
    if (state.destination == null) return;
    emit(state.copyWith(
      isSearchOpen: false,
      mode: _initialRouteMode(),
    ));
    await _fetchRoute();
  }

  Future<void> setMode(RouteMode mode) async {
    if (mode == state.mode) return;
    emit(state.copyWith(mode: mode));
    if (state.destination != null) await _fetchRoute();
  }

  /// Accende/spegne la modalita' Live. Il timer di ricalcolo (avviato al primo
  /// percorso) continua a girare: Live ON aggiunge la classificazione sensori
  /// prima di ogni ricalcolo periodico.
  void toggleLive() {
    if (state.isLive) {
      emit(state.copyWith(isLive: false, clearDetected: true));
      return;
    }
    emit(state.copyWith(isLive: true));
    _tick(); // classifica e ricalcola subito senza aspettare il prossimo tick
  }

  void _ensureTimer() {
    if (_liveTimer != null) return;
    _liveTimer = Timer.periodic(_tickInterval, (_) => _tick());
  }

  void setPassiveModeDetectionEnabled(bool enabled) {
    if (_passiveModeDetectionEnabled == enabled) return;
    _passiveModeDetectionEnabled = enabled;
    if (enabled) {
      _emitPassiveModeSeed();
      _ensureTimer();
      unawaited(_tick());
    } else {
      if (!state.isActive) emit(state.copyWith(clearDetected: true));
      _stopTimerIfIdle();
    }
  }

  void clearDetectedModePrediction() {
    _lastDetectedMode = null;
    _hasLastDetectedModeResult = false;
    if (state.detectedMode != null || state.hasDetectedModeResult) {
      emit(state.copyWith(clearDetected: true));
    }
  }

  /// Tick periodico: se Live e' ON classifica prima e aggiorna il profilo;
  /// poi ricalcola sempre il percorso per seguire il movimento dell'utente.
  Future<void> _tick() async {
    if (isClosed) return;
    final shouldClassifyForLive = state.isActive && state.isLive;
    final shouldClassifyForIndicator =
        _passiveModeDetectionEnabled && !state.isActive;
    final shouldFetchRoute = state.isActive;
    if (!shouldClassifyForLive &&
        !shouldClassifyForIndicator &&
        !shouldFetchRoute) {
      _stopTimerIfIdle();
      return;
    }
    try {
      if (shouldClassifyForLive || shouldClassifyForIndicator) {
        await _classifyCurrentMode(updateRouteMode: shouldClassifyForLive);
      }
      if (isClosed || !shouldFetchRoute) return;
      if (state.isActive) await _fetchRoute();
    } catch (_) {
      // ignora: il prossimo tick riprovera'
    } finally {
      _stopTimerIfIdle();
    }
  }

  /// Chiude l'assistente: ferma il Live, invalida le richieste in volo (ricerca
  /// e routing) e azzera tutto lo stato.
  void dismiss() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _passiveModeDetectionEnabled = false;
    _searchGeneration++;
    _routeGeneration++;
    emit(const RouteAssistantState());
  }

  @override
  Future<void> close() {
    _liveTimer?.cancel();
    _passiveModeDetectionEnabled = false;
    return super.close();
  }

  Future<void> _fetchRoute() async {
    final destination = state.destination;
    if (destination == null) return;
    // Una nuova richiesta (o un dismiss) invalida quelle in volo: cosi' una
    // risposta tardiva non riattiva l'assistente dopo la chiusura.
    final generation = ++_routeGeneration;
    final from = await _currentOrigin();
    if (isClosed || generation != _routeGeneration) return;
    if (from == null) {
      emit(state.copyWith(
        isRouting: false,
        errorMessage: 'Posizione corrente non disponibile',
      ));
      return;
    }
    emit(state.copyWith(isRouting: true, clearError: true));
    try {
      final result = await _repository.fetchRoute(
        from: from,
        to: destination.location,
        mode: state.mode,
      );
      if (isClosed || generation != _routeGeneration) return;
      final failure = result.failure;
      if (failure != null) {
        emit(state.copyWith(
          isRouting: false,
          errorMessage: failure.message,
        ));
        return;
      }
      emit(state.copyWith(
        route: result.requireValue,
        routeUpdatedAt: DateTime.now(),
        isRouting: false,
      ));
      _ensureTimer(); // avvia il tick periodico al primo percorso calcolato
    } catch (error) {
      if (isClosed || generation != _routeGeneration) return;
      emit(state.copyWith(isRouting: false, errorMessage: error.toString()));
    }
  }

  Future<ll.LatLng?> _currentOrigin() async {
    return _activeLocationProvider?.call() ?? await _locationProvider();
  }

  RouteMode _initialRouteMode() {
    if (state.isActive || !state.hasDetectedModeResult) return state.mode;
    return state.detectedMode ?? state.mode;
  }

  void _emitPassiveModeSeed() {
    if (!_hasLastDetectedModeResult) {
      emit(state.copyWith(clearDetected: true));
      return;
    }
    if (_lastDetectedMode == null) {
      emit(state.copyWith(
        clearDetected: true,
        hasDetectedModeResult: true,
      ));
      return;
    }
    emit(state.copyWith(
      detectedMode: _lastDetectedMode,
      hasDetectedModeResult: true,
    ));
  }

  Future<void> _classifyCurrentMode({required bool updateRouteMode}) async {
    final samples = await _sensorWindowProvider();
    if (isClosed ||
        samples.isEmpty ||
        !_classificationStillRelevant(
          updateRouteMode,
        )) {
      return;
    }
    final result = await _repository.classify(samples);
    if (isClosed || !_classificationStillRelevant(updateRouteMode)) return;
    final failure = result.failure;
    if (failure != null) throw failure;
    final detected = result.value;
    if (detected == null) {
      _rememberDetectedMode(null);
      emit(state.copyWith(
        clearDetected: true,
        hasDetectedModeResult: true,
      ));
      return;
    }
    _rememberDetectedMode(detected);
    emit(state.copyWith(
      detectedMode: detected,
      hasDetectedModeResult: true,
      mode: updateRouteMode ? detected : null,
    ));
  }

  void _rememberDetectedMode(RouteMode? detected) {
    _lastDetectedMode = detected;
    _hasLastDetectedModeResult = true;
  }

  bool _classificationStillRelevant(bool updateRouteMode) {
    return updateRouteMode
        ? state.isActive && state.isLive
        : _passiveModeDetectionEnabled && !state.isActive;
  }

  void _stopTimerIfIdle() {
    if (_passiveModeDetectionEnabled || state.isActive) return;
    _liveTimer?.cancel();
    _liveTimer = null;
  }
}

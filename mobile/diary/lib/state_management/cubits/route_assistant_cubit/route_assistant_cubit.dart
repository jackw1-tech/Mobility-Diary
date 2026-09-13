import 'dart:async';

import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/repositories/route_assistant_repository.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart' as ll;

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
  int _classificationTick = 0;

  RouteAssistantCubit(
    this._repository, {
    required Future<ll.LatLng?> Function() locationProvider,
    ll.LatLng? Function()? activeLocationProvider,
    required Future<List<List<double>>> Function() sensorWindowProvider,
    Duration tickInterval = const Duration(seconds: 15),
  }) : _locationProvider = locationProvider,
       _activeLocationProvider = activeLocationProvider,
       _sensorWindowProvider = sensorWindowProvider,
       _tickInterval = tickInterval,
       super(const RouteAssistantState.initial());

  void openSearch() => emit(state.copyWith(isSearchOpen: true));

  void closeSearch() => emit(state.copyWith(isSearchOpen: false));

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      _searchGeneration++;
      emit(
        state.copyWith(
          searchStatus: RouteAssistantSearchStatus.initial,
          searchResults: const [],
          clearSearchError: true,
        ),
      );
      return;
    }
    final generation = ++_searchGeneration;
    emit(
      state.copyWith(
        searchStatus: RouteAssistantSearchStatus.loading,
        clearSearchError: true,
      ),
    );
    try {
      final proximity = await _currentOrigin();
      final result = await _repository.searchPlaces(
        query,
        proximity: proximity,
      );
      if (isClosed || generation != _searchGeneration) return;
      final failure = result.failure;
      if (failure != null) {
        emit(
          state.copyWith(
            searchStatus: RouteAssistantSearchStatus.error,
            searchError: failure.message,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          searchStatus: RouteAssistantSearchStatus.loaded,
          searchResults: result.requireValue,
          clearSearchError: true,
        ),
      );
    } catch (error) {
      if (isClosed || generation != _searchGeneration) return;
      emit(
        state.copyWith(
          searchStatus: RouteAssistantSearchStatus.error,
          searchError: error.toString(),
        ),
      );
    }
  }

  void selectDestination(GeocodingPlace place) =>
      emit(state.copyWith(destination: place));

  Future<void> confirmDestination() async {
    if (state.destination == null) return;
    emit(state.copyWith(isSearchOpen: false, mode: _initialRouteMode()));
    await _fetchRoute();
  }

  Future<void> setMode(RouteMode mode) async {
    if (mode == state.mode) return;
    emit(state.copyWith(mode: mode));
    if (state.destination != null) await _fetchRoute();
  }

  void toggleLive() {
    if (state.isLive) {
      emit(state.copyWith(isLive: false, clearDetected: true));
      return;
    }
    emit(state.copyWith(isLive: true));
    _tick();
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

  Future<void> _tick() async {
    if (isClosed) return;
    // Route assistant attivo e l'utente ha cliccato il tasto live nella modalità di spostamento
    final shouldClassifyForLive = state.isActive && state.isLive;
    // Route assistant non attivo ma viaggio vero o replay in corso
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
      //Prima chiedo la nuova classificazione
      if (shouldClassifyForLive || shouldClassifyForIndicator) {
        await _classifyCurrentMode(updateRouteMode: shouldClassifyForLive);
      }
      if (isClosed || !shouldFetchRoute) return;
      //E poi, con la nuova modalità di movimentorielvata, rifaccio la chiamata a mapbox per la rotta
      if (state.isActive) await _fetchRoute();
    } catch (_) {
    } finally {
      _stopTimerIfIdle();
    }
  }

  void dismiss() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _passiveModeDetectionEnabled = false;
    _searchGeneration++;
    _routeGeneration++;
    emit(const RouteAssistantState.initial());
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
    final generation = ++_routeGeneration;
    final from = await _currentOrigin();
    if (isClosed || generation != _routeGeneration) return;
    if (from == null) {
      emit(
        state.copyWith(
          routeStatus: RouteAssistantRouteStatus.error,
          routeError: 'Posizione corrente non disponibile',
        ),
      );
      return;
    }
    emit(
      state.copyWith(
        routeStatus: RouteAssistantRouteStatus.loading,
        clearRouteError: true,
      ),
    );
    try {
      final result = await _repository.fetchRoute(
        from: from,
        to: destination.location,
        mode: state.mode,
      );
      if (isClosed || generation != _routeGeneration) return;
      final failure = result.failure;
      if (failure != null) {
        emit(
          state.copyWith(
            routeStatus: RouteAssistantRouteStatus.error,
            routeError: failure.message,
          ),
        );
        return;
      }
      emit(
        state.copyWith(
          routeStatus: RouteAssistantRouteStatus.loaded,
          route: result.requireValue,
          routeUpdatedAt: DateTime.now(),
          clearRouteError: true,
        ),
      );
      _ensureTimer();
    } catch (error) {
      if (isClosed || generation != _routeGeneration) return;
      emit(
        state.copyWith(
          routeStatus: RouteAssistantRouteStatus.error,
          routeError: error.toString(),
        ),
      );
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
      emit(state.copyWith(clearDetected: true, hasDetectedModeResult: true));
      return;
    }
    emit(
      state.copyWith(
        detectedMode: _lastDetectedMode,
        hasDetectedModeResult: true,
      ),
    );
  }

  // Funzione da cui parte la classificazione degli ultimi 5 secondi di viaggio
  Future<void> _classifyCurrentMode({required bool updateRouteMode}) async {
    final samples = await _sensorWindowProvider();
    //Meccanismo di sicurezz
    if (isClosed ||
        samples.isEmpty ||
        !_classificationStillRelevant(updateRouteMode)) {
      return;
    }
    final result = await _repository.classify(samples);
    if (isClosed || !_classificationStillRelevant(updateRouteMode)) return;
    final failure = result.failure;
    if (failure != null) throw failure;
    final detected = result.value;
    _classificationTick++;
    if (detected == null) {
      _rememberDetectedMode(null);
      emit(
        state.copyWith(
          clearDetected: true,
          hasDetectedModeResult: true,
          classificationTick: _classificationTick,
        ),
      );
      return;
    }
    _rememberDetectedMode(detected);
    emit(
      state.copyWith(
        detectedMode: detected,
        hasDetectedModeResult: true,
        mode: updateRouteMode ? detected : null,
        classificationTick: _classificationTick,
      ),
    );
  }

  void _rememberDetectedMode(RouteMode? detected) {
    _lastDetectedMode = detected;
    _hasLastDetectedModeResult = true;
  }

  //Controllo ulteriore se la situazione non è cambiata che fa _classifyCurrentMode
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

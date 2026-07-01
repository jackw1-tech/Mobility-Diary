import 'dart:async';

import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/network/service/route_assistant_service.dart';
import 'package:diary/network/service/route_classifier_service.dart';
import 'package:diary/state_management/cubits/route_assistant_cubit/route_assistant_cubit_state.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Assistente di percorso, completamente separato dall'AcquisitionCubit.
/// Il punto A e' la posizione GPS corrente (via `_locationProvider`); il punto
/// B arriva dal geocoding. Il percorso e' effimero: chiudendo si azzera tutto.
///
/// In modalita' Live la modalita' di mobilita' e' riconosciuta ogni
/// [_tickInterval] classificando la finestra sensori di `_sensorWindowProvider`.
class RouteAssistantCubit extends Cubit<RouteAssistantState> {
  final RouteAssistantService _service;
  final RouteClassifierService _classifier;
  final Future<ll.LatLng?> Function() _locationProvider;
  final Future<List<List<double>>> Function() _sensorWindowProvider;
  final Duration _tickInterval;
  int _searchGeneration = 0;
  int _routeGeneration = 0;
  Timer? _liveTimer;

  RouteAssistantCubit(
    this._service, {
    required RouteClassifierService classifier,
    required Future<ll.LatLng?> Function() locationProvider,
    required Future<List<List<double>>> Function() sensorWindowProvider,
    Duration tickInterval = const Duration(seconds: 15),
  })  : _classifier = classifier,
        _locationProvider = locationProvider,
        _sensorWindowProvider = sensorWindowProvider,
        _tickInterval = tickInterval,
        super(const RouteAssistantState());

  void openSearch() => emit(state.copyWith(isSearchOpen: true));

  void closeSearch() => emit(state.copyWith(isSearchOpen: false));

  Future<void> search(String query) async {
    if (query.trim().isEmpty) {
      emit(state.copyWith(searchResults: const [], isSearching: false));
      return;
    }
    final generation = ++_searchGeneration;
    emit(state.copyWith(isSearching: true, clearError: true));
    try {
      final proximity = await _locationProvider();
      final results = await _service.searchPlaces(query, proximity: proximity);
      if (isClosed || generation != _searchGeneration) return;
      emit(state.copyWith(searchResults: results, isSearching: false));
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
    emit(state.copyWith(isSearchOpen: false));
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

  /// Tick periodico: se Live e' ON classifica prima e aggiorna il profilo;
  /// poi ricalcola sempre il percorso per seguire il movimento dell'utente.
  Future<void> _tick() async {
    if (isClosed || !state.isActive) return;
    try {
      if (state.isLive) {
        final samples = await _sensorWindowProvider();
        if (isClosed || !state.isActive) return;
        if (samples.isNotEmpty) {
          final detected = await _classifier.classify(samples);
          if (isClosed || !state.isActive) return;
          if (detected != null) {
            emit(state.copyWith(detectedMode: detected, mode: detected));
          }
        }
      }
      if (isClosed || !state.isActive) return;
      await _fetchRoute();
    } catch (_) {
      // ignora: il prossimo tick riprovera'
    }
  }

  /// Chiude l'assistente: ferma il Live, invalida le richieste in volo (ricerca
  /// e routing) e azzera tutto lo stato.
  void dismiss() {
    _liveTimer?.cancel();
    _liveTimer = null;
    _searchGeneration++;
    _routeGeneration++;
    emit(const RouteAssistantState());
  }

  @override
  Future<void> close() {
    _liveTimer?.cancel();
    return super.close();
  }

  Future<void> _fetchRoute() async {
    final destination = state.destination;
    if (destination == null) return;
    // Una nuova richiesta (o un dismiss) invalida quelle in volo: cosi' una
    // risposta tardiva non riattiva l'assistente dopo la chiusura.
    final generation = ++_routeGeneration;
    final from = await _locationProvider();
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
      final points = await _service.fetchRoute(
        from: from,
        to: destination.location,
        mode: state.mode,
      );
      if (isClosed || generation != _routeGeneration) return;
      emit(state.copyWith(routePoints: points, isRouting: false));
      _ensureTimer(); // avvia il tick periodico al primo percorso calcolato
    } catch (error) {
      if (isClosed || generation != _routeGeneration) return;
      emit(state.copyWith(isRouting: false, errorMessage: error.toString()));
    }
  }
}

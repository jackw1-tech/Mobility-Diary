import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:latlong2/latlong.dart' as ll;

/// Ricerca dei luoghi e calcolo del percorso sono due operazioni asincrone
/// indipendenti — possono essere in corso insieme — quindi hanno uno stato
/// ciascuna invece del singolo `status` degli altri cubit.
enum RouteAssistantSearchStatus {
  initial,
  loading,
  loaded,
  error,
}

enum RouteAssistantRouteStatus {
  initial,
  loading,
  loaded,
  error,
}

class RouteAssistantState {
  final RouteAssistantSearchStatus searchStatus;
  final RouteAssistantRouteStatus routeStatus;
  final bool isSearchOpen;
  final RouteMode mode;
  final List<GeocodingPlace> searchResults;
  final String? searchError;
  final GeocodingPlace? destination;
  final RouteAssistantRoute? route;
  final DateTime? routeUpdatedAt;
  final String? routeError;

  /// Modalita' Live: la modalita' e' guidata dal classificatore, non dai chip.
  final bool isLive;

  /// Ultima modalita' rilevata dal classificatore (evidenziata in giallo).
  final RouteMode? detectedMode;
  final bool hasDetectedModeResult;

  const RouteAssistantState({
    required this.searchStatus,
    required this.routeStatus,
    this.isSearchOpen = false,
    this.mode = RouteMode.walking,
    this.searchResults = const [],
    this.searchError,
    this.destination,
    this.route,
    this.routeUpdatedAt,
    this.routeError,
    this.isLive = false,
    this.detectedMode,
    this.hasDetectedModeResult = false,
  });

  const RouteAssistantState.initial()
      : searchStatus = RouteAssistantSearchStatus.initial,
        routeStatus = RouteAssistantRouteStatus.initial,
        isSearchOpen = false,
        mode = RouteMode.walking,
        searchResults = const [],
        searchError = null,
        destination = null,
        route = null,
        routeUpdatedAt = null,
        routeError = null,
        isLive = false,
        detectedMode = null,
        hasDetectedModeResult = false;

  bool get isSearching => searchStatus == RouteAssistantSearchStatus.loading;

  bool get isRouting => routeStatus == RouteAssistantRouteStatus.loading;

  /// Un solo messaggio per la UI: se il percorso e' fallito e' quello a contare,
  /// altrimenti resta l'errore della ricerca.
  String? get errorMessage => routeError ?? searchError;

  /// Pallini e selettori sono visibili solo con un percorso calcolato.
  bool get isActive => routePoints.isNotEmpty;

  List<ll.LatLng> get routePoints => route?.points ?? const [];

  RouteAssistantState copyWith({
    RouteAssistantSearchStatus? searchStatus,
    RouteAssistantRouteStatus? routeStatus,
    bool? isSearchOpen,
    RouteMode? mode,
    List<GeocodingPlace>? searchResults,
    String? searchError,
    GeocodingPlace? destination,
    RouteAssistantRoute? route,
    DateTime? routeUpdatedAt,
    String? routeError,
    bool? isLive,
    RouteMode? detectedMode,
    bool? hasDetectedModeResult,
    bool clearDestination = false,
    bool clearRoute = false,
    bool clearSearchError = false,
    bool clearRouteError = false,
    bool clearDetected = false,
  }) {
    return RouteAssistantState(
      searchStatus: searchStatus ?? this.searchStatus,
      routeStatus: routeStatus ?? this.routeStatus,
      isSearchOpen: isSearchOpen ?? this.isSearchOpen,
      mode: mode ?? this.mode,
      searchResults: searchResults ?? this.searchResults,
      searchError: clearSearchError ? null : (searchError ?? this.searchError),
      destination: clearDestination ? null : (destination ?? this.destination),
      route: clearRoute ? null : (route ?? this.route),
      routeUpdatedAt:
          clearRoute ? null : (routeUpdatedAt ?? this.routeUpdatedAt),
      routeError: clearRouteError ? null : (routeError ?? this.routeError),
      isLive: isLive ?? this.isLive,
      detectedMode: clearDetected ? null : (detectedMode ?? this.detectedMode),
      hasDetectedModeResult: hasDetectedModeResult ??
          (clearDetected ? false : this.hasDetectedModeResult),
    );
  }
}

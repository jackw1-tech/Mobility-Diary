import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:latlong2/latlong.dart' as ll;

enum RouteAssistantSearchStatus { initial, loading, loaded, error }

enum RouteAssistantRouteStatus { initial, loading, loaded, error }

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

  final bool isLive;

  final RouteMode? detectedMode;
  final bool hasDetectedModeResult;

  // Incrementato ad ogni classificazione effettivamente arrivata dal
  // backend (anche quando il risultato e' identico al precedente), cosi'
  // l'UI puo' distinguere "e' arrivata una nuova risposta" da "il valore
  // e' cambiato" - il riseed della cache passiva non lo tocca.
  final int classificationTick;

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
    this.classificationTick = 0,
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
      hasDetectedModeResult = false,
      classificationTick = 0;

  bool get isSearching => searchStatus == RouteAssistantSearchStatus.loading;

  bool get isRouting => routeStatus == RouteAssistantRouteStatus.loading;

  String? get errorMessage => routeError ?? searchError;

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
    int? classificationTick,
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
      routeUpdatedAt: clearRoute
          ? null
          : (routeUpdatedAt ?? this.routeUpdatedAt),
      routeError: clearRouteError ? null : (routeError ?? this.routeError),
      isLive: isLive ?? this.isLive,
      detectedMode: clearDetected ? null : (detectedMode ?? this.detectedMode),
      hasDetectedModeResult:
          hasDetectedModeResult ??
          (clearDetected ? false : this.hasDetectedModeResult),
      classificationTick: classificationTick ?? this.classificationTick,
    );
  }
}

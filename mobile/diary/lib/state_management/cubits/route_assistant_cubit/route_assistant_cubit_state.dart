import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:latlong2/latlong.dart' as ll;

class RouteAssistantState {
  final bool isSearchOpen;
  final RouteMode mode;
  final List<GeocodingPlace> searchResults;
  final bool isSearching;
  final GeocodingPlace? destination;
  final RouteAssistantRoute? route;
  final DateTime? routeUpdatedAt;
  final bool isRouting;
  final String? errorMessage;

  /// Modalita' Live: la modalita' e' guidata dal classificatore, non dai chip.
  final bool isLive;

  /// Ultima modalita' rilevata dal classificatore (evidenziata in giallo).
  final RouteMode? detectedMode;
  final bool hasDetectedModeResult;

  const RouteAssistantState({
    this.isSearchOpen = false,
    this.mode = RouteMode.walking,
    this.searchResults = const [],
    this.isSearching = false,
    this.destination,
    this.route,
    this.routeUpdatedAt,
    this.isRouting = false,
    this.errorMessage,
    this.isLive = false,
    this.detectedMode,
    this.hasDetectedModeResult = false,
  });

  /// Pallini e selettori sono visibili solo con un percorso calcolato.
  bool get isActive => routePoints.isNotEmpty;

  List<ll.LatLng> get routePoints => route?.points ?? const [];

  RouteAssistantState copyWith({
    bool? isSearchOpen,
    RouteMode? mode,
    List<GeocodingPlace>? searchResults,
    bool? isSearching,
    GeocodingPlace? destination,
    RouteAssistantRoute? route,
    DateTime? routeUpdatedAt,
    bool? isRouting,
    String? errorMessage,
    bool? isLive,
    RouteMode? detectedMode,
    bool? hasDetectedModeResult,
    bool clearDestination = false,
    bool clearRoute = false,
    bool clearError = false,
    bool clearDetected = false,
  }) {
    return RouteAssistantState(
      isSearchOpen: isSearchOpen ?? this.isSearchOpen,
      mode: mode ?? this.mode,
      searchResults: searchResults ?? this.searchResults,
      isSearching: isSearching ?? this.isSearching,
      destination: clearDestination ? null : (destination ?? this.destination),
      route: clearRoute ? null : (route ?? this.route),
      routeUpdatedAt:
          clearRoute ? null : (routeUpdatedAt ?? this.routeUpdatedAt),
      isRouting: isRouting ?? this.isRouting,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      isLive: isLive ?? this.isLive,
      detectedMode: clearDetected ? null : (detectedMode ?? this.detectedMode),
      hasDetectedModeResult: hasDetectedModeResult ??
          (clearDetected ? false : this.hasDetectedModeResult),
    );
  }
}

import 'package:latlong2/latlong.dart' as ll;
import 'package:mapbox_maps_flutter/mapbox_maps_flutter.dart';

/// Movimenti di camera e stato del puck nativo per la mappa live.
/// Non decide *se* seguire l'utente (quella e' UI state, vive in
/// `_LiveMapState._followUser`): esegue solo l'operazione richiesta.
class LiveMapCameraController {
  LiveMapCameraController(this._map);

  static const double followZoom = 16.5;

  final MapboxMap _map;

  Future<void> syncNativePuck({required bool isReplay}) {
    return _map.location.updateSettings(
      LocationComponentSettings(
        enabled: !isReplay,
        pulsingEnabled: true,
        showAccuracyRing: true,
        puckBearingEnabled: true,
        puckBearing: PuckBearing.HEADING,
      ),
    );
  }

  Future<void> flyTo(ll.LatLng target) {
    return _map.flyTo(
      CameraOptions(
        center: Point(coordinates: Position(target.longitude, target.latitude)),
        zoom: followZoom,
      ),
      MapAnimationOptions(duration: 900),
    );
  }
}

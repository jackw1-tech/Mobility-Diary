import 'package:latlong2/latlong.dart' as ll;

abstract class LocationRepository {
  Future<ll.LatLng?> currentLocation();
}

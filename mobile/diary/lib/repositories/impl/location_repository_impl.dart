import 'package:diary/repositories/location_repository.dart';
import 'package:geolocator/geolocator.dart' as geo;
import 'package:latlong2/latlong.dart' as ll;

class GeolocatorLocationRepository implements LocationRepository {
  const GeolocatorLocationRepository();

  @override
  Future<ll.LatLng?> currentLocation() async {
    if (!await geo.Geolocator.isLocationServiceEnabled()) return null;
    var permission = await geo.Geolocator.checkPermission();
    if (permission == geo.LocationPermission.denied) {
      permission = await geo.Geolocator.requestPermission();
    }
    if (permission == geo.LocationPermission.denied ||
        permission == geo.LocationPermission.deniedForever) {
      return null;
    }
    final position = await geo.Geolocator.getLastKnownPosition() ??
        await geo.Geolocator.getCurrentPosition();
    return ll.LatLng(position.latitude, position.longitude);
  }
}

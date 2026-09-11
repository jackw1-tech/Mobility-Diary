class AcquisitionRoutePoint {
  final double latitude;
  final double longitude;

  const AcquisitionRoutePoint(this.latitude, this.longitude);

  @override
  bool operator ==(Object other) =>
      other is AcquisitionRoutePoint &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);
}

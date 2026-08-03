/// Un punto del percorso ripristinato di una sessione di tracking, esposto dal
/// repository alla UI senza vincolare il dominio a una libreria geografica.
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

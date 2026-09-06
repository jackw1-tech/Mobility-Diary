import 'dart:math';

class GpsSpeedFix {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double accuracyMeters;
  final double platformSpeedMetersPerSecond;

  const GpsSpeedFix({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    required this.platformSpeedMetersPerSecond,
  });
}

/// Usa la velocita' della piattaforma quando e' valida e la ricava dalle
/// coordinate quando iOS/Android la riportano come non disponibile.
class GpsSpeedEstimator {
  static const int _maxFixes = 5;
  static const int _maxSpeedSamples = 3;
  static const double _minimumDistanceMeters = 2;
  static const double _accuracyDeadZoneFactor = 0.35;
  static const double _maximumDeadZoneMeters = 12;
  static const double _maximumReasonableSpeedMetersPerSecond = 80;
  static const Duration _maxLookback = Duration(minutes: 2);

  final List<GpsSpeedFix> _fixes = [];
  final List<double> _speedSamples = [];

  double? add(GpsSpeedFix fix) {
    if (_fixes.isNotEmpty && !fix.timestamp.isAfter(_fixes.last.timestamp)) {
      return _smoothedSpeed();
    }

    final candidate = _usablePlatformSpeed(fix) ?? _coordinateSpeed(fix);
    _appendFix(fix);
    if (candidate != null) _appendSpeed(candidate);
    return _smoothedSpeed();
  }

  void reset() {
    _fixes.clear();
    _speedSamples.clear();
  }

  double? _usablePlatformSpeed(GpsSpeedFix fix) {
    final speed = fix.platformSpeedMetersPerSecond;
    return speed.isFinite &&
            speed >= 0 &&
            speed <= _maximumReasonableSpeedMetersPerSecond
        ? speed
        : null;
  }

  double? _coordinateSpeed(GpsSpeedFix current) {
    for (final previous in _fixes.reversed) {
      final elapsed = current.timestamp.difference(previous.timestamp);
      if (elapsed <= Duration.zero) continue;
      if (elapsed > _maxLookback) break;

      final distance = _distanceMeters(previous, current);
      final uncertainty = max(previous.accuracyMeters, current.accuracyMeters);
      final deadZone = min(
        _maximumDeadZoneMeters,
        max(_minimumDistanceMeters, uncertainty * _accuracyDeadZoneFactor),
      );
      if (distance <= deadZone) continue;

      final speed = distance / (elapsed.inMilliseconds / 1000);
      if (speed <= _maximumReasonableSpeedMetersPerSecond) return speed;
    }
    return null;
  }

  void _appendFix(GpsSpeedFix fix) {
    _fixes.add(fix);
    if (_fixes.length > _maxFixes) _fixes.removeAt(0);
  }

  void _appendSpeed(double speed) {
    _speedSamples.add(speed);
    if (_speedSamples.length > _maxSpeedSamples) _speedSamples.removeAt(0);
  }

  double? _smoothedSpeed() {
    if (_speedSamples.isEmpty) return null;
    if (_speedSamples.length < _maxSpeedSamples) return _speedSamples.last;
    final sorted = List<double>.from(_speedSamples)..sort();
    return sorted[sorted.length ~/ 2];
  }

  double _distanceMeters(GpsSpeedFix start, GpsSpeedFix end) {
    const earthRadiusMeters = 6371000.0;
    final startLatitude = _radians(start.latitude);
    final endLatitude = _radians(end.latitude);
    final deltaLatitude = _radians(end.latitude - start.latitude);
    final deltaLongitude = _radians(end.longitude - start.longitude);
    final haversine = sin(deltaLatitude / 2) * sin(deltaLatitude / 2) +
        cos(startLatitude) *
            cos(endLatitude) *
            sin(deltaLongitude / 2) *
            sin(deltaLongitude / 2);
    return earthRadiusMeters * 2 * atan2(sqrt(haversine), sqrt(1 - haversine));
  }

  double _radians(double degrees) => degrees * pi / 180;
}

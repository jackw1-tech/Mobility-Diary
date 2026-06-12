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

class GpsSpeedEstimator {
  static const int _maxFixes = 5;
  static const int _maxSpeedSamples = 3;
  static const double _minimumSpeedDistanceMeters = 2;
  static const double _accuracyDeadZoneFactor = 0.35;
  static const double _maximumDeadZoneMeters = 12;
  static const double _maximumReasonableSpeedMetersPerSecond = 80;
  static const Duration _maxSpeedLookback = Duration(minutes: 2);

  final List<GpsSpeedFix> _fixes = [];
  final List<double> _speedSamples = [];

  double add(GpsSpeedFix fix) {
    if (_fixes.isNotEmpty && !fix.timestamp.isAfter(_fixes.last.timestamp)) {
      return _smoothedSpeed();
    }

    final candidateSpeed = _candidateSpeed(fix);
    _appendFix(fix);
    _appendSpeed(candidateSpeed);
    return _smoothedSpeed();
  }

  void reset() {
    _fixes.clear();
    _speedSamples.clear();
  }

  double _candidateSpeed(GpsSpeedFix fix) {
    if (_isUsableSpeed(fix.platformSpeedMetersPerSecond)) {
      return fix.platformSpeedMetersPerSecond;
    }

    return _fallbackDistanceSpeed(fix) ?? 0;
  }

  bool _isUsableSpeed(double speedMetersPerSecond) {
    return speedMetersPerSecond > 0 &&
        speedMetersPerSecond <= _maximumReasonableSpeedMetersPerSecond;
  }

  double? _fallbackDistanceSpeed(GpsSpeedFix currentFix) {
    for (final previousFix in _fixes) {
      final elapsedSeconds = currentFix.timestamp
              .difference(previousFix.timestamp)
              .inMilliseconds /
          1000;
      if (elapsedSeconds <= 0) {
        continue;
      }
      if (currentFix.timestamp.difference(previousFix.timestamp) >
          _maxSpeedLookback) {
        continue;
      }

      final distanceMeters = _distanceMeters(
        previousFix.latitude,
        previousFix.longitude,
        currentFix.latitude,
        currentFix.longitude,
      );
      final uncertaintyMeters = max(
        previousFix.accuracyMeters,
        currentFix.accuracyMeters,
      );
      final deadZoneMeters = min(
        _maximumDeadZoneMeters,
        max(
          _minimumSpeedDistanceMeters,
          uncertaintyMeters * _accuracyDeadZoneFactor,
        ),
      );
      if (distanceMeters <= deadZoneMeters) {
        continue;
      }

      final speedMetersPerSecond = distanceMeters / elapsedSeconds;
      if (_isUsableSpeed(speedMetersPerSecond)) {
        return speedMetersPerSecond;
      }
    }

    return null;
  }

  void _appendFix(GpsSpeedFix fix) {
    _fixes.add(fix);
    if (_fixes.length > _maxFixes) {
      _fixes.removeAt(0);
    }
  }

  void _appendSpeed(double speedMetersPerSecond) {
    _speedSamples.add(speedMetersPerSecond);
    if (_speedSamples.length > _maxSpeedSamples) {
      _speedSamples.removeAt(0);
    }
  }

  double _smoothedSpeed() {
    if (_speedSamples.isEmpty) {
      return 0;
    }
    if (_speedSamples.length < _maxSpeedSamples) {
      return _speedSamples.last;
    }

    final sorted = List<double>.from(_speedSamples)..sort();
    return sorted[sorted.length ~/ 2];
  }

  double _distanceMeters(
    double startLatitude,
    double startLongitude,
    double endLatitude,
    double endLongitude,
  ) {
    const earthRadiusMeters = 6371000.0;
    final startLatitudeRadians = _degreesToRadians(startLatitude);
    final endLatitudeRadians = _degreesToRadians(endLatitude);
    final deltaLatitudeRadians = _degreesToRadians(endLatitude - startLatitude);
    final deltaLongitudeRadians =
        _degreesToRadians(endLongitude - startLongitude);

    final haversine =
        sin(deltaLatitudeRadians / 2) * sin(deltaLatitudeRadians / 2) +
            cos(startLatitudeRadians) *
                cos(endLatitudeRadians) *
                sin(deltaLongitudeRadians / 2) *
                sin(deltaLongitudeRadians / 2);
    final centralAngle = 2 * atan2(sqrt(haversine), sqrt(1 - haversine));

    return earthRadiusMeters * centralAngle;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
  }
}

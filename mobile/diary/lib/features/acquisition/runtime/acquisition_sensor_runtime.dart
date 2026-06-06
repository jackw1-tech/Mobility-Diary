import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

typedef AcquisitionRuntimeEventSink = Future<void> Function(
    TrackingEvent event);

class AcquisitionSensorRuntime {
  static const double _minimumSpeedDistanceMeters = 2;
  static const double _accuracyDeadZoneFactor = 0.35;
  static const double _maximumDeadZoneMeters = 12;

  final List<AccelerationSample> _accelerationWindow = [];

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;
  AcquisitionRuntimeEventSink? _eventSink;
  SamplingProfile? _currentProfile;
  bool _isStarted = false;

  Future<void> start({
    required SamplingProfile profile,
    required AcquisitionRuntimeEventSink onEvent,
  }) async {
    _eventSink = onEvent;
    _isStarted = true;
    await configure(profile);
  }

  Future<void> configure(SamplingProfile profile) async {
    if (!_isStarted) {
      return;
    }

    final previousProfile = _currentProfile;
    _currentProfile = profile;

    if (previousProfile?.accelerometerHz != profile.accelerometerHz) {
      await _restartAccelerometer(profile.accelerometerHz);
    }

    if (previousProfile?.gyroscopeHz != profile.gyroscopeHz) {
      await _restartGyroscope(profile.gyroscopeHz);
    }

    final gpsChanged = previousProfile?.gpsEnabled != profile.gpsEnabled ||
        previousProfile?.gpsDistanceFilterMeters !=
            profile.gpsDistanceFilterMeters;

    if (gpsChanged) {
      await _restartGps(profile);
    }
  }

  Future<void> stop() async {
    _isStarted = false;
    _currentProfile = null;
    _eventSink = null;
    _accelerationWindow.clear();
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    await _positionSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _positionSubscription = null;
    _lastPosition = null;
  }

  Future<void> dispose() => stop();

  Future<void> _restartAccelerometer(int frequencyHz) async {
    await _accelerometerSubscription?.cancel();
    _accelerometerSubscription = null;
    _accelerationWindow.clear();

    if (frequencyHz <= 0) {
      return;
    }

    _accelerometerSubscription = accelerometerEventStream(
      samplingPeriod: _samplingPeriodFor(frequencyHz),
    ).listen(_onAccelerometerEvent);
  }

  Future<void> _restartGyroscope(int frequencyHz) async {
    await _gyroscopeSubscription?.cancel();
    _gyroscopeSubscription = null;

    if (frequencyHz <= 0) {
      return;
    }

    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: _samplingPeriodFor(frequencyHz),
    ).listen((_) {});
  }

  Future<void> _restartGps(SamplingProfile profile) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;
    _lastPosition = null;

    if (!profile.gpsEnabled) {
      return;
    }

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) {
      return;
    }

    final distanceFilter =
        (profile.gpsDistanceFilterMeters ?? 0).round().clamp(0, 1000000);

    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: _locationSettingsFor(profile, distanceFilter),
    ).listen(_onPosition);
  }

  Future<bool> _ensureLocationPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }

  Future<void> _onAccelerometerEvent(AccelerometerEvent event) async {
    final profile = _currentProfile;
    final eventSink = _eventSink;
    if (!_isStarted || profile == null || eventSink == null) {
      return;
    }

    _accelerationWindow.add(
      AccelerationSample(
        x: event.x,
        y: event.y,
        z: event.z,
      ),
    );

    final windowSize = _windowSizeFor(profile.accelerometerHz);
    if (_accelerationWindow.length < windowSize) {
      return;
    }

    final window = List<AccelerationSample>.from(_accelerationWindow);
    _accelerationWindow.clear();
    final sigma = MotionMetrics.accelerationMagnitudeSigma(window);

    await eventSink(
      MotionWindowEvaluated(
        timestamp: DateTime.now(),
        sigma: sigma,
        sampleCount: window.length,
      ),
    );
  }

  Future<void> _onPosition(Position position) async {
    final eventSink = _eventSink;
    if (!_isStarted || eventSink == null) {
      return;
    }

    final speedMetersPerSecond = _effectiveSpeedMetersPerSecond(position);
    _lastPosition = position;

    await eventSink(
      GpsFixReceived(
        timestamp: position.timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
        speedMetersPerSecond: speedMetersPerSecond,
        accuracyMeters: position.accuracy,
      ),
    );
  }

  double _effectiveSpeedMetersPerSecond(Position position) {
    if (position.speed > 0) {
      return position.speed;
    }

    final previousPosition = _lastPosition;
    if (previousPosition == null) {
      return 0;
    }

    final elapsedSeconds = position.timestamp
            .difference(previousPosition.timestamp)
            .inMilliseconds /
        1000;
    if (elapsedSeconds <= 0) {
      return 0;
    }

    final distanceMeters = _distanceMeters(
      previousPosition.latitude,
      previousPosition.longitude,
      position.latitude,
      position.longitude,
    );
    final uncertaintyMeters = max(
      previousPosition.accuracy,
      position.accuracy,
    );
    final deadZoneMeters = min(
      _maximumDeadZoneMeters,
      max(
        _minimumSpeedDistanceMeters,
        uncertaintyMeters * _accuracyDeadZoneFactor,
      ),
    );

    if (distanceMeters <= deadZoneMeters) {
      return 0;
    }

    return distanceMeters / elapsedSeconds;
  }

  LocationSettings _locationSettingsFor(
    SamplingProfile profile,
    int distanceFilter,
  ) {
    final interval = profile.gpsInterval;
    if (Platform.isAndroid && interval != null) {
      return AndroidSettings(
        accuracy: LocationAccuracy.high,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
      );
    }

    return LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: distanceFilter,
    );
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

  Duration _samplingPeriodFor(int frequencyHz) {
    return Duration(milliseconds: (1000 / frequencyHz).round());
  }

  int _windowSizeFor(int frequencyHz) {
    if (frequencyHz >= 50) {
      return 250;
    }

    return 20;
  }
}

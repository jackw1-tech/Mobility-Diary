import 'dart:async';
import 'dart:io';

import 'package:diary/features/acquisition/domain/acquisition_domain.dart';
import 'package:diary/features/acquisition/runtime/gps_speed_estimator.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

typedef AcquisitionRuntimeEventSink = Future<void> Function(
    TrackingEvent event);
typedef HarWindowSink = Future<void> Function(HarSensorWindow window);

class AcquisitionSensorRuntime {
  static const Duration _harWindowDuration = HarSensorWindow.targetDuration;
  static const int _maxCompletedHarWindows = 12;

  final List<AccelerationSample> _accelerationWindow = [];
  final List<HarSensorSample> _harWindowSamples = [];
  final List<HarSensorWindow> _completedHarWindows = [];
  final GpsSpeedEstimator _gpsSpeedEstimator = GpsSpeedEstimator();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _positionSubscription;
  GyroscopeEvent? _latestGyroscopeEvent;
  DateTime? _harWindowStartedAt;
  AcquisitionRuntimeEventSink? _eventSink;
  HarWindowSink? _harWindowSink;
  SamplingProfile? _currentProfile;
  bool _isStarted = false;

  List<HarSensorWindow> get completedHarWindows {
    return List<HarSensorWindow>.unmodifiable(_completedHarWindows);
  }

  Future<void> start({
    required SamplingProfile profile,
    required AcquisitionRuntimeEventSink onEvent,
    HarWindowSink? onHarWindow,
  }) async {
    _eventSink = onEvent;
    _harWindowSink = onHarWindow;
    _isStarted = true;
    _gpsSpeedEstimator.reset();
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

    if (previousProfile?.harWindowEnabled != profile.harWindowEnabled) {
      _resetHarWindow();
      if (!profile.harWindowEnabled) {
        _completedHarWindows.clear();
      }
    }

    final gpsChanged = previousProfile?.gpsEnabled != profile.gpsEnabled ||
        previousProfile?.gpsInterval != profile.gpsInterval ||
        previousProfile?.gpsDistanceFilterMeters !=
            profile.gpsDistanceFilterMeters ||
        previousProfile?.gpsAccuracy != profile.gpsAccuracy;

    if (gpsChanged) {
      await _restartGps(profile);
    }
  }

  Future<void> stop() async {
    _isStarted = false;
    _currentProfile = null;
    _eventSink = null;
    _harWindowSink = null;
    _accelerationWindow.clear();
    _resetHarWindow();
    _completedHarWindows.clear();
    await _accelerometerSubscription?.cancel();
    await _gyroscopeSubscription?.cancel();
    await _positionSubscription?.cancel();
    _accelerometerSubscription = null;
    _gyroscopeSubscription = null;
    _positionSubscription = null;
    _gpsSpeedEstimator.reset();
    _latestGyroscopeEvent = null;
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
    _latestGyroscopeEvent = null;

    if (frequencyHz <= 0) {
      return;
    }

    _gyroscopeSubscription = gyroscopeEventStream(
      samplingPeriod: _samplingPeriodFor(frequencyHz),
    ).listen(_onGyroscopeEvent);
  }

  Future<void> _restartGps(SamplingProfile profile) async {
    await _positionSubscription?.cancel();
    _positionSubscription = null;

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

    if (permission == LocationPermission.whileInUse) {
      permission = await Geolocator.requestPermission();
    }

    return canStartAcquisitionLocationStream(permission);
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
    final timestamp = DateTime.now().toUtc();
    await _appendHarSensorSample(event, timestamp);

    final windowSize = _windowSizeFor(profile.accelerometerHz);
    if (_accelerationWindow.length < windowSize) {
      return;
    }

    final window = List<AccelerationSample>.from(_accelerationWindow);
    _accelerationWindow.clear();
    final sigma = MotionMetrics.accelerationMagnitudeSigma(window);

    await eventSink(
      MotionWindowEvaluated(
        timestamp: timestamp,
        sigma: sigma,
        sampleCount: window.length,
      ),
    );
  }

  void _onGyroscopeEvent(GyroscopeEvent event) {
    _latestGyroscopeEvent = event;
  }

  Future<void> _appendHarSensorSample(
    AccelerometerEvent event,
    DateTime timestamp,
  ) async {
    final profile = _currentProfile;
    if (profile == null || !profile.harWindowEnabled) {
      return;
    }

    _harWindowStartedAt ??= timestamp;
    final gyroscopeEvent = _latestGyroscopeEvent;

    _harWindowSamples.add(
      HarSensorSample(
        timestamp: timestamp,
        accX: event.x,
        accY: event.y,
        accZ: event.z,
        gyrX: gyroscopeEvent?.x ?? 0,
        gyrY: gyroscopeEvent?.y ?? 0,
        gyrZ: gyroscopeEvent?.z ?? 0,
      ),
    );

    final startedAt = _harWindowStartedAt!;
    if (timestamp.difference(startedAt) < _harWindowDuration) {
      return;
    }

    final window = HarSensorWindow(
      startedAt: startedAt,
      endedAt: timestamp,
      accelerometerHz: profile.accelerometerHz,
      gyroscopeHz: profile.gyroscopeHz,
      magnetometerHz: profile.magnetometerHz,
      samples: List<HarSensorSample>.from(_harWindowSamples),
    );
    _completedHarWindows.insert(0, window);
    if (_completedHarWindows.length > _maxCompletedHarWindows) {
      _completedHarWindows.removeLast();
    }
    _resetHarWindow();
    await _harWindowSink?.call(window);
  }

  void _resetHarWindow() {
    _harWindowSamples.clear();
    _harWindowStartedAt = null;
  }

  Future<void> _onPosition(Position position) async {
    final eventSink = _eventSink;
    if (!_isStarted || eventSink == null) {
      return;
    }

    final timestamp = position.timestamp.toUtc();
    final speedMetersPerSecond = _gpsSpeedEstimator.add(
      GpsSpeedFix(
        timestamp: timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        platformSpeedMetersPerSecond: position.speed,
      ),
    );

    await eventSink(
      GpsFixReceived(
        timestamp: timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
        speedMetersPerSecond: speedMetersPerSecond,
        accuracyMeters: position.accuracy,
      ),
    );
  }

  LocationSettings _locationSettingsFor(
    SamplingProfile profile,
    int distanceFilter,
  ) {
    final interval = profile.gpsInterval;
    final accuracy = _locationAccuracyFor(profile.gpsAccuracy);
    if (Platform.isAndroid && interval != null) {
      return AndroidSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Mobility Diary attivo',
          notificationText:
              'Il tracking continua a usare la posizione in background.',
          notificationChannelName: 'Mobility tracking',
          enableWakeLock: true,
          setOngoing: true,
        ),
      );
    }

    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
        // During an active trip, pausing in the stationary profile can let iOS
        // suspend the app long enough that the user comes back to a cold start.
        pauseLocationUpdatesAutomatically: false,
        activityType: profile.gpsAccuracy == GpsAccuracyProfile.highAccuracy
            ? ActivityType.fitness
            : ActivityType.other,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }

    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  LocationAccuracy _locationAccuracyFor(GpsAccuracyProfile accuracyProfile) {
    switch (accuracyProfile) {
      case GpsAccuracyProfile.lowPower:
        return LocationAccuracy.low;
      case GpsAccuracyProfile.highAccuracy:
        return LocationAccuracy.high;
    }
  }

  Duration _samplingPeriodFor(int frequencyHz) {
    return Duration(milliseconds: (1000 / frequencyHz).round());
  }

  int _windowSizeFor(int frequencyHz) {
    if (frequencyHz >= 50) {
      return frequencyHz * _harWindowDuration.inSeconds;
    }

    return 20;
  }
}

bool canStartAcquisitionLocationStream(LocationPermission permission) {
  return permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;
}

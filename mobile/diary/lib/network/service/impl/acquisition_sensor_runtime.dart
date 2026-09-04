import 'dart:async';
import 'dart:io';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/network/service/impl/gps_speed_estimator.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';

typedef AcquisitionEventCallback = Future<void> Function(TrackingEvent event);
typedef HarWindowCallback = Future<void> Function(HarSensorWindow window);

class AcquisitionSensorRuntime {
  static const Duration _harWindowDuration = HarSensorWindow.targetDuration;

  final List<AccelerationSample> _accelerationWindow = [];
  final List<HarSensorSample> _harWindowSamples = [];
  final GpsSpeedEstimator _gpsSpeedEstimator = GpsSpeedEstimator();

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _positionSubscription;
  GyroscopeEvent? _latestGyroscopeEvent;
  DateTime? _harWindowStartedAt;
  AcquisitionEventCallback? _onEvent;
  HarWindowCallback? _onHarWindow;
  SamplingProfile? _currentProfile;
  bool _isStarted = false;
  bool _gpsRestartPending = false;

  /// Blocca l acquisizione nel caso non ci sia il permesso Always
  Future<bool> hasAcquisitionLocationPermission() =>
      _ensureLocationPermission();

  Future<void> start({
    required SamplingProfile profile,
    required AcquisitionEventCallback onEvent,
    HarWindowCallback? onHarWindow,
  }) async {
    _onEvent = onEvent;
    _onHarWindow = onHarWindow;
    _isStarted = true;
    _gpsSpeedEstimator.reset();
    await configure(profile);
  }

  // funzione da chiamare quando il profilo di sempling cambia
  Future<void> configure(
    SamplingProfile profile, {
    bool allowGpsRestart = true,
  }) async {
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
    }

    final gpsChanged = previousProfile?.gpsEnabled != profile.gpsEnabled ||
        previousProfile?.gpsInterval != profile.gpsInterval ||
        previousProfile?.gpsDistanceFilterMeters !=
            profile.gpsDistanceFilterMeters;

    if (gpsChanged || _gpsRestartPending) {
      if (allowGpsRestart) {
        _gpsRestartPending = false;
        await _restartGps(profile);
      } else {
        _gpsRestartPending = true;
      }
    }
  }

  /// Applica in foreground il riavvio GPS.
  Future<void> applyPendingGpsRestart() async {
    final profile = _currentProfile;
    if (!_isStarted || !_gpsRestartPending || profile == null) {
      return;
    }
    _gpsRestartPending = false;
    await _restartGps(profile);
  }

  Future<void> stop() async {
    _isStarted = false;
    _currentProfile = null;
    _gpsRestartPending = false;
    _onEvent = null;
    _onHarWindow = null;
    _accelerationWindow.clear();
    _resetHarWindow();
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

  // Riavvia lo stream del gps
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
    final onEvent = _onEvent;
    if (!_isStarted || profile == null || onEvent == null) {
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

    // LiveAcquisitionStrategy -> ingestEvent
    await onEvent(
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

  // Accomula campioni e ogni 5 secondi inserisce il record HarSensorWindow
  Future<void> _appendHarSensorSample(
    AccelerometerEvent event,
    DateTime timestamp,
  ) async {
    final profile = _currentProfile;
    if (profile == null || !profile.harWindowEnabled) {
      return;
    }

    _harWindowStartedAt ??=
        timestamp; // assegna solo se_harWindowStartedAt è null -> il primo campione dopo _resetHarWindow
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
    } //se siamo all'interno dei 5 secondi, non faccio nulla
    // Se sono alla fine, inserisco la HarSensorWindow nel db

    final window = HarSensorWindow(
      startedAt: startedAt,
      endedAt: timestamp,
      accelerometerHz: profile.accelerometerHz,
      gyroscopeHz: profile.gyroscopeHz,
      magnetometerHz: profile.magnetometerHz,
      samples: List<HarSensorSample>.from(_harWindowSamples),
    );
    _resetHarWindow();
    await _onHarWindow?.call(window);
  }

  void _resetHarWindow() {
    _harWindowSamples.clear();
    _harWindowStartedAt = null;
  }

  //Prende un il gps, lo ripulisce e lo converte in un GpsFixReceived
  Future<void> _onPosition(Position position) async {
    final onEvent = _onEvent;
    if (!_isStarted || onEvent == null) {
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

    await onEvent(
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
    const accuracy = LocationAccuracy.high;
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
        activityType: ActivityType.fitness,
        showBackgroundLocationIndicator: true,
        allowBackgroundLocationUpdates: true,
      );
    }

    return LocationSettings(
      accuracy: accuracy,
      distanceFilter: distanceFilter,
    );
  }

  Duration _samplingPeriodFor(int frequencyHz) {
    return Duration(milliseconds: (1000 / frequencyHz).round());
  }

  // Decide in base alla frequenza / profilo di sampling quanti campioni accumulare in _accelerationWindow per il sigma
  int _windowSizeFor(int frequencyHz) {
    return switch (frequencyHz) {
      10 => 20,
      100 => frequencyHz * _harWindowDuration.inSeconds,
      _ => 20,
    };
  }
}

bool canStartAcquisitionLocationStream(LocationPermission permission) {
  return permission == LocationPermission.always;
}

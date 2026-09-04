import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart' as ph;
import 'package:sensors_plus/sensors_plus.dart';

typedef AcquisitionEventCallback = Future<void> Function(TrackingEvent event);
typedef HarWindowCallback = Future<void> Function(HarSensorWindow window);

// Classe che gestisce e costruire le finestra Har 500 x 6
class AcquisitionSensorRuntime {
  static const Duration _harWindowDuration = HarSensorWindow.targetDuration;

  final List<AccelerationSample> _accelerationWindow = [];
  final List<HarSensorSample> _harWindowSamples = [];

  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  StreamSubscription<GyroscopeEvent>? _gyroscopeSubscription;
  StreamSubscription<Position>? _positionSubscription;
  GyroscopeEvent? _latestGyroscopeEvent;
  DateTime? _harWindowStartedAt;
  AcquisitionEventCallback? _onEvent;
  HarWindowCallback? _onHarWindow;
  SamplingProfile? _currentSamplingProfile;
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

    final previousProfile = _currentSamplingProfile;
    _currentSamplingProfile = profile;

    if (previousProfile?.accelerometerHz != profile.accelerometerHz) {
      await _restartAccelerometer(profile.accelerometerHz);
    }

    if (previousProfile?.gyroscopeHz != profile.gyroscopeHz) {
      await _restartGyroscope(profile.gyroscopeHz);
    }

    // Quando cambio stato FSM; elimino i dati dei sensori dato che cambierà la frequenza di campionamento
    if (previousProfile?.harWindowEnabled != profile.harWindowEnabled) {
      _resetHarWindow();
    }

    // Stationary <> Movement: 5s <> 2s
    final gpsChanged = previousProfile?.gpsInterval != profile.gpsInterval;

    if (gpsChanged || _gpsRestartPending) {
      // Se siamo in background non voglio far riavviare il gps
      if (allowGpsRestart) {
        _gpsRestartPending = false;
        await _restartGps(profile);
      } else {
        // Se siamo in background, non riavvio il gps ma segno che al prossimo foreground lo devo fare
        _gpsRestartPending = true;
      }
    }
  }

  /// Applica in foreground il riavvio GPS.
  Future<void> applyPendingGpsRestart() async {
    final profile = _currentSamplingProfile;
    if (!_isStarted || !_gpsRestartPending || profile == null) {
      return;
    }
    _gpsRestartPending = false;
    await _restartGps(profile);
  }

  Future<void> stop() async {
    _isStarted = false;
    _currentSamplingProfile = null;
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

    final hasPermission = await _ensureLocationPermission();
    if (!hasPermission) {
      return;
    }

    final distanceFilter = (profile.gpsDistanceFilterMeters ?? 0).round();

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
    developer.log(
      'checkPermission -> $permission',
      name: 'mobility.permission',
    );
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      developer.log(
        'requestPermission (denied -> ?) -> $permission',
        name: 'mobility.permission',
      );
    }

    if (permission == LocationPermission.whileInUse) {
      // Geolocator non chiede mai davvero l'upgrade a "Always" quando il
      // permesso e' gia' "When In Use": la sua requestPermission() ritorna lo
      // stato attuale senza mostrare il dialogo nativo (bug noto,
      // github.com/Baseflow/flutter-geolocator/issues/1223). permission_handler
      // arriva davvero a chiamare requestAlwaysAuthorization.
      //
      // Su iOS 15+ due richieste di permesso privacy incatenate subito una
      // dopo l'altra vengono soppresse: il dialogo "When In Use" appena
      // chiuso lascia l'app momentaneamente inactive, e una richiesta fatta
      // in quella finestra non mostra nulla. Il piccolo ritardo da'
      // all'app il tempo di tornare active prima della seconda richiesta.
      await Future<void>.delayed(const Duration(milliseconds: 750));
      try {
        final phStatus = await ph.Permission.locationAlways.status;
        developer.log(
          'permission_handler status prima della richiesta -> $phStatus',
          name: 'mobility.permission',
        );
        final phResult = await ph.Permission.locationAlways.request();
        developer.log(
          'permission_handler locationAlways.request() -> $phResult',
          name: 'mobility.permission',
        );
      } catch (error, stackTrace) {
        developer.log(
          'permission_handler locationAlways.request() ha lanciato',
          name: 'mobility.permission',
          error: error,
          stackTrace: stackTrace,
        );
      }
      permission = await Geolocator.checkPermission();
      developer.log(
        'checkPermission dopo il tentativo di upgrade -> $permission',
        name: 'mobility.permission',
      );
    }

    return canStartAcquisitionLocationStream(permission);
  }

  Future<void> _onAccelerometerEvent(AccelerometerEvent event) async {
    final profile = _currentSamplingProfile;
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
    final profile = _currentSamplingProfile;
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
      samples: List<HarSensorSample>.from(_harWindowSamples),
    );
    _resetHarWindow();
    await _onHarWindow?.call(window);
  }

  void _resetHarWindow() {
    _harWindowSamples.clear();
    _harWindowStartedAt = null;
  }

  //Prende un il gps ricevuto da Geolocator e lo converte in un GpsFixReceived -> fa scattare
  // La funzione ingestEvent di live acquisition strategy repo
  Future<void> _onPosition(Position position) async {
    final onEvent = _onEvent;
    if (!_isStarted || onEvent == null) {
      return;
    }

    final timestamp = position.timestamp.toUtc();
    await onEvent(
      GpsFixReceived.fromPlatform(
        timestamp: timestamp,
        latitude: position.latitude,
        longitude: position.longitude,
        accuracyMeters: position.accuracy,
        platformSpeedMetersPerSecond: position.speed,
      ),
    );
  }

  // Costruisce l'oggetto LocationSettings da passare a Geolocator.getPositionStream
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

    // ios non supporta l'intervallo
    if (Platform.isIOS || Platform.isMacOS) {
      return AppleSettings(
        accuracy: accuracy,
        distanceFilter: distanceFilter,
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
      10 => 20, // ogni 2 secondi
      100 => frequencyHz * _harWindowDuration.inSeconds, // ogni 5 secondi
      _ => 20,
    };
  }
}

bool canStartAcquisitionLocationStream(LocationPermission permission) {
  return permission == LocationPermission.always;
}

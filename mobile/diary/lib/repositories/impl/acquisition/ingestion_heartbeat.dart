import 'dart:async';

import 'package:diary/network/service/trip_ingestion_service.dart';

typedef HeartbeatTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

/// Coordinate della sessione remota da tenere viva.
class HeartbeatTarget {
  final int ingestionId;
  final String clientSessionId;
  final String deviceId;

  const HeartbeatTarget({
    required this.ingestionId,
    required this.clientSessionId,
    required this.deviceId,
  });
}

/// Tiene viva l'ingestion sul backend mentre il viaggio e' in corso.
///
/// Bersaglio e stato di tracking vengono riletti a ogni battito invece di
/// essere catturati all'avvio del timer: la sessione puo' cambiare (resume,
/// stop, recupero da conflitto) mentre il timer e' gia' in piedi.
class IngestionHeartbeat {
  final TripIngestionService? _service;
  final Duration _interval;
  final HeartbeatTimerFactory _timerFactory;
  final HeartbeatTarget? Function() _target;
  final bool Function() _isTracking;

  Timer? _timer;

  IngestionHeartbeat({
    required TripIngestionService? service,
    required Duration interval,
    required HeartbeatTimerFactory timerFactory,
    required HeartbeatTarget? Function() target,
    required bool Function() isTracking,
  })  : _service = service,
        _interval = interval,
        _timerFactory = timerFactory,
        _target = target,
        _isTracking = isTracking;

  void restart() {
    _timer?.cancel();
    if (_service == null || _target() == null) {
      return;
    }
    _timer = _timerFactory(_interval, (_) {
      unawaited(send());
    });
  }

  /// Manda un heart beat al backend
  Future<void> send() async {
    final api = _service;
    final target = _target();
    if (!_isTracking() || api == null || target == null) {
      return;
    }

    try {
      await api.heartbeatIngestion(
        ingestionId: target.ingestionId,
        clientSessionId: target.clientSessionId,
        deviceId: target.deviceId,
      );
    } catch (_) {
      // Heartbeat best-effort: non deve mai fermare i sensori locali.
    }
  }

  void cancel() => _timer?.cancel();
}

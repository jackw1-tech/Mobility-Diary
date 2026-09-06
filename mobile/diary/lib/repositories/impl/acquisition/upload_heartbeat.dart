import 'dart:async';

import 'package:diary/network/service/trip_upload_service.dart';

typedef HeartbeatTimerFactory = Timer Function(
  Duration duration,
  void Function(Timer timer) callback,
);

class HeartbeatTarget {
  final int uploadId;
  final String clientSessionId;
  final String deviceId;

  const HeartbeatTarget({
    required this.uploadId,
    required this.clientSessionId,
    required this.deviceId,
  });
}

class UploadHeartbeat {
  final TripUploadService? _service;
  final Duration _interval;
  final HeartbeatTimerFactory _timerFactory;
  final HeartbeatTarget? Function() _target;
  final bool Function() _isTracking;

  Timer? _timer;

  UploadHeartbeat({
    required TripUploadService? service,
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
      await api.heartbeatUpload(
        uploadId: target.uploadId,
        clientSessionId: target.clientSessionId,
        deviceId: target.deviceId,
      );
    } catch (_) {}
  }

  void cancel() => _timer?.cancel();
}

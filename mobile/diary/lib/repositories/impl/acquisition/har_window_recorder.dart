import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/model/entities/acquisition/sensor_matrix_json.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';

class HarWindowRecorder {
  final AcquisitionDao _dao;
  final Set<String> _persistedKeys = {};

  HarWindowRecorder(this._dao);

  void reset() => _persistedKeys.clear();

  Future<void> persist({
    required String sessionId,
    required HarSensorWindow window,
  }) async {
    final key = _keyFor(window);
    if (_persistedKeys.contains(key)) {
      return;
    }

    final modelInput = window.modelInputMatrix;
    await _dao.insertSensorWindow(
      sessionId: sessionId,
      startTimestamp: window.startedAt,
      endTimestamp: window.endedAt,
      sampleCount: modelInput.length,
      frequencyHz: HarSensorWindow.targetSamplingHz,
      matrixJson: encodeSensorMatrixJson(modelInput),
    );
    _persistedKeys.add(key);
  }

  static String _keyFor(HarSensorWindow window) {
    return '${window.startedAt.microsecondsSinceEpoch}-'
        '${window.endedAt.microsecondsSinceEpoch}';
  }
}

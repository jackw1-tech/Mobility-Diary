import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/model/entities/acquisition/sensor_matrix_json.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';

/// Persiste le finestre sensori HAR di una sessione, scartando i doppioni.
///
/// Oggi le finestre arrivano da una sola strada (il callback `onHarWindow` del
/// runtime, una chiamata per finestra chiusa), quindi la deduplica non
/// dovrebbe mai scattare: resta come rete di sicurezza a costo trascurabile,
/// perche' riscrivere la stessa finestra violerebbe il vincolo di unicita'
/// sull'intervallo temporale. La chiave e' appunto quell'intervallo.
class HarWindowRecorder {
  final AcquisitionDao _dao;
  final Set<String> _persistedKeys = {};

  HarWindowRecorder(this._dao);

  /// Da chiamare a ogni cambio di sessione: le chiavi valgono solo dentro la
  /// sessione corrente.
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

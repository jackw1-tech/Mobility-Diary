import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/model/entities/acquisition/sensor_matrix_blob.dart';
import 'package:diary/network/service/impl/acquisition_local_database.dart';

/// Persiste le finestre sensori HAR di una sessione, scartando i doppioni.
///
/// Le finestre arrivano da due strade che possono sovrapporsi (il callback live
/// del runtime e il recupero delle finestre gia' completate a ogni decisione
/// FSM), quindi serve ricordare cosa e' gia' stato scritto: la chiave e'
/// l'intervallo temporale della finestra, stabile tra le due strade.
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
      matrixBlob: encodeSensorMatrixBlob(modelInput),
    );
    _persistedKeys.add(key);
  }

  static String _keyFor(HarSensorWindow window) {
    return '${window.startedAt.microsecondsSinceEpoch}-'
        '${window.endedAt.microsecondsSinceEpoch}';
  }
}

import 'dart:convert';

const int sensorMatrixChannelCount = 6;

/// 10^6: teniamo 6 decimali. 1e-6 e' ordini di grandezza sotto il rumore di
/// fondo di accelerometro e giroscopio, quindi non perde segnale utile, ma
/// dimezza dimensione e tempo di parsing rispetto alla precisione piena.
const double _roundingFactor = 1000000;

/// Arrotonda e neutralizza i valori non finiti: `jsonEncode` rifiuta
/// NaN/Infinity, e un campione sporco non deve poter bloccare per sempre
/// l'upload di un viaggio.
///
/// Il controllo e' sul risultato, non sull'ingresso: un valore finito ma
/// enorme (>= ~1.8e302) traboccherebbe a Infinity nella moltiplicazione,
/// sfuggendo a una guardia posta solo in ingresso.
double _rounded(double value) {
  final rounded = (value * _roundingFactor).roundToDouble() / _roundingFactor;
  return rounded.isFinite ? rounded : 0;
}

String encodeSensorMatrixJson(List<List<double>> matrix) {
  return jsonEncode([
    for (final row in matrix)
      if (row.length < sensorMatrixChannelCount)
        throw const FormatException('sensor window matrix con riga non valida')
      else
        [
          for (var channel = 0; channel < sensorMatrixChannelCount; channel += 1)
            _rounded(row[channel]),
        ],
  ]);
}

List<List<double>> decodeSensorMatrixJson(String matrixJson) {
  final decoded = jsonDecode(matrixJson);
  if (decoded is! List) {
    throw const FormatException('sensor window matrix non valida');
  }
  return [
    for (final row in decoded)
      if (row is! List || row.length < sensorMatrixChannelCount)
        throw const FormatException('sensor window matrix con riga non valida')
      else
        [
          for (var channel = 0; channel < sensorMatrixChannelCount; channel += 1)
            (row[channel] as num).toDouble(),
        ],
  ];
}

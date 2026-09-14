import 'dart:convert';

const int sensorMatrixChannelCount = 6;

const double _roundingFactor = 1000000;

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
          for (
            var channel = 0;
            channel < sensorMatrixChannelCount;
            channel += 1
          )
            _rounded(row[channel]),
        ],
  ]);
}
//[  [-0.023457,-9.806649,0.112346,0.001235,-0.004321,0.000765],[...],...  ]
// Una sola [] di primo livello (radice)
// Tante [] dentro il secondo livello
// jsonDecode lo interpreta come una lista di elementi,
// ogni elemento contiene i numeri dentro [] di secondo livello -> List di primo livello di decodeSensorMatrixJson
// all'interno ci sono 6 numeir -> List<double> di secondo livello di decodeSensorMatrixJson

// 500 elementi lista di primo livello
// 6 elementi lista di secondo livello
// 5 sec di dati
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
          for (
            var channel = 0;
            channel < sensorMatrixChannelCount;
            channel += 1
          )
            (row[channel] as num).toDouble(),
        ],
  ];
}

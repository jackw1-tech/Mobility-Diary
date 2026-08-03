import 'dart:convert';
import 'dart:typed_data';

const int sensorMatrixChannelCount = 6;

Uint8List encodeSensorMatrixBlob(List<List<double>> matrix) {
  final bytes = ByteData(
    matrix.length * sensorMatrixChannelCount * Float32List.bytesPerElement,
  );
  var offset = 0;
  for (final row in matrix) {
    if (row.length < sensorMatrixChannelCount) {
      throw const FormatException('sensor window matrix con riga non valida');
    }
    for (var channel = 0; channel < sensorMatrixChannelCount; channel += 1) {
      bytes.setFloat32(offset, row[channel], Endian.little);
      offset += Float32List.bytesPerElement;
    }
  }
  return bytes.buffer.asUint8List();
}

Uint8List encodeSensorMatrixJsonToBlob(String matrixJson) {
  final decoded = jsonDecode(matrixJson);
  if (decoded is! List) {
    throw const FormatException('sensor window matrix non valida');
  }
  final rows = <List<double>>[];
  for (final row in decoded) {
    if (row is! List || row.length < sensorMatrixChannelCount) {
      throw const FormatException('sensor window matrix con riga non valida');
    }
    rows.add([
      for (var channel = 0; channel < sensorMatrixChannelCount; channel += 1)
        (row[channel] as num).toDouble(),
    ]);
  }
  return encodeSensorMatrixBlob(rows);
}

List<List<double>> decodeSensorMatrixBlob(
  Uint8List blob, {
  required int sampleCount,
}) {
  final expectedBytes =
      sampleCount * sensorMatrixChannelCount * Float32List.bytesPerElement;
  if (blob.lengthInBytes != expectedBytes) {
    throw const FormatException('sensor window matrix blob non valido');
  }
  final data = ByteData.sublistView(blob);
  var offset = 0;
  return [
    for (var sample = 0; sample < sampleCount; sample += 1)
      [
        for (var channel = 0; channel < sensorMatrixChannelCount; channel += 1)
          () {
            final value = data.getFloat32(offset, Endian.little);
            offset += Float32List.bytesPerElement;
            return value;
          }(),
      ],
  ];
}

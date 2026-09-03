import 'dart:convert';

import 'package:diary/model/entities/acquisition/sensor_matrix_json.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('round trip preserva i valori arrotondati a 6 decimali', () {
    final matrix = [
      [0.1234564, -9.8100001, 0.0, 1.5, -0.000001, 123.456789],
      [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
    ];

    final decoded = decodeSensorMatrixJson(encodeSensorMatrixJson(matrix));

    expect(decoded.length, 2);
    expect(decoded[0], [0.123456, -9.81, 0.0, 1.5, -0.000001, 123.456789]);
    expect(decoded[1], [1.0, 2.0, 3.0, 4.0, 5.0, 6.0]);
  });

  test('produce JSON parsabile con una riga per campione', () {
    final json = encodeSensorMatrixJson([
      [1.5, 2.5, 3.5, 4.5, 5.5, 6.5],
    ]);

    expect(jsonDecode(json), [
      [1.5, 2.5, 3.5, 4.5, 5.5, 6.5],
    ]);
  });

  test('i valori non finiti diventano 0 invece di far fallire la codifica', () {
    final json = encodeSensorMatrixJson([
      [double.nan, double.infinity, double.negativeInfinity, 1.0, 2.0, 3.0],
    ]);

    expect(jsonDecode(json), [
      [0, 0, 0, 1.0, 2.0, 3.0],
    ]);
  });

  test('un valore finito ma enorme non traborda a Infinity nel round', () {
    // value * 1e6 supera il massimo double: senza il controllo sul risultato
    // uscirebbe Infinity e jsonEncode fallirebbe, bloccando l'upload.
    final json = encodeSensorMatrixJson([
      [1e303, -1e305, 1.0, 2.0, 3.0, 4.0],
    ]);

    expect(jsonDecode(json), [
      [0, 0, 1.0, 2.0, 3.0, 4.0],
    ]);
  });

  test('una riga con meno di 6 canali e\' rifiutata', () {
    expect(
      () => encodeSensorMatrixJson([
        [1.0, 2.0, 3.0],
      ]),
      throwsA(isA<FormatException>()),
    );
    expect(
      () => decodeSensorMatrixJson('[[1,2,3]]'),
      throwsA(isA<FormatException>()),
    );
  });
}

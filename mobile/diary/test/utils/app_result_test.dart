import 'dart:async';
import 'dart:io';

import 'package:diary/utils/app_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves successful values', () async {
    final result = await appResultOf(() async => 42);

    expect(result.isSuccess, isTrue);
    expect(result.requireValue, 42);
  });

  test('classifies socket and timeout errors as network failures', () {
    expect(
        toAppFailure(const SocketException('offline')), isA<NetworkFailure>());
    expect(toAppFailure(TimeoutException('slow')), isA<NetworkFailure>());
  });

  test('does not erase an existing application failure', () {
    const failure = ValidationFailure('dato non valido');

    expect(identical(toAppFailure(failure), failure), isTrue);
  });

  test('requireValue rejects failed results', () {
    const result = AppResult<int>.failure(ValidationFailure('invalid'));

    expect(() => result.requireValue, throwsStateError);
  });
}

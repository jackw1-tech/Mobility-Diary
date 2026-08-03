import 'dart:async';
import 'dart:io';

sealed class AppFailure implements Exception {
  final String message;
  final Object? cause;

  const AppFailure(this.message, {this.cause});

  @override
  String toString() => message;
}

class NetworkFailure extends AppFailure {
  const NetworkFailure(super.message, {super.cause});
}

class UnauthorizedFailure extends AppFailure {
  const UnauthorizedFailure(super.message, {super.cause});
}

class ValidationFailure extends AppFailure {
  const ValidationFailure(super.message, {super.cause});
}

class UnknownFailure extends AppFailure {
  const UnknownFailure(super.message, {super.cause});
}

class AppResult<T> {
  final T? value;
  final AppFailure? failure;

  const AppResult.success(this.value) : failure = null;

  const AppResult.failure(this.failure) : value = null;

  bool get isSuccess => failure == null;

  bool get isFailure => failure != null;

  T get requireValue {
    final currentValue = value;
    if (isFailure || currentValue == null) {
      throw StateError('AppResult does not contain a value');
    }
    return currentValue;
  }
}

Future<AppResult<T>> appResultOf<T>(Future<T> Function() run) async {
  try {
    return AppResult.success(await run());
  } catch (error) {
    return AppResult.failure(toAppFailure(error));
  }
}

Future<AppResult<void>> appVoidResultOf(Future<void> Function() run) async {
  try {
    await run();
    return const AppResult.success(null);
  } catch (error) {
    return AppResult.failure(toAppFailure(error));
  }
}

AppFailure toAppFailure(Object error) {
  if (error is AppFailure) return error;
  if (error is SocketException || error is TimeoutException) {
    return NetworkFailure(_cleanMessage(error), cause: error);
  }
  return UnknownFailure(_cleanMessage(error), cause: error);
}

String _cleanMessage(Object error) {
  final message = error.toString();
  const prefixes = ['Exception: ', 'Bad state: '];
  for (final prefix in prefixes) {
    if (message.startsWith(prefix)) {
      return message.substring(prefix.length);
    }
  }
  return message;
}

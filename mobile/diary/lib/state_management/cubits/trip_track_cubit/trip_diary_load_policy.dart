class TripDiaryLoadPolicy {
  final Duration pollingInterval;
  final Duration requestTimeout;
  final Duration retryBaseDelay;
  final Duration retryMaxDelay;

  const TripDiaryLoadPolicy({
    this.pollingInterval = const Duration(seconds: 1),
    this.requestTimeout = const Duration(seconds: 20),
    this.retryBaseDelay = const Duration(seconds: 2),
    this.retryMaxDelay = const Duration(seconds: 30),
  });

  Duration retryDelay(int failureStreak) {
    final multiplier = 1 << (failureStreak - 1).clamp(0, 10);
    final delay = retryBaseDelay * multiplier;
    return delay > retryMaxDelay ? retryMaxDelay : delay;
  }
}

class ReplayStopResult {
  final int? tripId;

  const ReplayStopResult({required this.tripId});
}

class AcquisitionStopResult {
  final String? syncSessionId;
  final ReplayStopResult? replayResult;

  const AcquisitionStopResult._({
    this.syncSessionId,
    this.replayResult,
  });

  const AcquisitionStopResult.none() : this._();

  const AcquisitionStopResult.syncSession(String sessionId)
      : this._(syncSessionId: sessionId);

  const AcquisitionStopResult.replay(ReplayStopResult result)
      : this._(replayResult: result);
}

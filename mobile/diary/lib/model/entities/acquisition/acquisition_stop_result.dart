class ReplayStopResult {
  final int? tripId;
  const ReplayStopResult({required this.tripId});
}

// Classe che trasporta i dati finali di una AcquisitionStrategy (Live/Replay) quando si chiude
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

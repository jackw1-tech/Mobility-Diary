import 'acquisition_diagnostics_report.dart';

class ReplayStopResult {
  final int? tripId;
  const ReplayStopResult({required this.tripId});
}

// Classe che trasporta i dati finali di una AcquisitionStrategy (Live/Replay) quando si chiude
class AcquisitionStopResult {
  final String? syncSessionId;
  final ReplayStopResult? replayResult;
  final AcquisitionDiagnosticsReport? diagnosticsReport;

  const AcquisitionStopResult._({
    this.syncSessionId,
    this.replayResult,
    this.diagnosticsReport,
  });

  const AcquisitionStopResult.none() : this._();

  const AcquisitionStopResult.syncSession(
    String sessionId, {
    AcquisitionDiagnosticsReport? diagnosticsReport,
  }) : this._(
          syncSessionId: sessionId,
          diagnosticsReport: diagnosticsReport,
        );

  const AcquisitionStopResult.replay(ReplayStopResult result)
      : this._(replayResult: result);
}

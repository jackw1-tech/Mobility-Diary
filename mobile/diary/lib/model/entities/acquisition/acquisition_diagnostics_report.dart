class AcquisitionDiagnosticsReport {
  final String sessionId;
  final String filePath;
  final String fileName;
  final String content;
  final int sizeBytes;
  final int decisionCount;
  final DateTime startedAt;
  final DateTime endedAt;

  const AcquisitionDiagnosticsReport({
    required this.sessionId,
    required this.filePath,
    required this.fileName,
    required this.content,
    required this.sizeBytes,
    required this.decisionCount,
    required this.startedAt,
    required this.endedAt,
  });
}

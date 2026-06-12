enum AcquisitionSyncStatus {
  none,
  pending,
  packaging,
  uploading,
  waitingProcessing,
  completed,
  failedRetryable,
  failedFinal,
}

class AcquisitionSyncSnapshot {
  final AcquisitionSyncStatus status;
  final String? localSessionId;
  final int? remoteIngestionId;
  final int attempts;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime? updatedAt;

  const AcquisitionSyncSnapshot({
    required this.status,
    this.localSessionId,
    this.remoteIngestionId,
    this.attempts = 0,
    this.nextRetryAt,
    this.lastError,
    this.updatedAt,
  });

  const AcquisitionSyncSnapshot.none()
      : status = AcquisitionSyncStatus.none,
        localSessionId = null,
        remoteIngestionId = null,
        attempts = 0,
        nextRetryAt = null,
        lastError = null,
        updatedAt = null;

  bool get hasJob => status != AcquisitionSyncStatus.none;

  bool get isWorking {
    return status == AcquisitionSyncStatus.packaging ||
        status == AcquisitionSyncStatus.uploading ||
        status == AcquisitionSyncStatus.waitingProcessing;
  }

  bool get isTerminal {
    return status == AcquisitionSyncStatus.completed ||
        status == AcquisitionSyncStatus.failedFinal;
  }

  bool get isFailed {
    return status == AcquisitionSyncStatus.failedRetryable ||
        status == AcquisitionSyncStatus.failedFinal;
  }
}

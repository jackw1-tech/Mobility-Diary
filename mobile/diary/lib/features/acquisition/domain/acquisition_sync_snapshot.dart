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
  final AcquisitionSyncStatus rawStatus;
  final String? localSessionId;
  final int? remoteIngestionId;
  final int? remoteTripId;
  final bool coreMapAvailable;
  final int attempts;
  final DateTime? nextRetryAt;
  final String? lastError;
  final DateTime? updatedAt;

  const AcquisitionSyncSnapshot({
    required this.status,
    this.rawStatus = AcquisitionSyncStatus.none,
    this.localSessionId,
    this.remoteIngestionId,
    this.remoteTripId,
    this.coreMapAvailable = false,
    this.attempts = 0,
    this.nextRetryAt,
    this.lastError,
    this.updatedAt,
  });

  const AcquisitionSyncSnapshot.none()
      : status = AcquisitionSyncStatus.none,
        rawStatus = AcquisitionSyncStatus.none,
        localSessionId = null,
        remoteIngestionId = null,
        remoteTripId = null,
        coreMapAvailable = false,
        attempts = 0,
        nextRetryAt = null,
        lastError = null,
        updatedAt = null;

  bool get hasJob => status != AcquisitionSyncStatus.none;

  bool get isCoreCompleted => status == AcquisitionSyncStatus.completed;

  bool get canOpenCoreDetail => isCoreCompleted && remoteTripId != null;

  bool shouldOpenCoreDetailAfter(AcquisitionSyncSnapshot previous) {
    return canOpenCoreDetail &&
        (!previous.isCoreCompleted || previous.remoteTripId != remoteTripId);
  }

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
        status == AcquisitionSyncStatus.failedFinal ||
        rawStatus == AcquisitionSyncStatus.failedRetryable ||
        rawStatus == AcquisitionSyncStatus.failedFinal;
  }

  bool get isRawWorking {
    return rawStatus == AcquisitionSyncStatus.packaging ||
        rawStatus == AcquisitionSyncStatus.uploading ||
        rawStatus == AcquisitionSyncStatus.waitingProcessing;
  }
}

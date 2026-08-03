class PresignResult {
  final String objectKey;
  final String uploadUrl;
  final Map<String, String> uploadHeaders;

  const PresignResult({
    required this.objectKey,
    required this.uploadUrl,
    this.uploadHeaders = const {},
  });
}

class IngestionStatus {
  final String coreStatus;
  final String rawStatus;
  final List<int> missingRawParts;
  final int? tripId;
  final bool mapAvailable;

  const IngestionStatus({
    required this.coreStatus,
    required this.rawStatus,
    required this.missingRawParts,
    this.tripId,
    this.mapAvailable = false,
  });

  bool get isCoreCompleted => coreStatus == 'COMPLETED';
  bool get isCoreFailedFinal => coreStatus == 'FAILED_FINAL';
  bool get isRawDone => rawStatus == 'COMPLETED';
  bool get isRawFailedFinal => rawStatus == 'FAILED_FINAL';
  bool get isRawBackendProcessing =>
      rawStatus == 'QUEUED' ||
      rawStatus == 'PROCESSING' ||
      rawStatus == 'FAILED_RETRYABLE';
  bool get canCompleteRaw => rawStatus == 'RECEIVED';

  bool get isCoreBackendProcessing {
    return coreStatus == 'QUEUED' ||
        coreStatus == 'PROCESSING' ||
        coreStatus == 'FAILED_RETRYABLE';
  }

  bool get canReceiveRawParts =>
      rawStatus == 'PENDING' || rawStatus == 'RECEIVING';
}

class InlineCoreResult {
  final int ingestionId;
  final int? tripId;
  final String coreStatus;
  final String rawStatus;
  final bool mapAvailable;

  const InlineCoreResult({
    required this.ingestionId,
    required this.tripId,
    required this.coreStatus,
    required this.rawStatus,
    required this.mapAvailable,
  });

  bool get isCoreCompleted => coreStatus == 'COMPLETED';
  bool get isCoreFailedFinal => coreStatus == 'FAILED_FINAL';
  bool get isCoreBackendProcessing {
    return coreStatus == 'QUEUED' ||
        coreStatus == 'PROCESSING' ||
        coreStatus == 'FAILED_RETRYABLE';
  }

  bool get isRawDone => rawStatus == 'COMPLETED';
  bool get isRawFailedFinal => rawStatus == 'FAILED_FINAL';
  bool get isRawBackendProcessing =>
      rawStatus == 'QUEUED' ||
      rawStatus == 'PROCESSING' ||
      rawStatus == 'FAILED_RETRYABLE';
  bool get canCompleteRaw => rawStatus == 'RECEIVED';
  bool get canReceiveRawParts =>
      rawStatus == 'PENDING' || rawStatus == 'RECEIVING';
}

class IngestionStartResult {
  final int ingestionId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;
  final bool alreadyExists;

  const IngestionStartResult({
    required this.ingestionId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    required this.alreadyExists,
  });
}

class ActiveIngestion {
  final int ingestionId;
  final String clientSessionId;
  final String deviceId;
  final DateTime recordingStartedAt;
  final DateTime? lastSeenAt;

  const ActiveIngestion({
    required this.ingestionId,
    required this.clientSessionId,
    required this.deviceId,
    required this.recordingStartedAt,
    this.lastSeenAt,
  });
}

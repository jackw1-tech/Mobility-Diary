import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/theme/semantic_colors.dart';
import 'package:flutter/material.dart';

/// Presentazione degli snack di debug sync mostrati sulla home: decidono se e
/// come raccontare all'utente l'avanzamento dell'upload di un viaggio.

bool shouldShowSyncDebugSnack(
  AcquisitionSyncSnapshot previous,
  AcquisitionSyncSnapshot current,
) {
  if (!current.hasJob) return false;

  return previous.localSessionId != current.localSessionId ||
      previous.status != current.status ||
      previous.rawStatus != current.rawStatus ||
      previous.remoteUploadId != current.remoteUploadId ||
      previous.remoteTripId != current.remoteTripId ||
      previous.attempts != current.attempts ||
      previous.lastError != current.lastError;
}

SnackBar? syncDebugSnackBar(AcquisitionSyncSnapshot sync, {required SemanticColors sem}) {
  final message = syncDebugMessage(sync);
  if (message == null) return null;

  return SnackBar(
    content: Text(message),
    duration: const Duration(milliseconds: 2200),
    backgroundColor: syncDebugSnackColor(sync, sem: sem),
  );
}

String? syncDebugMessage(AcquisitionSyncSnapshot sync) {
  if (!sync.hasJob) return null;

  if (sync.isFailed) {
    final detail = sync.lastError?.trim();
    final suffix = detail == null || detail.isEmpty ? '' : ': $detail';
    if (sync.isNonRecoverable) {
      return 'Sync fallita definitivamente$suffix';
    }
    return 'Sync in retry$suffix';
  }

  if (sync.status == AcquisitionSyncStatus.pending) {
    return 'Sync: viaggio in coda';
  }

  if (sync.status == AcquisitionSyncStatus.packaging) {
    return 'Sync: preparo pacchetto GPS e HAR';
  }

  if (sync.status == AcquisitionSyncStatus.uploading) {
    return 'Sync: invio core GPS/FSM';
  }

  if (sync.status == AcquisitionSyncStatus.waitingProcessing) {
    return 'Sync: backend sta creando il viaggio';
  }

  if (sync.status == AcquisitionSyncStatus.completed &&
      sync.rawStatus == AcquisitionSyncStatus.pending) {
    return 'Core caricato. HAR dichiarata: backend attende i raw';
  }

  if (sync.rawStatus == AcquisitionSyncStatus.packaging) {
    return 'HAR: preparo finestre sensori';
  }

  if (sync.rawStatus == AcquisitionSyncStatus.uploading) {
    return 'HAR trovata: upload sensor_windows';
  }

  if (sync.rawStatus == AcquisitionSyncStatus.waitingProcessing) {
    return 'Raw confermati. Processing HAR finale';
  }

  if (sync.status == AcquisitionSyncStatus.completed &&
      sync.rawStatus == AcquisitionSyncStatus.completed) {
    return 'Traccia processata';
  }

  return null;
}

Color syncDebugSnackColor(AcquisitionSyncSnapshot sync, {required SemanticColors sem}) {
  if (sync.isNonRecoverable) return sem.error;
  if (sync.isFailed) return sem.warning;
  if (sync.status == AcquisitionSyncStatus.completed &&
      sync.rawStatus == AcquisitionSyncStatus.completed) {
    return sem.success;
  }
  return sem.info;
}

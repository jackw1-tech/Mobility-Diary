import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue.dart';
import 'package:drift/drift.dart' show Value;

/// Processore opportunistico dei SyncJob: per ogni job pronto esegue
/// packaging -> create -> (presign -> PUT -> confirm)* -> complete -> poll,
/// con retry/backoff. Tutta la sequenza e' idempotente lato backend, quindi un
/// job interrotto puo' riprendere senza duplicare
/// (REPORT_STRATEGIA_INGESTION_ASINCRONA.md D5/D7).
class TripSyncQueueImpl implements TripSyncQueue {
  final AcquisitionDao _dao;
  final TripPackageBuilder _builder;
  final TripIngestionApi _api;
  final AccessTokenProvider _tokenProvider;
  final List<Duration> _backoff;
  final int _maxAttempts;
  final Duration _pollDelay;
  bool _running = false;

  TripSyncQueueImpl({
    required AcquisitionDao dao,
    required TripPackageBuilder builder,
    required TripIngestionApi api,
    required AccessTokenProvider tokenProvider,
    List<Duration>? backoff,
    int maxAttempts = 5,
    Duration pollDelay = const Duration(seconds: 15),
  })  : _dao = dao,
        _builder = builder,
        _api = api,
        _tokenProvider = tokenProvider,
        _maxAttempts = maxAttempts,
        _pollDelay = pollDelay,
        _backoff = backoff ??
            const [
              Duration(seconds: 10),
              Duration(seconds: 30),
              Duration(minutes: 2),
              Duration(minutes: 10),
            ];

  @override
  Future<void> kick() => processDue();

  /// Elabora una passata di tutti i SyncJob pronti. Rientrante: una sola
  /// esecuzione alla volta.
  Future<void> processDue() async {
    if (_running) return;
    // Senza sessione autenticata non si tenta nulla: evita di bruciare retry
    // se la coda viene "kickata" prima del login.
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) return;

    _running = true;
    try {
      final jobs = await _dao.claimableSyncJobs(DateTime.now().toUtc());
      for (final job in jobs) {
        await _processJob(job);
      }
    } finally {
      _running = false;
    }
  }

  Future<void> _processJob(SyncJob job) async {
    try {
      if (job.coreStatus == syncJobFailedFinal) return;

      final coreAlreadyCompleted = job.coreStatus == syncJobCompleted;
      await _dao.updateSyncJob(
        job.id,
        coreStatus: coreAlreadyCompleted ? null : syncJobPackaging,
        rawStatus: coreAlreadyCompleted ? syncJobPackaging : null,
        lastError: const Value(null),
      );

      final package = await _builder.build(job.localSessionId);
      if (package.parts.isEmpty) {
        // Sessione senza dati da caricare: niente da fare.
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobCompleted,
          rawStatus: syncJobCompleted,
        );
        await _deletePackageDirectory(package);
        return;
      }
      if (package.coreParts.isEmpty) {
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobFailedFinal,
          rawStatus: syncJobFailedFinal,
          lastError: const Value('nessuna parte core da sincronizzare'),
        );
        return;
      }

      var ingestionId = job.remoteIngestionId;
      ingestionId ??= await _api.createIngestion(
        clientSessionId: job.localSessionId,
        expectedCoreParts: package.expectedCoreParts,
        expectedRawParts: package.expectedRawParts,
        startedAt: package.startedAt,
        endedAt: package.endedAt,
      );
      await _dao.updateSyncJob(
        job.id,
        coreStatus: syncJobUploading,
        remoteIngestionId: Value(ingestionId),
      );

      var status = await _api.getStatus(ingestionId);
      if (status.isCoreFailedFinal) {
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobFailedFinal,
          lastError: const Value('elaborazione core backend fallita'),
        );
        return;
      }
      if (status.isCoreBackendProcessing) {
        await _waitForCoreProcessing(job);
        return;
      }

      if (!status.isCoreCompleted && status.canReceiveCoreParts) {
        await _uploadMissingParts(
          ingestionId,
          package.coreParts,
          status.missingCoreParts,
          uploadAll: status.coreStatus == 'PENDING',
        );
        await _api.completeCoreIngestion(
          ingestionId,
          totalParts: package.coreParts.length,
        );
        await _dao.updateSyncJob(job.id, coreStatus: syncJobWaitingProcessing);
        status = await _api.getStatus(ingestionId);

        if (status.isCoreCompleted) {
          await _dao.updateSyncJob(job.id, coreStatus: syncJobCompleted);
        } else if (status.isCoreFailedFinal) {
          await _dao.updateSyncJob(
            job.id,
            coreStatus: syncJobFailedFinal,
            lastError: const Value('elaborazione core backend fallita'),
          );
          return;
        } else {
          await _waitForCoreProcessing(job);
          return;
        }
      }

      if (status.isCoreCompleted) {
        // Persisto il trip_id materializzato dal backend: serve alla UI per
        // aprire la mappa del viaggio. Non sovrascrivo se ancora assente.
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobCompleted,
          remoteTripId:
              status.tripId != null ? Value(status.tripId) : const Value.absent(),
        );
        if (package.rawParts.isEmpty || status.isRawDone) {
          await _finalizeAllDone(job, package);
          return;
        }
        if (status.isRawFailedFinal) {
          await _dao.updateSyncJob(
            job.id,
            rawStatus: syncJobFailedFinal,
            lastError: const Value('raw sensor ingestion fallita'),
          );
          return;
        }
        if (status.canReceiveRawParts) {
          await _dao.updateSyncJob(job.id, rawStatus: syncJobUploading);
          await _uploadMissingParts(
            ingestionId,
            package.rawParts,
            status.missingRawParts,
            uploadAll: status.rawStatus == 'PENDING',
          );
          await _api.completeRawIngestion(
            ingestionId,
            totalParts: package.rawParts.length,
          );
          status = await _api.getStatus(ingestionId);
          if (status.isRawDone) {
            await _finalizeAllDone(job, package);
            return;
          }
        }

        await _dao.updateSyncJob(
          job.id,
          rawStatus: syncJobFailedRetryable,
          nextRetryAt: Value(DateTime.now().toUtc().add(_pollDelay)),
          lastError: const Value('raw sensor ingestion non completata'),
        );
        return;
      }

      throw IngestionApiException(
          'stato ingestion non gestito: core=${status.coreStatus}, raw=${status.rawStatus}');
    } catch (error) {
      await _handleFailure(job, error);
    }
  }

  Future<void> _uploadMissingParts(
    int ingestionId,
    List<TripPackagePart> parts,
    List<({String kind, int sequence})> missingParts, {
    required bool uploadAll,
  }) async {
    final missing = missingParts.map((m) => '${m.kind}#${m.sequence}').toSet();

    for (final part in parts) {
      final key = '${part.kind}#${part.sequence}';
      if (!uploadAll && !missing.contains(key)) continue;

      final presign = await _api.presignPart(
        ingestionId,
        kind: part.kind,
        sequence: part.sequence,
        sha256: part.sha256,
        sizeBytes: part.sizeBytes,
      );
      final bytes = await part.file.readAsBytes();
      await _api.uploadPart(
        presign.uploadUrl,
        bytes,
        headers: presign.uploadHeaders,
      );
      await _api.confirmPart(
        ingestionId,
        kind: part.kind,
        sequence: part.sequence,
        sha256: part.sha256,
      );
    }
  }

  Future<void> _finalizeAllDone(SyncJob job, TripPackage package) async {
    await _dao.updateSyncJob(
      job.id,
      coreStatus: syncJobCompleted,
      rawStatus: syncJobCompleted,
    );
    await _deletePackageDirectory(package);
  }

  Future<void> _deletePackageDirectory(TripPackage package) async {
    // Pulizia dei blob temporanei su disco.
    if (await package.directory.exists()) {
      await package.directory.delete(recursive: true);
    }
  }

  Future<void> _waitForCoreProcessing(SyncJob job) {
    return _dao.updateSyncJob(
      job.id,
      coreStatus: syncJobWaitingProcessing,
      nextRetryAt: Value(DateTime.now().toUtc().add(_pollDelay)),
    );
  }

  Future<void> _handleFailure(SyncJob job, Object error) async {
    final currentJob = await _dao.syncJobForSession(job.localSessionId) ?? job;
    final coreCompleted = currentJob.coreStatus == syncJobCompleted;
    final attempts = currentJob.attempts + 1;
    if (attempts >= _maxAttempts) {
      await _dao.updateSyncJob(
        job.id,
        coreStatus: coreCompleted ? null : syncJobFailedFinal,
        rawStatus: syncJobFailedFinal,
        attempts: attempts,
        lastError: Value(error.toString()),
      );
      return;
    }
    final delay = _backoff[
        attempts - 1 < _backoff.length ? attempts - 1 : _backoff.length - 1];
    await _dao.updateSyncJob(
      job.id,
      coreStatus: coreCompleted ? null : syncJobFailedRetryable,
      rawStatus: coreCompleted ? syncJobFailedRetryable : null,
      attempts: attempts,
      nextRetryAt: Value(DateTime.now().toUtc().add(delay)),
      lastError: Value(error.toString()),
    );
  }
}

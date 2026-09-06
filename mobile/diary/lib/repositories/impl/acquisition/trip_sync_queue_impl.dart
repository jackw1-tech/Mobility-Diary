import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/model/entities/acquisition/upload_models.dart';
import 'package:diary/mappers/upload_mapper.dart';
import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/repositories/impl/acquisition/trip_package_builder.dart';
import 'package:diary/network/service/trips_service.dart';
import 'package:drift/drift.dart' show Value;

/// Processore opportunistico dei SyncJob: per ogni job pronto esegue
/// packaging -> POST core inline -> raw presigned, con retry/backoff. Tutta la
/// sequenza e' idempotente lato backend, quindi un job interrotto puo'
/// riprendere senza duplicare.
///
/// Un fallimento definitivo (core o raw) non resta mai in attesa di un'azione
/// dell'utente: viene scartato in automatico (Trip lato backend eliminato se
/// gia' esistente, dati locali cancellati) — vedi [_discardJob].
class TripSyncQueueImpl {
  final AcquisitionDao _dao;
  final TripPackageBuilder _builder;
  final TripUploadService _service;
  final UploadMapper _mapper;
  final TripsService? _tripsService;
  final AccessTokenProvider _tokenProvider;
  final List<Duration> _backoff;
  final int _maxAttempts;
  final Duration _pollDelay;
  final Duration _processingPollDelay;
  final int _rawUploadConcurrency;
  bool _running = false;

  TripSyncQueueImpl({
    required AcquisitionDao dao,
    required TripPackageBuilder builder,
    required TripUploadService service,
    required UploadMapper mapper,
    required AccessTokenProvider tokenProvider,
    TripsService? tripsService,
    List<Duration>? backoff,
    int maxAttempts = 5,
    Duration pollDelay = const Duration(seconds: 15),
    Duration processingPollDelay = const Duration(seconds: 2),
    int rawUploadConcurrency = 3,
  })  : _dao = dao,
        _builder = builder,
        _service = service,
        _mapper = mapper,
        _tripsService = tripsService,
        _tokenProvider = tokenProvider,
        _maxAttempts = maxAttempts,
        _pollDelay = pollDelay,
        _processingPollDelay = processingPollDelay,
        _rawUploadConcurrency =
            rawUploadConcurrency < 1 ? 1 : rawUploadConcurrency,
        _backoff = backoff ??
            const [
              Duration(seconds: 10),
              Duration(seconds: 30),
              Duration(minutes: 2),
              Duration(minutes: 10),
            ];

  Future<void> kick() => processDue();

  //Esegue uno alla volta i sync job in ordine cronologico, prima i vecchi
  Future<void> processDue() async {
    if (_running) return;
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
      if (!coreAlreadyCompleted &&
          package.corePayload == null &&
          package.rawParts.isEmpty) {
        await _deletePackageDirectory(package);
        await _dao.purgeSyncedSession(job.localSessionId);
        return;
      }
      if (!coreAlreadyCompleted && package.corePayload == null) {
        await _discardJob(job);
        return;
      }

      var uploadId = job.remoteUploadId ?? package.remoteUploadId;
      UploadStatus status;
      if (coreAlreadyCompleted) {
        if (uploadId == null) {
          throw const UploadApiException('remote upload assente');
        }
        status = _mapper.mapUploadStatus(await _service.getStatus(uploadId));
      } else {
        final corePayload = package.corePayload!;
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobUploading,
          remoteUploadId:
              uploadId == null ? const Value.absent() : Value(uploadId),
          corePayloadSizeBytes: corePayload.sizeBytes,
        );
        final coreResult = _mapper.mapInlineCoreResult(
          await _service.postCoreInline(body: corePayload.requestBody),
        );
        uploadId = coreResult.uploadId;
        status = _statusFromInlineResult(coreResult);
      }

      if (status.isCoreFailedFinal) {
        await _discardJob(job);
        return;
      }
      if (status.isCoreBackendProcessing) {
        await _waitForCoreProcessing(
          job,
          remoteUploadId: uploadId,
          delay: _processingDelayFor(status.coreStatus),
        );
        return;
      }

      if (status.isCoreCompleted) {
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobCompleted,
          coreMapAvailable: status.mapAvailable,
          remoteUploadId: Value(uploadId),
          remoteTripId: status.tripId != null
              ? Value(status.tripId)
              : const Value.absent(),
        );
        if (await _handleRawOutcome(job, package, uploadId, status)) {
          return;
        }
        if (status.canReceiveRawParts) {
          await _dao.updateSyncJob(job.id, rawStatus: syncJobUploading);
          await _uploadRawParts(uploadId, package.rawParts);
          await _service.completeRawUpload(
            uploadId,
            totalParts: package.rawParts.length,
          );
          status = _mapper.mapUploadStatus(await _service.getStatus(uploadId));
          if (await _handleRawOutcome(job, package, uploadId, status)) {
            return;
          }
        }
        if (status.canCompleteRaw) {
          await _service.completeRawUpload(
            uploadId,
            totalParts: package.rawParts.length,
          );
          status = _mapper.mapUploadStatus(await _service.getStatus(uploadId));
          if (await _handleRawOutcome(job, package, uploadId, status)) {
            return;
          }
        }

        await _dao.updateSyncJob(
          job.id,
          rawStatus: syncJobFailedRetryable,
          nextRetryAt: Value(DateTime.now().toUtc().add(_pollDelay)),
          lastError: const Value('raw sensor upload non completata'),
        );
        return;
      }

      throw UploadApiException(
          'stato upload non gestito: core=${status.coreStatus}, raw=${status.rawStatus}');
    } catch (error) {
      await _handleFailure(job, error);
    }
  }

  /// Controlla in diversi punti del codice se il caricamento raw è concluso
  Future<bool> _handleRawOutcome(
    SyncJob job,
    TripPackage package,
    int uploadId,
    UploadStatus status,
  ) async {
    if (status.isRawDone) {
      //completato con successo
      await _finalizeAllDone(job, package);
      return true;
    }
    if (status.isRawFailedFinal) {
      await _discardJob(job, remoteTripId: status.tripId);
      return true;
    }
    if (status.isRawBackendProcessing) {
      await _deletePackageDirectory(package);
      await _waitForRawProcessing(
        job,
        remoteUploadId: uploadId,
        delay: _processingDelayFor(status.rawStatus),
      );
      return true;
    }
    return false;
  }

  // Upload effettivo delle raw, a blocchi di _rawUploadConcurrency alla volta.
  Future<void> _uploadRawParts(
    int uploadId,
    List<TripPackagePart> parts,
  ) async {
    for (final batch in _inBatches(parts, _rawUploadConcurrency)) {
      await Future.wait(
        batch.map((part) => _uploadSinglePart(uploadId, part)),
      );
    }
  }

  Iterable<List<TripPackagePart>> _inBatches(
    List<TripPackagePart> parts,
    int size,
  ) sync* {
    for (var start = 0; start < parts.length; start += size) {
      yield parts.sublist(start, (start + size).clamp(0, parts.length));
    }
  }

  // Upload di un singolo blocco
  Future<void> _uploadSinglePart(int uploadId, TripPackagePart part) async {
    final presign = _mapper.mapPresignResult(await _service.presignPart(
      uploadId,
      sequence: part.sequence,
      sha256: part.sha256,
    ));
    final bytes = await part.file.readAsBytes();
    await _service.uploadPart(
      presign.uploadUrl,
      bytes,
      headers: presign.uploadHeaders,
    );
    await _service.confirmPart(
      uploadId,
      sequence: part.sequence,
      sha256: part.sha256,
    );
  }

  UploadStatus _statusFromInlineResult(InlineCoreResult result) {
    return UploadStatus(
      coreStatus: result.coreStatus,
      rawStatus: result.rawStatus,
      tripId: result.tripId,
      mapAvailable: result.mapAvailable,
    );
  }

  // Aggiorno lo stato locale del caricamento del viaggio a concluso e cancello
  // i file compressi e tutte le righe del db relative al quel viaggio
  Future<void> _finalizeAllDone(SyncJob job, TripPackage package) async {
    await _dao.updateSyncJob(
      job.id,
      coreStatus: syncJobCompleted,
      rawStatus: syncJobCompleted,
    );
    await _deletePackageDirectory(package);
    await _dao.purgeSyncedSession(job.localSessionId);
  }

  // Elimino i file temporanei compressi che sono stati mandati al bucket
  Future<void> _deletePackageDirectory(TripPackage package) async {
    if (await package.directory.exists()) {
      await package.directory.delete(recursive: true);
    }
  }

  Duration _processingDelayFor(String status) {
    return status == 'FAILED_RETRYABLE' ? _pollDelay : _processingPollDelay;
  }

  Future<void> _waitForCoreProcessing(
    SyncJob job, {
    int? remoteUploadId,
    Duration? delay,
  }) {
    return _dao.updateSyncJob(
      job.id,
      coreStatus: syncJobWaitingProcessing,
      remoteUploadId:
          remoteUploadId == null ? const Value.absent() : Value(remoteUploadId),
      nextRetryAt: Value(DateTime.now().toUtc().add(delay ?? _pollDelay)),
    );
  }

  Future<void> _waitForRawProcessing(
    SyncJob job, {
    int? remoteUploadId,
    Duration? delay,
  }) {
    return _dao.updateSyncJob(
      job.id,
      rawStatus: syncJobWaitingProcessing,
      remoteUploadId:
          remoteUploadId == null ? const Value.absent() : Value(remoteUploadId),
      nextRetryAt: Value(DateTime.now().toUtc().add(delay ?? _pollDelay)),
    );
  }

  Future<void> _handleFailure(SyncJob job, Object error) async {
    final currentJob = await _dao.syncJobForSession(job.localSessionId) ?? job;
    final coreCompleted = currentJob.coreStatus == syncJobCompleted;
    if (error is UploadApiException && error.statusCode == 410) {
      await _discardJob(currentJob);
      return;
    }
    final attempts = currentJob.attempts + 1;
    if (attempts >= _maxAttempts) {
      await _discardJob(currentJob);
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

  Future<void> _discardJob(SyncJob job, {int? remoteTripId}) async {
    final tripId = remoteTripId ?? job.remoteTripId;
    if (tripId != null) {
      try {
        await _tripsService?.deleteTrip(tripId);
      } catch (_) {}
    }
    await _dao.purgeSyncedSession(job.localSessionId);
  }
}

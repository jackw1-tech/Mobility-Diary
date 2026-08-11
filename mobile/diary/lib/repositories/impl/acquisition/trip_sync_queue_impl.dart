import 'package:diary/network/service/impl/acquisition_local_database.dart';
import 'package:diary/model/entities/acquisition/ingestion_models.dart';
import 'package:diary/mappers/ingestion_mapper.dart';
import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/repositories/impl/acquisition/trip_package_builder.dart';
import 'package:diary/repositories/trip_sync_queue.dart';
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
class TripSyncQueueImpl implements TripSyncQueue {
  final AcquisitionDao _dao;
  final TripPackageBuilder _builder;
  final TripIngestionService _service;
  final IngestionMapper _mapper;
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
    required TripIngestionService service,
    required IngestionMapper mapper,
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
      if (!coreAlreadyCompleted &&
          package.corePayload == null &&
          package.rawParts.isEmpty) {
        // Sessione senza dati da caricare: niente da fare, ma non deve
        // restare in giro per sempre — pulizia locale come un successo vuoto.
        await _deletePackageDirectory(package);
        await _dao.purgeSyncedSession(job.localSessionId);
        return;
      }
      if (!coreAlreadyCompleted && package.corePayload == null) {
        await _discardJob(job);
        return;
      }

      var ingestionId = job.remoteIngestionId ?? package.remoteIngestionId;
      late IngestionStatus status;
      if (coreAlreadyCompleted) {
        if (ingestionId == null) {
          throw const IngestionApiException('remote ingestion assente');
        }
        status =
            _mapper.mapIngestionStatus(await _service.getStatus(ingestionId));
      } else {
        final corePayload = package.corePayload!;
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobUploading,
          remoteIngestionId:
              ingestionId == null ? const Value.absent() : Value(ingestionId),
          corePayloadSizeBytes: corePayload.sizeBytes,
        );

        // `ingestionId` puo' essere gia' noto qui perche' `start_ingestion`
        // crea la riga remota all'avvio della registrazione. Il core pero'
        // entra sempre solo da questo endpoint inline.
        final coreResult = _mapper.mapInlineCoreResult(
          await _service.postCoreInline(body: corePayload.requestBody),
        );
        ingestionId = coreResult.ingestionId;
        status = _statusFromInlineResult(coreResult, package.rawParts);
      }

      if (status.isCoreFailedFinal) {
        await _discardJob(job);
        return;
      }
      if (status.isCoreBackendProcessing) {
        await _waitForCoreProcessing(
          job,
          remoteIngestionId: ingestionId,
          delay: _processingDelayFor(status.coreStatus),
        );
        return;
      }

      if (status.isCoreCompleted) {
        // Persisto il trip_id materializzato dal backend: serve alla UI per
        // aprire la mappa del viaggio. Non sovrascrivo se ancora assente.
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobCompleted,
          coreMapAvailable: status.mapAvailable,
          remoteIngestionId: Value(ingestionId),
          remoteTripId: status.tripId != null
              ? Value(status.tripId)
              : const Value.absent(),
        );
        if (await _handleRawOutcome(job, package, ingestionId, status)) {
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
          await _service.completeRawIngestion(
            ingestionId,
            totalParts: package.rawParts.length,
          );
          status =
              _mapper.mapIngestionStatus(await _service.getStatus(ingestionId));
          if (await _handleRawOutcome(job, package, ingestionId, status)) {
            return;
          }
        }
        if (status.canCompleteRaw) {
          await _service.completeRawIngestion(
            ingestionId,
            totalParts: package.rawParts.length,
          );
          status =
              _mapper.mapIngestionStatus(await _service.getStatus(ingestionId));
          if (await _handleRawOutcome(job, package, ingestionId, status)) {
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

  /// Gestisce gli esiti terminali/di attesa dello stato raw comuni ai tre
  /// punti in cui viene ricontrollato in [_processJob] (subito dopo il core,
  /// dopo l'upload delle parti mancanti, dopo il complete). Ritorna `true` se
  /// lo stato e' stato gestito (il chiamante deve fermarsi), `false` se serve
  /// proseguire con i passi successivi (upload/complete).
  Future<bool> _handleRawOutcome(
    SyncJob job,
    TripPackage package,
    int ingestionId,
    IngestionStatus status,
  ) async {
    if (status.isRawDone) {
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
        remoteIngestionId: ingestionId,
        delay: _processingDelayFor(status.rawStatus),
      );
      return true;
    }
    return false;
  }

  Future<void> _uploadMissingParts(
    int ingestionId,
    List<TripPackagePart> parts,
    List<int> missingParts, {
    required bool uploadAll,
  }) async {
    final selectedParts = [
      for (final part in parts)
        if (uploadAll || missingParts.contains(part.sequence)) part,
    ];

    for (var start = 0;
        start < selectedParts.length;
        start += _rawUploadConcurrency) {
      final proposedEnd = start + _rawUploadConcurrency;
      final end = proposedEnd > selectedParts.length
          ? selectedParts.length
          : proposedEnd;
      final batch = selectedParts.sublist(start, end);
      await Future.wait([
        for (final part in batch) _uploadSinglePart(ingestionId, part),
      ]);
    }
  }

  Future<void> _uploadSinglePart(int ingestionId, TripPackagePart part) async {
    final presign = _mapper.mapPresignResult(await _service.presignPart(
      ingestionId,
      sequence: part.sequence,
      sha256: part.sha256,
      sizeBytes: part.sizeBytes,
    ));
    final bytes = await part.file.readAsBytes();
    await _service.uploadPart(
      presign.uploadUrl,
      bytes,
      headers: presign.uploadHeaders,
    );
    await _service.confirmPart(
      ingestionId,
      sequence: part.sequence,
      sha256: part.sha256,
    );
  }

  IngestionStatus _statusFromInlineResult(
    InlineCoreResult result,
    List<TripPackagePart> rawParts,
  ) {
    return IngestionStatus(
      coreStatus: result.coreStatus,
      rawStatus: result.rawStatus,
      missingRawParts: _partKeys(rawParts),
      tripId: result.tripId,
      mapAvailable: result.mapAvailable,
    );
  }

  List<int> _partKeys(List<TripPackagePart> parts) {
    return [
      for (final part in parts) part.sequence,
    ];
  }

  Future<void> _finalizeAllDone(SyncJob job, TripPackage package) async {
    await _dao.updateSyncJob(
      job.id,
      coreStatus: syncJobCompleted,
      rawStatus: syncJobCompleted,
    );
    await _deletePackageDirectory(package);
    // Backend ha confermato core+raw COMPLETED: il telefono non e' piu'
    // l'unica copia. Cancella tutto il locale (dati grezzi, SyncJob, riga
    // sessione), non solo la mole.
    await _dao.purgeSyncedSession(job.localSessionId);
  }

  Future<void> _deletePackageDirectory(TripPackage package) async {
    // Pulizia dei blob temporanei su disco.
    if (await package.directory.exists()) {
      await package.directory.delete(recursive: true);
    }
  }

  Duration _processingDelayFor(String status) {
    return status == 'FAILED_RETRYABLE' ? _pollDelay : _processingPollDelay;
  }

  Future<void> _waitForCoreProcessing(
    SyncJob job, {
    int? remoteIngestionId,
    Duration? delay,
  }) {
    return _dao.updateSyncJob(
      job.id,
      coreStatus: syncJobWaitingProcessing,
      remoteIngestionId: remoteIngestionId == null
          ? const Value.absent()
          : Value(remoteIngestionId),
      nextRetryAt: Value(DateTime.now().toUtc().add(delay ?? _pollDelay)),
    );
  }

  Future<void> _waitForRawProcessing(
    SyncJob job, {
    int? remoteIngestionId,
    Duration? delay,
  }) {
    return _dao.updateSyncJob(
      job.id,
      rawStatus: syncJobWaitingProcessing,
      remoteIngestionId: remoteIngestionId == null
          ? const Value.absent()
          : Value(remoteIngestionId),
      nextRetryAt: Value(DateTime.now().toUtc().add(delay ?? _pollDelay)),
    );
  }

  Future<void> _handleFailure(SyncJob job, Object error) async {
    final currentJob = await _dao.syncJobForSession(job.localSessionId) ?? job;
    final coreCompleted = currentJob.coreStatus == syncJobCompleted;
    // 410: il backend ha gia' abbandonato o chiuso questa ingestion altrove
    // (es. un altro device ha avviato un nuovo viaggio dopo che questa e'
    // rimasta stantia oltre la soglia lato server). Non e' un fallimento
    // transitorio: nessun retry lo risolvera' mai, quindi si scarta subito
    // invece di bruciare tutto il budget di backoff su un esito gia' noto.
    if (error is IngestionApiException && error.statusCode == 410) {
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

  /// Un viaggio la cui sincronizzazione e' fallita in modo definitivo (core o
  /// raw, esauriti i tentativi) viene scartato subito, senza nessuna azione
  /// dell'utente: se il core era gia' riuscito (Trip gia' visibile nel
  /// diario, [remoteTripId] valorizzato), lo elimina anche li' — best-effort,
  /// un errore nell'eliminazione remota non deve impedire la pulizia locale.
  /// Poi cancella sempre dati grezzi, SyncJob e riga sessione in locale.
  Future<void> _discardJob(SyncJob job, {int? remoteTripId}) async {
    final tripId = remoteTripId ?? job.remoteTripId;
    if (tripId != null) {
      try {
        await _tripsService?.deleteTrip(tripId);
      } catch (_) {
        // Best-effort: non deve impedire la pulizia locale automatica.
      }
    }
    await _dao.purgeSyncedSession(job.localSessionId);
  }
}

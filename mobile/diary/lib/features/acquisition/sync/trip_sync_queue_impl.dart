import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/features/acquisition/sync/trip_package_builder.dart';
import 'package:diary/features/acquisition/sync/trip_sync_queue.dart';
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
  final TripIngestionApi _api;
  final TripsService? _tripsService;
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
    TripsService? tripsService,
    List<Duration>? backoff,
    int maxAttempts = 5,
    Duration pollDelay = const Duration(seconds: 15),
  })  : _dao = dao,
        _builder = builder,
        _api = api,
        _tripsService = tripsService,
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
        status = await _api.getStatus(ingestionId);
      } else {
        final corePayload = package.corePayload!;
        await _dao.updateSyncJob(
          job.id,
          coreStatus: syncJobUploading,
          remoteIngestionId:
              ingestionId == null ? const Value.absent() : Value(ingestionId),
          corePayloadSha256: Value(corePayload.sha256),
          corePayloadSizeBytes: corePayload.sizeBytes,
        );

        final coreResult = await _api.postCoreInline(
          body: corePayload.requestBody,
        );
        ingestionId = coreResult.ingestionId;
        status = _statusFromInlineResult(coreResult, package.rawParts);
      }

      if (status.isCoreFailedFinal) {
        await _discardJob(job);
        return;
      }
      if (status.isCoreBackendProcessing) {
        await _waitForCoreProcessing(job, remoteIngestionId: ingestionId);
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
        if (status.isRawDone) {
          await _finalizeAllDone(job, package);
          return;
        }
        if (status.isRawFailedFinal) {
          await _discardJob(job, remoteTripId: status.tripId);
          return;
        }
        if (status.isRawBackendProcessing) {
          await _deletePackageDirectory(package);
          await _waitForRawProcessing(job, remoteIngestionId: ingestionId);
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
          if (status.isRawFailedFinal) {
            await _discardJob(job, remoteTripId: status.tripId);
            return;
          }
          if (status.isRawBackendProcessing) {
            await _deletePackageDirectory(package);
            await _waitForRawProcessing(job, remoteIngestionId: ingestionId);
            return;
          }
        }
        if (status.canCompleteRaw) {
          await _api.completeRawIngestion(
            ingestionId,
            totalParts: package.rawParts.length,
          );
          status = await _api.getStatus(ingestionId);
          if (status.isRawDone) {
            await _finalizeAllDone(job, package);
            return;
          }
          if (status.isRawFailedFinal) {
            await _discardJob(job, remoteTripId: status.tripId);
            return;
          }
          if (status.isRawBackendProcessing) {
            await _deletePackageDirectory(package);
            await _waitForRawProcessing(job, remoteIngestionId: ingestionId);
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

  IngestionStatus _statusFromInlineResult(
    InlineCoreResult result,
    List<TripPackagePart> rawParts,
  ) {
    return IngestionStatus(
      coreStatus: result.coreStatus,
      rawStatus: result.rawStatus,
      missingCoreParts: const [],
      missingRawParts: _partKeys(rawParts),
      tripId: result.tripId,
      coreIngestionMode: 'INLINE',
      mapAvailable: result.mapAvailable,
    );
  }

  List<({String kind, int sequence})> _partKeys(List<TripPackagePart> parts) {
    return [
      for (final part in parts) (kind: part.kind, sequence: part.sequence),
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

  Future<void> _waitForCoreProcessing(SyncJob job, {int? remoteIngestionId}) {
    return _dao.updateSyncJob(
      job.id,
      coreStatus: syncJobWaitingProcessing,
      remoteIngestionId: remoteIngestionId == null
          ? const Value.absent()
          : Value(remoteIngestionId),
      nextRetryAt: Value(DateTime.now().toUtc().add(_pollDelay)),
    );
  }

  Future<void> _waitForRawProcessing(SyncJob job, {int? remoteIngestionId}) {
    return _dao.updateSyncJob(
      job.id,
      rawStatus: syncJobWaitingProcessing,
      remoteIngestionId: remoteIngestionId == null
          ? const Value.absent()
          : Value(remoteIngestionId),
      nextRetryAt: Value(DateTime.now().toUtc().add(_pollDelay)),
    );
  }

  Future<void> _handleFailure(SyncJob job, Object error) async {
    final currentJob = await _dao.syncJobForSession(job.localSessionId) ?? job;
    final coreCompleted = currentJob.coreStatus == syncJobCompleted;
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

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
      await _dao.updateSyncJob(
        job.id,
        status: syncJobPackaging,
        lastError: const Value(null),
      );

      final package = await _builder.build(job.localSessionId);
      if (package.parts.isEmpty) {
        // Sessione senza dati da caricare: niente da fare.
        await _dao.updateSyncJob(job.id, status: syncJobCompleted);
        return;
      }

      var ingestionId = job.remoteIngestionId;
      ingestionId ??= await _api.createIngestion(
        clientSessionId: job.localSessionId,
        expectedParts: package.expectedParts,
        startedAt: package.startedAt,
        endedAt: package.endedAt,
      );
      await _dao.updateSyncJob(
        job.id,
        status: syncJobUploading,
        remoteIngestionId: Value(ingestionId),
      );

      var status = await _api.getStatus(ingestionId);
      if (status.isProcessed) {
        await _finalizeSuccess(job, package);
        return;
      }
      if (status.isFailedFinal) {
        await _dao.updateSyncJob(
          job.id,
          status: syncJobFailedFinal,
          lastError: const Value('elaborazione backend fallita'),
        );
        return;
      }
      if (status.isBackendProcessing) {
        await _waitForBackendProcessing(job);
        return;
      }

      if (status.canReceiveParts) {
        await _uploadMissingParts(ingestionId, package, status);
        await _api.completeIngestion(
          ingestionId,
          totalParts: package.parts.length,
        );
        await _dao.updateSyncJob(job.id, status: syncJobWaitingProcessing);
        status = await _api.getStatus(ingestionId);

        if (status.isProcessed) {
          await _finalizeSuccess(job, package);
          return;
        }
        if (status.isFailedFinal) {
          await _dao.updateSyncJob(
            job.id,
            status: syncJobFailedFinal,
            lastError: const Value('elaborazione backend fallita'),
          );
          return;
        }
        await _waitForBackendProcessing(job);
        return;
      }

      throw IngestionApiException(
          'stato ingestion non gestito: ${status.status}');
    } catch (error) {
      await _handleFailure(job, error);
    }
  }

  Future<void> _uploadMissingParts(
    int ingestionId,
    TripPackage package,
    IngestionStatus status,
  ) async {
    // Alla prima creazione lo stato e' CREATED e nessuna parte risulta ancora
    // ricevuta: carichiamo tutto. Su un retry, carichiamo solo le mancanti.
    final uploadAll = status.status == 'CREATED';
    final missing =
        status.missingParts.map((m) => '${m.kind}#${m.sequence}').toSet();

    for (final part in package.parts) {
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

  Future<void> _finalizeSuccess(SyncJob job, TripPackage package) async {
    await _dao.updateSyncJob(job.id, status: syncJobCompleted);
    // Pulizia dei blob temporanei su disco.
    if (await package.directory.exists()) {
      await package.directory.delete(recursive: true);
    }
  }

  Future<void> _waitForBackendProcessing(SyncJob job) {
    return _dao.updateSyncJob(
      job.id,
      status: syncJobWaitingProcessing,
      nextRetryAt: Value(DateTime.now().toUtc().add(_pollDelay)),
    );
  }

  Future<void> _handleFailure(SyncJob job, Object error) async {
    final attempts = job.attempts + 1;
    if (attempts >= _maxAttempts) {
      await _dao.updateSyncJob(
        job.id,
        status: syncJobFailedFinal,
        attempts: attempts,
        lastError: Value(error.toString()),
      );
      return;
    }
    final delay = _backoff[
        attempts - 1 < _backoff.length ? attempts - 1 : _backoff.length - 1];
    await _dao.updateSyncJob(
      job.id,
      status: syncJobFailedRetryable,
      attempts: attempts,
      nextRetryAt: Value(DateTime.now().toUtc().add(delay)),
      lastError: Value(error.toString()),
    );
  }
}

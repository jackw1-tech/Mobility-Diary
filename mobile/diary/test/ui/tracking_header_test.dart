import 'dart:async';

import 'package:diary/model/entities/acquisition/acquisition_domain.dart';
import 'package:diary/repositories/acquisition_repository.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit.dart';
import 'package:diary/state_management/cubits/acquisition_cubit/acquisition_cubit_state.dart';
import 'package:diary/theme/app_theme.dart';
import 'package:diary/ui/widgets/home/tracking_header.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('stopping a trip does not automatically open technical logs',
      (tester) async {
    final repository = _TrackingRepositoryWithDiagnostics();
    final cubit = AcquisitionCubit(
      trackingRepository: repository,
      syncRepository: _NoopSyncRepository(),
    );
    addTearDown(() async {
      await cubit.close();
      await repository.close();
    });
    await tester.pumpWidget(
      BlocProvider.value(
        value: cubit,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(body: TrackingHeader(state: cubit.state)),
        ),
      ),
    );

    await tester.tap(find.text('Stop'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final diagnosticsOpened =
        find.text('Log diagnostici registrazione').evaluate().isNotEmpty;
    if (diagnosticsOpened) {
      await tester.tap(find.byTooltip('Chiudi'));
      await tester.pumpAndSettle();
    }

    expect(diagnosticsOpened, isFalse);
  });

  testWidgets('disables the start button while acquisition is transitioning',
      (tester) async {
    final state = AcquisitionCubitState.fromSnapshot(
      AcquisitionSnapshot.idle(),
      isTransitioning: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(body: TrackingHeader(state: state)),
      ),
    );

    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('Avvio...'), findsOneWidget);
  });
}

class _TrackingRepositoryWithDiagnostics
    implements AcquisitionTrackingRepository {
  final _snapshots =
      StreamController<AcquisitionSnapshot>.broadcast(sync: true);
  final _snapshot = AcquisitionSnapshot(
    isTracking: true,
    trackingState: TrackingState.stationary,
    latestSigma: 0,
    latestSpeedMetersPerSecond: 0,
    lastTransition: null,
    updatedAt: DateTime.utc(2026, 9, 4, 10),
  );

  @override
  AcquisitionSnapshot get currentSnapshot => _snapshot;

  @override
  Stream<AcquisitionSnapshot> get snapshots => _snapshots.stream;

  @override
  Future<AcquisitionDiagnosticsReport?> stopTracking() async {
    const content = '{}\n';
    final timestamp = DateTime.utc(2026, 9, 4, 10);
    return AcquisitionDiagnosticsReport(
      sessionId: 'session-id',
      filePath: '/tmp/fsm.jsonl',
      fileName: 'fsm.jsonl',
      content: content,
      sizeBytes: content.length,
      decisionCount: 1,
      startedAt: timestamp,
      endedAt: timestamp.add(const Duration(minutes: 1)),
    );
  }

  @override
  Future<List<AcquisitionRoutePoint>> currentSessionRoute() async => const [];

  @override
  Future<List<List<double>>> currentSensorWindow() async => const [];

  @override
  Future<void> ingestEvent(TrackingEvent event) async {}

  @override
  Future<void> startReplay(
    int sourceTripId, {
    DateTime? scheduledStartAt,
    double replaySpeedMultiplier = 1,
  }) async {}

  @override
  Future<void> startTracking() async {}

  @override
  Future<ReplayStopResult> stopReplay() async =>
      const ReplayStopResult(tripId: null);

  @override
  void dispose() {}

  Future<void> close() => _snapshots.close();
}

class _NoopSyncRepository implements AcquisitionSyncRepository {
  @override
  AcquisitionSyncSnapshot get currentSyncSnapshot =>
      const AcquisitionSyncSnapshot.none();

  @override
  Stream<AcquisitionSyncSnapshot> get syncSnapshots => const Stream.empty();

  @override
  Future<void> resumeSync() async {}
}

import 'package:diary/features/acquisition/data/acquisition_local_database.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AcquisitionLocalDatabase', () {
    test('creates sessions and stores ordered transitions', () async {
      final database = AcquisitionLocalDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dao = database.acquisitionDao;
      final startedAt = DateTime.utc(2026, 1, 1, 8);

      await dao.createSession(
        id: 'session-1',
        deviceId: 'device-1',
        startedAt: startedAt,
      );
      await dao.insertTransition(
        sessionId: 'session-1',
        fromState: 'STATIONARY',
        toState: 'POTENTIAL_MOTION',
        reason: 'movement_sigma_above_threshold',
        timestamp: startedAt.add(const Duration(seconds: 2)),
        sigma: 0.7,
        speedMps: 0,
      );
      await dao.endSession(
        id: 'session-1',
        endedAt: startedAt.add(const Duration(minutes: 1)),
      );

      final sessions = await dao.allSessions();
      final transitions = await dao.transitionsForSession('session-1');

      expect(sessions.single.id, 'session-1');
      expect(sessions.single.endedAt, isNotNull);
      expect(transitions.single.reason, 'movement_sigma_above_threshold');
      expect(await dao.countTransitionsForSession('session-1'), 1);
    });
  });
}

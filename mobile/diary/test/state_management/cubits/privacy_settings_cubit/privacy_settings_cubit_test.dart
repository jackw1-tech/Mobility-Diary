import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePrivacySettingsService implements PrivacySettingsService {
  PrivacyLevel fetched = PrivacyLevel.precise;
  PrivacyLevel? saved;
  Object? fetchError;
  Object? saveError;
  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<PrivacyLevel> fetch() async {
    fetchCalls += 1;
    final error = fetchError;
    if (error != null) throw error;
    return fetched;
  }

  @override
  Future<PrivacyLevel> update(PrivacyLevel level) async {
    saveCalls += 1;
    final error = saveError;
    if (error != null) throw error;
    saved = level;
    return level;
  }
}

Future<void> flushCubitStream() => Future<void>.delayed(Duration.zero);

void main() {
  group('PrivacySettingsCubit', () {
    test('loads the current privacy level', () async {
      final service = FakePrivacySettingsService()
        ..fetched = PrivacyLevel.approximate;
      final cubit = PrivacySettingsCubit(service);
      final states = <PrivacySettingsState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      addTearDown(cubit.close);

      await cubit.load();
      await flushCubitStream();

      expect(service.fetchCalls, 1);
      expect(states.map((state) => state.status), [
        PrivacySettingsStatus.loading,
        PrivacySettingsStatus.ready,
      ]);
      expect(cubit.state.level, PrivacyLevel.approximate);
    });

    test('saves the selected privacy level', () async {
      final service = FakePrivacySettingsService();
      final cubit = PrivacySettingsCubit(service);
      final states = <PrivacySettingsState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      addTearDown(cubit.close);

      await cubit.save(PrivacyLevel.aggregated);
      await flushCubitStream();

      expect(service.saveCalls, 1);
      expect(service.saved, PrivacyLevel.aggregated);
      expect(states.map((state) => state.status), [
        PrivacySettingsStatus.saving,
        PrivacySettingsStatus.ready,
      ]);
      expect(states.first.level, PrivacyLevel.aggregated);
      expect(cubit.state.level, PrivacyLevel.aggregated);
    });

    test('keeps the previous level when saving fails', () async {
      final service = FakePrivacySettingsService()
        ..saveError = Exception('offline');
      final cubit = PrivacySettingsCubit(service);
      final states = <PrivacySettingsState>[];
      final subscription = cubit.stream.listen(states.add);
      addTearDown(subscription.cancel);
      addTearDown(cubit.close);

      await cubit.save(PrivacyLevel.approximate);

      expect(service.saveCalls, 1);
      expect(cubit.state.status, PrivacySettingsStatus.error);
      expect(cubit.state.level, PrivacyLevel.precise);
      expect(cubit.state.error, contains('offline'));
      expect(states.first.level, PrivacyLevel.approximate);
    });

    test('emits error when loading fails', () async {
      final service = FakePrivacySettingsService()
        ..fetchError = Exception('server');
      final cubit = PrivacySettingsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.status, PrivacySettingsStatus.error);
      expect(cubit.state.error, contains('server'));
      expect(cubit.state.level, PrivacyLevel.precise);
    });
  });
}

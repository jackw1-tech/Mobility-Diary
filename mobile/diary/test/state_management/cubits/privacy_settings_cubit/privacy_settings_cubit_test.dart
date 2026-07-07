import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/features/privacy/domain/privacy_settings.dart';
import 'package:diary/repositories/privacy_settings_repository.dart';
import 'package:diary/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit.dart';
import 'package:flutter_test/flutter_test.dart';

class FakePrivacySettingsService implements PrivacySettingsRepository {
  PrivacyLevel fetched = PrivacyLevel.precise;
  bool fetchedIsFirstLogin = false;
  PrivacyLevel? saved;
  Object? fetchError;
  Object? saveError;
  int fetchCalls = 0;
  int saveCalls = 0;

  @override
  Future<AppResult<PrivacySettings>> fetch() async {
    fetchCalls += 1;
    final error = fetchError;
    if (error != null) return AppResult.failure(toAppFailure(error));
    return AppResult.success(
      (level: fetched, isFirstLogin: fetchedIsFirstLogin),
    );
  }

  @override
  Future<AppResult<PrivacySettings>> update(PrivacyLevel level) async {
    saveCalls += 1;
    final error = saveError;
    if (error != null) return AppResult.failure(toAppFailure(error));
    saved = level;
    return AppResult.success((level: level, isFirstLogin: false));
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

    test('surfaces isFirstLogin from the backend after loading', () async {
      final service = FakePrivacySettingsService()..fetchedIsFirstLogin = true;
      final cubit = PrivacySettingsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      expect(cubit.state.isFirstLogin, isTrue);
      expect(cubit.state.needsPrivacyOnboarding, isTrue);
    });

    test('saving on first login clears the flag even with the default level',
        () async {
      final service = FakePrivacySettingsService()..fetchedIsFirstLogin = true;
      final cubit = PrivacySettingsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();
      expect(cubit.state.needsPrivacyOnboarding, isTrue);

      // User confirms the already-selected default level (precise):
      // the save must not be skipped as a no-op, otherwise the
      // onboarding flag would never clear.
      await cubit.save(PrivacyLevel.precise);

      expect(service.saveCalls, 1);
      expect(cubit.state.isFirstLogin, isFalse);
      expect(cubit.state.needsPrivacyOnboarding, isFalse);
    });

    test('does not skip saving the same level while onboarding is pending',
        () async {
      final service = FakePrivacySettingsService()
        ..fetchedIsFirstLogin = true
        ..fetched = PrivacyLevel.approximate;
      final cubit = PrivacySettingsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      await cubit.save(PrivacyLevel.approximate);

      expect(service.saveCalls, 1);
      expect(service.saved, PrivacyLevel.approximate);
    });

    test('keeps isFirstLogin unchanged when a later save fails', () async {
      final service = FakePrivacySettingsService()..fetchedIsFirstLogin = true;
      final cubit = PrivacySettingsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();

      service.saveError = Exception('offline');
      await cubit.save(PrivacyLevel.approximate);

      expect(cubit.state.status, PrivacySettingsStatus.error);
      expect(cubit.state.isFirstLogin, isTrue);
      expect(cubit.state.needsPrivacyOnboarding, isFalse);
    });

    test('skips redundant saves once onboarding is already complete', () async {
      final service = FakePrivacySettingsService()
        ..fetchedIsFirstLogin = false
        ..fetched = PrivacyLevel.approximate;
      final cubit = PrivacySettingsCubit(service);
      addTearDown(cubit.close);

      await cubit.load();
      await cubit.save(PrivacyLevel.approximate);

      expect(service.saveCalls, 0);
    });
  });
}

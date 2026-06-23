import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/features/privacy/domain/privacy_settings.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/state_management/cubits/privacy_settings_cubit/privacy_settings_cubit.dart';
import 'package:diary/ui/widgets/privacy_onboarding_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeService implements PrivacySettingsService {
  bool isFirstLogin = true;
  int saveCalls = 0;
  PrivacyLevel? savedLevel;

  @override
  Future<PrivacySettings> fetch() async =>
      (level: PrivacyLevel.precise, isFirstLogin: isFirstLogin);

  @override
  Future<PrivacySettings> update(PrivacyLevel level) async {
    saveCalls += 1;
    savedLevel = level;
    return (level: level, isFirstLogin: false);
  }
}

Future<void> _pumpHost(WidgetTester tester, PrivacySettingsCubit cubit) {
  return tester.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: cubit,
        child: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showPrivacyOnboardingDialog(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('reads the forwarded cubit, saves the default level and closes',
      (tester) async {
    final service = _FakeService();
    final cubit = PrivacySettingsCubit(service)..load();
    addTearDown(cubit.close);

    await _pumpHost(tester, cubit);
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Imposta la tua privacy'), findsOneWidget);

    // Accept the already-selected default: must still save (not a no-op during
    // onboarding) and then close the non-dismissible dialog.
    await tester.tap(find.text('Conferma'));
    await tester.pumpAndSettle();

    expect(service.saveCalls, 1);
    expect(service.savedLevel, PrivacyLevel.precise);
    expect(find.text('Imposta la tua privacy'), findsNothing);
  });
}

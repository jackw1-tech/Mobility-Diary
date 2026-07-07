import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/features/privacy/domain/privacy_settings.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/repositories/privacy_settings_repository.dart';

class PrivacySettingsRepositoryImpl implements PrivacySettingsRepository {
  final PrivacySettingsService _service;

  const PrivacySettingsRepositoryImpl({
    required PrivacySettingsService service,
  }) : _service = service;

  @override
  Future<AppResult<PrivacySettings>> fetch() =>
      appResultOf(() => _service.fetch());

  @override
  Future<AppResult<PrivacySettings>> update(PrivacyLevel level) =>
      appResultOf(() => _service.update(level));
}

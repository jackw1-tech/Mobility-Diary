import 'package:diary/features/common/domain/app_result.dart';
import 'package:diary/features/privacy/domain/privacy_level.dart';
import 'package:diary/features/privacy/domain/privacy_settings.dart';

abstract class PrivacySettingsRepository {
  Future<AppResult<PrivacySettings>> fetch();
  Future<AppResult<PrivacySettings>> update(PrivacyLevel level);
}

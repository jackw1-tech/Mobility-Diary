import 'package:diary/utils/app_result.dart';
import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:diary/model/entities/privacy/privacy_settings.dart';

abstract class PrivacySettingsRepository {
  Future<AppResult<PrivacySettings>> fetch();
  Future<AppResult<PrivacySettings>> update(PrivacyLevel level);
}

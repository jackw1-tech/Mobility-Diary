import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:diary/model/entities/privacy/privacy_settings.dart';
import 'package:diary/network/dto/privacy_settings_dto.dart';

class PrivacySettingsMapper {
  PrivacySettings mapSettings(PrivacySettingsDto dto) => (
        level: PrivacyLevel.fromWire(dto.privacyLevel),
        isFirstLogin: dto.isFirstLogin,
      );
}

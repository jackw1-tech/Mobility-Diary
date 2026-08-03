import 'package:diary/utils/app_result.dart';
import 'package:diary/mappers/privacy_settings_mapper.dart';
import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:diary/model/entities/privacy/privacy_settings.dart';
import 'package:diary/network/service/privacy_settings_service.dart';
import 'package:diary/repositories/privacy_settings_repository.dart';

class PrivacySettingsRepositoryImpl implements PrivacySettingsRepository {
  final PrivacySettingsService _service;
  final PrivacySettingsMapper _mapper;

  const PrivacySettingsRepositoryImpl({
    required PrivacySettingsService service,
    required PrivacySettingsMapper mapper,
  })  : _service = service,
        _mapper = mapper;

  @override
  Future<AppResult<PrivacySettings>> fetch() => appResultOf(
        () async => _mapper.mapSettings(await _service.fetch()),
      );

  @override
  Future<AppResult<PrivacySettings>> update(PrivacyLevel level) => appResultOf(
        () async => _mapper.mapSettings(await _service.update(level)),
      );
}

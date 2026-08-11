import 'dart:io';

import 'package:diary/network/service/trip_ingestion_service.dart';
import 'package:diary/model/entities/privacy/privacy_level.dart';
import 'package:diary/network/dto/privacy_settings_dto.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';
import 'package:diary/other/constants/api_constants.dart';

abstract class PrivacySettingsService {
  Future<PrivacySettingsDto> fetch();
  Future<PrivacySettingsDto> update(PrivacyLevel level);
}

class PrivacySettingsHttpService implements PrivacySettingsService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  PrivacySettingsHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<PrivacySettingsDto> fetch() async {
    final data = await _sendJson('GET', ApiConstants.privacySettingsPath);
    return PrivacySettingsDto.fromJson(data);
  }

  @override
  Future<PrivacySettingsDto> update(PrivacyLevel level) async {
    final data = await _sendJson(
      'PUT',
      ApiConstants.privacySettingsPath,
      body: {'privacy_level': level.wireName},
    );
    return PrivacySettingsDto.fromJson(data);
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response =
        await sendAuthenticatedJson(_client, _tokenProvider, method, path,
            body: body);
    final decoded = tryDecodeJsonMap(response.body);

    if (response.isError) {
      final detail = decoded?['detail'];
      throw IngestionApiException(
        detail is String ? detail : 'Impostazioni privacy non disponibili',
        statusCode: response.statusCode,
      );
    }
    if (decoded != null) return decoded;
    throw const IngestionApiException('Risposta privacy non valida');
  }
}

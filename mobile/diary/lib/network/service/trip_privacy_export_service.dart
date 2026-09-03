import 'dart:io';

import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/network/dto/trip_privacy_export_dto.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';

abstract class TripPrivacyExportService {
  Future<TripPrivacyExportDto> fetchExport(int tripId);
}

class TripPrivacyExportHttpService implements TripPrivacyExportService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  TripPrivacyExportHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<TripPrivacyExportDto> fetchExport(int tripId) async {
    final data = await _sendJson(
      'GET',
      '/mobility/trips/$tripId/privacy-export',
    );
    return TripPrivacyExportDto.fromJson(data);
  }

  Future<Map<String, dynamic>> _sendJson(String method, String path) async {
    final response =
        await sendAuthenticatedJson(_client, _tokenProvider, method, path);
    final decoded = tryDecodeJsonMap(response.body);

    if (response.isError) {
      final detail = decoded?['detail'];
      throw UploadApiException(
        detail is String ? detail : 'Export privacy non disponibile',
        statusCode: response.statusCode,
      );
    }
    if (decoded != null) return decoded;
    throw const UploadApiException('Risposta export privacy non valida');
  }
}

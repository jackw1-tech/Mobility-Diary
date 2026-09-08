import 'dart:io';

import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';

abstract class TripTrackService {
  Future<TripTrackDto> fetchTrack(int tripId);
  Future<TripDiaryDto> fetchDiary(int tripId);
}

class TripTrackHttpService implements TripTrackService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  TripTrackHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<TripTrackDto> fetchTrack(int tripId) async {
    final data = await _sendJson(
      'GET',
      '/mobility/trips/$tripId/track',
    );
    return TripTrackDto.fromJson(data);
  }

  @override
  Future<TripDiaryDto> fetchDiary(int tripId) async {
    final data = await _sendJson(
      'GET',
      '/mobility/trips/$tripId/diary',
    );
    return TripDiaryDto.fromJson(data);
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path,
  ) async {
    final response = await sendAuthenticatedJson(
      _client,
      _tokenProvider,
      method,
      path,
    );
    final decoded = tryDecodeJsonMap(response.body);

    if (response.isError) {
      final detail = decoded?['detail'];
      throw UploadApiException(
        detail is String ? detail : 'Richiesta traiettoria fallita',
        statusCode: response.statusCode,
      );
    }
    if (decoded != null) return decoded;
    throw const UploadApiException('Risposta traiettoria non valida');
  }
}

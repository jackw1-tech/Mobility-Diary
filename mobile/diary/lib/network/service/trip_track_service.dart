import 'dart:io';

import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';
import 'package:diary/utils/trip_detail_diagnostics.dart';

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
      tripId: tripId,
      requestName: 'track',
    );
    final stopwatch = Stopwatch()..start();
    final dto = TripTrackDto.fromJson(data);
    TripDetailDiagnostics.eventForTrip(
      tripId,
      'track_dto_parsed',
      fields: {
        'duration_ms': stopwatch.elapsedMilliseconds,
        'declared_point_count': dto.pointCount,
      },
    );
    return dto;
  }

  @override
  Future<TripDiaryDto> fetchDiary(int tripId) async {
    final data = await _sendJson(
      'GET',
      '/mobility/trips/$tripId/diary',
      tripId: tripId,
      requestName: 'diary',
    );
    final stopwatch = Stopwatch()..start();
    final dto = TripDiaryDto.fromJson(data);
    TripDetailDiagnostics.eventForTrip(
      tripId,
      'diary_dto_parsed',
      fields: {
        'duration_ms': stopwatch.elapsedMilliseconds,
        'segment_count': dto.segments.length,
        'place_count': dto.places.length,
      },
    );
    return dto;
  }

  Future<Map<String, dynamic>> _sendJson(
    String method,
    String path, {
    required int tripId,
    required String requestName,
  }) async {
    TripDetailDiagnostics.eventForTrip(
      tripId,
      '${requestName}_http_start',
    );
    final response = await sendAuthenticatedJson(
      _client,
      _tokenProvider,
      method,
      path,
      onDiagnostic: (event) {
        TripDetailDiagnostics.eventForTrip(
          tripId,
          '${requestName}_http_${event.stage}',
          fields: {
            'stage_ms': event.stageDuration.inMilliseconds,
            'http_total_ms': event.totalDuration.inMilliseconds,
            if (event.statusCode != null) 'status': event.statusCode,
            if (event.declaredContentLength != null)
              'content_length': event.declaredContentLength,
            if (event.bodyCharacters != null)
              'body_characters': event.bodyCharacters,
            if (event.errorType != null) 'error_type': event.errorType,
          },
        );
      },
    );
    final decodeWatch = Stopwatch()..start();
    final decoded = tryDecodeJsonMap(response.body);
    TripDetailDiagnostics.eventForTrip(
      tripId,
      '${requestName}_json_decode_complete',
      fields: {
        'duration_ms': decodeWatch.elapsedMilliseconds,
        'decoded_map': decoded != null,
      },
    );

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

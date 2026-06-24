import 'dart:convert';
import 'dart:io';

import 'package:diary/features/acquisition/sync/trip_ingestion_api.dart';
import 'package:diary/network/dto/trip_track_dto.dart';
import 'package:diary/other/contants/api_contants.dart';

enum DiaryEventStatus { enriched, failed, unknown }

class DiaryEvent {
  final DiaryEventStatus status;
  final int? tripId;
  final String? reasonCode;

  const DiaryEvent({
    required this.status,
    this.tripId,
    this.reasonCode,
  });

  const DiaryEvent.unknown()
      : status = DiaryEventStatus.unknown,
        tripId = null,
        reasonCode = null;

  factory DiaryEvent.fromSse({String? event, String? data}) {
    final decoded = event == 'diary_status' ? _tryDecodeMap(data) : null;
    if (decoded == null) return const DiaryEvent.unknown();
    return DiaryEvent(
      status: switch (decoded['status']) {
        'enriched' => DiaryEventStatus.enriched,
        'failed' => DiaryEventStatus.failed,
        _ => DiaryEventStatus.unknown,
      },
      tripId: _asInt(decoded['trip_id']),
      reasonCode:
          decoded['reason'] is String ? decoded['reason'] as String : null,
    );
  }
}

Map<String, dynamic>? _tryDecodeMap(String? body) {
  if (body == null || body.isEmpty) return null;
  try {
    final decoded = jsonDecode(body);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
  } on FormatException {
    return null;
  }
  return null;
}

int? _asInt(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return null;
}

Stream<DiaryEvent> parseDiaryEvents(Stream<String> lines) async* {
  String? event;
  final dataLines = <String>[];

  DiaryEvent? flush() {
    if (event == null && dataLines.isEmpty) return null;
    final parsed = DiaryEvent.fromSse(
      event: event,
      data: dataLines.join('\n'),
    );
    event = null;
    dataLines.clear();
    return parsed;
  }

  await for (final rawLine in lines) {
    final line = rawLine.trimRight();
    if (line.isEmpty) {
      final parsed = flush();
      if (parsed != null) yield parsed;
    } else if (line.startsWith(':')) {
      continue;
    } else if (line.startsWith('event:')) {
      event = line.substring('event:'.length).trimLeft();
    } else if (line.startsWith('data:')) {
      dataLines.add(line.substring('data:'.length).trimLeft());
    }
  }

  final parsed = flush();
  if (parsed != null) yield parsed;
}

abstract class TripTrackService {
  Future<TripTrackDto> fetchTrack(int tripId);
  Future<TripDiaryDto> fetchDiary(int tripId);
  Stream<DiaryEvent> watchDiaryEvents(int tripId);
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

  @override
  Stream<DiaryEvent> watchDiaryEvents(int tripId) async* {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const IngestionApiException('Sessione non disponibile');
    }

    final request = await _client.openUrl(
      'GET',
      _uri('/mobility/trips/$tripId/events'),
    );
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.contentLength = 0;

    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final responseBody = await response.transform(utf8.decoder).join();
      final detail = _tryDecodeMap(responseBody)?['detail'];
      throw IngestionApiException(
        detail is String ? detail : 'Stream eventi viaggio non disponibile',
        statusCode: response.statusCode,
      );
    }

    final lines =
        response.transform(utf8.decoder).transform(const LineSplitter());

    yield* parseDiaryEvents(lines);
  }

  Future<Map<String, dynamic>> _sendJson(String method, String path) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const IngestionApiException('Sessione non disponibile');
    }

    final request = await _client.openUrl(method, _uri(path));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.acceptHeader, 'application/json');
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    request.contentLength = 0;

    final response = await request.close().timeout(const Duration(seconds: 30));
    final responseBody = await response.transform(utf8.decoder).join();
    final decoded = _tryDecodeMap(responseBody);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final detail = decoded?['detail'];
      throw IngestionApiException(
        detail is String ? detail : 'Richiesta traiettoria fallita',
        statusCode: response.statusCode,
      );
    }
    if (decoded != null) return decoded;
    throw const IngestionApiException('Risposta traiettoria non valida');
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}

import 'dart:convert';
import 'dart:io';

import 'package:diary/features/route_assistant/domain/route_assistant_domain.dart';
import 'package:diary/other/contants/api_contants.dart';

typedef AccessTokenProvider = Future<String?> Function();

/// Classificazione live della modalita' di mobilita' via backend (solo CNN).
abstract class RouteClassifierService {
  /// Classifica una finestra 500x6. Restituisce la modalita' rilevata, oppure
  /// null quando il modello risponde "idle" (fermo).
  Future<RouteMode?> classify(List<List<double>> samples);
}

class RouteClassifierHttpService implements RouteClassifierService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  RouteClassifierHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  })  : _tokenProvider = tokenProvider,
        _client = client ?? HttpClient();

  @override
  Future<RouteMode?> classify(List<List<double>> samples) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const RouteAssistantException('Sessione non disponibile');
    }
    final request = await _client.postUrl(_uri('/mobility/route-assistant/classify'));
    request.headers.contentType = ContentType.json;
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
    final encoded = utf8.encode(jsonEncode({'samples': samples}));
    request.contentLength = encoded.length;
    request.add(encoded);

    final response = await request.close().timeout(const Duration(seconds: 30));
    final body = await response.transform(utf8.decoder).join();
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw RouteAssistantException(
        'Classificazione fallita (HTTP ${response.statusCode})',
      );
    }
    final decoded = jsonDecode(body);
    final label = decoded is Map ? decoded['label'] : null;
    return _modeFromLabel(label);
  }

  RouteMode? _modeFromLabel(dynamic label) {
    switch (label) {
      case 'walking':
        return RouteMode.walking;
      case 'cycling':
        return RouteMode.cycling;
      case 'driving':
        return RouteMode.driving;
      default:
        return null; // idle o valore inatteso
    }
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}

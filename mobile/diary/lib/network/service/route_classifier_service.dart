import 'dart:convert';
import 'dart:io';

import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/other/constants/api_constants.dart';

typedef AccessTokenProvider = Future<String?> Function();

/// Classificazione live della modalita' di mobilita' via backend (solo CNN).
///
/// Provider layer (Pine): restituisce l'etichetta grezza cosi' come arriva
/// dal backend. La conversione in [RouteMode] e' compito esclusivo di
/// [RouteAssistantMapper].
abstract class RouteClassifierService {
  /// Classifica una finestra 500x6. Restituisce l'etichetta grezza (es.
  /// `walking`/`cycling`/`driving`), oppure null quando il modello risponde
  /// "idle" (fermo) o con un valore inatteso.
  Future<String?> classify(List<List<double>> samples);
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
  Future<String?> classify(List<List<double>> samples) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const RouteAssistantException('Sessione non disponibile');
    }
    final request =
        await _client.postUrl(_uri('/mobility/route-assistant/classify'));
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
    return label is String ? label : null;
  }

  Uri _uri(String path) {
    final base = ApiConstants.baseApiUrl.endsWith('/')
        ? ApiConstants.baseApiUrl
            .substring(0, ApiConstants.baseApiUrl.length - 1)
        : ApiConstants.baseApiUrl;
    return Uri.parse('$base$path');
  }
}

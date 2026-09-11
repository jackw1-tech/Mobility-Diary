import 'dart:convert';
import 'dart:io';

import 'package:diary/model/entities/route_assistant/route_assistant_domain.dart';
import 'package:diary/network/service/impl/http_json_utils.dart';

typedef AccessTokenProvider = Future<String?> Function();

abstract class RouteClassifierService {
  Future<String?> classify(List<List<double>> samples);
}

class RouteClassifierHttpService implements RouteClassifierService {
  final AccessTokenProvider _tokenProvider;
  final HttpClient _client;

  RouteClassifierHttpService({
    required AccessTokenProvider tokenProvider,
    HttpClient? client,
  }) : _tokenProvider = tokenProvider,
       _client = client ?? HttpClient();

  @override
  Future<String?> classify(List<List<double>> samples) async {
    final token = await _tokenProvider();
    if (token == null || token.isEmpty) {
      throw const RouteAssistantException('Sessione non disponibile');
    }
    final request = await _client.postUrl(
      resolveApiUri('/mobility/route-assistant/classify'),
    );
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
}

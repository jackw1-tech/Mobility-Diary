import 'dart:convert';
import 'dart:io';

import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/other/constants/api_constants.dart';

/// Provider layer (Pine): helper puri condivisi dai vari `*HttpService` che
/// parlano con l'API REST interna via `dart:io` HttpClient. Solo I/O di
/// supporto (costruzione URL, invio richiesta autenticata, decodifica JSON
/// best-effort) — nessuna logica di business, nessuno stato.

/// Risolve [path] contro [ApiConstants.baseApiUrl], evitando il doppio slash.
Uri resolveApiUri(String path) {
  final base = ApiConstants.baseApiUrl.endsWith('/')
      ? ApiConstants.baseApiUrl.substring(0, ApiConstants.baseApiUrl.length - 1)
      : ApiConstants.baseApiUrl;
  return Uri.parse('$base$path');
}

class HttpJsonResponse {
  final int statusCode;
  final String body;

  const HttpJsonResponse(this.statusCode, this.body);

  bool get isError => statusCode < 200 || statusCode >= 300;
}

/// Apre una richiesta autenticata (bearer token) verso l'API REST interna,
/// scrive il body JSON se presente e legge la risposta come stringa.
/// Fattorizza il preambolo HTTP identico ripetuto in ogni `*HttpService`;
/// l'interpretazione di status/errori resta a carico del chiamante.
Future<HttpJsonResponse> sendAuthenticatedJson(
  HttpClient client,
  AccessTokenProvider tokenProvider,
  String method,
  String path, {
  Map<String, dynamic>? body,
  Duration timeout = const Duration(seconds: 30),
}) async {
  final token = await tokenProvider();
  if (token == null || token.isEmpty) {
    throw const UploadApiException('Sessione non disponibile');
  }

  final request = await client.openUrl(method, resolveApiUri(path));
  request.headers.contentType = ContentType.json;
  request.headers.set(HttpHeaders.acceptHeader, 'application/json');
  request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
  if (body != null) {
    final encoded = utf8.encode(jsonEncode(body));
    request.contentLength = encoded.length;
    request.add(encoded);
  } else {
    request.contentLength = 0;
  }

  final response = await request.close().timeout(timeout);
  final responseBody = await response.transform(utf8.decoder).join();
  return HttpJsonResponse(response.statusCode, responseBody);
}

/// Decodifica JSON senza lanciare: un 4xx/5xx puo' tornare testo o HTML.
/// Ritorna il valore decodificato cosi' com'e' (Map, List, ...) o null.
dynamic tryDecodeJson(String body) {
  if (body.isEmpty) return null;
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

/// Come [tryDecodeJson], ma normalizza il risultato a `Map<String, dynamic>?`.
Map<String, dynamic>? tryDecodeJsonMap(String? body) {
  if (body == null || body.isEmpty) return null;
  final decoded = tryDecodeJson(body);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return null;
}

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

class HttpJsonDiagnosticEvent {
  final String stage;
  final Duration stageDuration;
  final Duration totalDuration;
  final int? statusCode;
  final int? declaredContentLength;
  final int? bodyCharacters;
  final String? errorType;

  const HttpJsonDiagnosticEvent({
    required this.stage,
    required this.stageDuration,
    required this.totalDuration,
    this.statusCode,
    this.declaredContentLength,
    this.bodyCharacters,
    this.errorType,
  });
}

typedef HttpJsonDiagnosticCallback = void Function(
  HttpJsonDiagnosticEvent event,
);

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
  HttpJsonDiagnosticCallback? onDiagnostic,
}) async {
  final totalWatch = Stopwatch()..start();
  var stageWatch = Stopwatch()..start();

  void report(
    String stage, {
    int? statusCode,
    int? declaredContentLength,
    int? bodyCharacters,
    Object? error,
  }) {
    onDiagnostic?.call(
      HttpJsonDiagnosticEvent(
        stage: stage,
        stageDuration: stageWatch.elapsed,
        totalDuration: totalWatch.elapsed,
        statusCode: statusCode,
        declaredContentLength: declaredContentLength,
        bodyCharacters: bodyCharacters,
        errorType: error?.runtimeType.toString(),
      ),
    );
    stageWatch = Stopwatch()..start();
  }

  String? token;
  try {
    token = await tokenProvider();
    report('token_ready');
  } catch (error) {
    report('token_error', error: error);
    rethrow;
  }
  if (token == null || token.isEmpty) {
    report('token_missing');
    throw const UploadApiException('Sessione non disponibile');
  }

  HttpClientRequest request;
  try {
    request = await client.openUrl(method, resolveApiUri(path));
    report('connection_opened');
  } catch (error) {
    report('connection_error', error: error);
    rethrow;
  }
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

  report('request_configured');
  report('waiting_response_headers');
  HttpClientResponse response;
  try {
    response = await request.close().timeout(timeout);
    report(
      'response_headers_received',
      statusCode: response.statusCode,
      declaredContentLength: response.contentLength,
    );
  } catch (error) {
    report('response_headers_error', error: error);
    rethrow;
  }

  report(
    'reading_response_body',
    statusCode: response.statusCode,
    declaredContentLength: response.contentLength,
  );
  String responseBody;
  try {
    responseBody = await response.transform(utf8.decoder).join();
    report(
      'response_body_complete',
      statusCode: response.statusCode,
      declaredContentLength: response.contentLength,
      bodyCharacters: responseBody.length,
    );
  } catch (error) {
    report(
      'response_body_error',
      statusCode: response.statusCode,
      declaredContentLength: response.contentLength,
      error: error,
    );
    rethrow;
  }
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

import 'dart:convert';
import 'dart:io';

import 'package:diary/network/service/trip_upload_service.dart';
import 'package:diary/other/constants/api_constants.dart';

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

dynamic tryDecodeJson(String body) {
  if (body.isEmpty) return null;
  try {
    return jsonDecode(body);
  } on FormatException {
    return null;
  }
}

Map<String, dynamic>? tryDecodeJsonMap(String? body) {
  if (body == null || body.isEmpty) return null;
  final decoded = tryDecodeJson(body);
  if (decoded is Map<String, dynamic>) return decoded;
  if (decoded is Map) return Map<String, dynamic>.from(decoded);
  return null;
}

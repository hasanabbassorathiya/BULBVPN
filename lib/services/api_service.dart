import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';

enum HttpMethod { get, post, put, delete, patch }

class ApiService {
  String? _authToken;
  final http.Client _client;

  ApiService({http.Client? client}) : _client = client ?? http.Client();

  void setAuthToken(String? token) {
    _authToken = token;
  }

  Map<String, String> get _headers {
    final headers = Map<String, String>.from(AppConfig.defaultHeaders);
    if (_authToken != null) {
      headers['Authorization'] = 'Bearer $_authToken';
    }
    return headers;
  }

  Future<Map<String, dynamic>> request(
    String endpoint, {
    HttpMethod method = HttpMethod.get,
    Map<String, dynamic>? body,
    Map<String, String>? queryParams,
  }) async {
    try {
      final uri = _buildUri(endpoint, queryParams);
      final request = _buildRequest(method, uri, body);

      final response = await _client
          .send(request)
          .timeout(AppConfig.apiTimeout);

      final responseBody = await response.stream.bytesToString();
      final data = json.decode(responseBody) as Map<String, dynamic>;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return data;
      } else {
        throw ApiException(
          statusCode: response.statusCode,
          message: data['error']?['message'] ?? data['message'] ?? 'Unknown error',
          code: data['error']?['code'],
        );
      }
    } on ApiException {
      rethrow;
    } catch (e) {
      throw ApiException(
        statusCode: 0,
        message: 'Network error: ${e.toString()}',
      );
    }
  }

  Uri _buildUri(String endpoint, Map<String, String>? queryParams) {
    final base = '${AppConfig.apiBaseUrl}$endpoint';
    if (queryParams != null && queryParams.isNotEmpty) {
      return Uri.parse(base).replace(queryParameters: queryParams);
    }
    return Uri.parse(base);
  }

  http.Request _buildRequest(HttpMethod method, Uri uri, Map<String, dynamic>? body) {
    final request = http.Request(method.name.toUpperCase(), uri);
    request.headers.addAll(_headers);
    if (body != null) {
      request.body = json.encode(body);
    }
    return request;
  }

  Future<Map<String, dynamic>> get(String endpoint, {Map<String, String>? queryParams}) {
    return request(endpoint, method: HttpMethod.get, queryParams: queryParams);
  }

  Future<Map<String, dynamic>> post(String endpoint, {Map<String, dynamic>? body}) {
    return request(endpoint, method: HttpMethod.post, body: body);
  }

  Future<Map<String, dynamic>> put(String endpoint, {Map<String, dynamic>? body}) {
    return request(endpoint, method: HttpMethod.put, body: body);
  }

  Future<Map<String, dynamic>> delete(String endpoint) {
    return request(endpoint, method: HttpMethod.delete);
  }

  void dispose() {
    _client.close();
  }
}

class ApiException implements Exception {
  final int statusCode;
  final String message;
  final String? code;

  ApiException({required this.statusCode, required this.message, this.code});

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isRateLimited => statusCode == 429;
  bool get isServerError => statusCode >= 500;
  bool get isNetworkError => statusCode == 0;

  @override
  String toString() => 'ApiException($statusCode): $message';
}

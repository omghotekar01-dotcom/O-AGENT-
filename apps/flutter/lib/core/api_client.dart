import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

/// The development API uses a bearer token. Never write it into logs,
/// shared preferences, Android resources, or iOS bundles.
class AgentApi {
  AgentApi(String endpoint, String token, {HttpClient? httpClient})
      : endpoint = validateEndpoint(endpoint),
        _token = token,
        _http = httpClient ?? HttpClient() {
    if (token.trim().length < 24) {
      throw const ApiException('Operator token must contain at least 24 characters');
    }
    _http.connectionTimeout = const Duration(seconds: 10);
  }

  final Uri endpoint;
  final String _token;
  final HttpClient _http;

  static Uri validateEndpoint(String raw) {
    final uri = Uri.tryParse(raw.trim());
    if (uri == null || !uri.hasAuthority || uri.host.isEmpty || uri.userInfo.isNotEmpty) {
      throw const ApiException('Enter a valid backend URL, e.g. https://your-server.example');
    }
    if (uri.hasQuery || uri.hasFragment || (uri.path.isNotEmpty && uri.path != '/')) {
      throw const ApiException('Enter the backend origin without a path or query');
    }
    final local = const {'localhost', '127.0.0.1', '10.0.2.2'}.contains(uri.host);
    final debug = !const bool.fromEnvironment('dart.vm.product');
    if (uri.scheme != 'https' && !(debug && local && uri.scheme == 'http')) {
      throw const ApiException('HTTPS is required outside local debug testing');
    }
    return uri;
  }

  void close() => _http.close(force: true);

  Future<Map<String, dynamic>> _request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async {
    try {
      final timeout = path == "/api/ai/chat" ? const Duration(seconds: 85) : const Duration(seconds: 15);
      final url = endpoint.resolve(path);
      final request = await _http.openUrl(method, url).timeout(timeout);
      request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      if (idempotencyKey != null) request.headers.set('Idempotency-Key', idempotencyKey);
      if (body != null) {
        request.headers.contentType = ContentType.json;
        request.write(jsonEncode(body));
      }
      final response = await request.close().timeout(timeout);
      final text = await utf8.decoder.bind(response).join().timeout(timeout);
      Map<String, dynamic> data;
      try {
        data = Map<String, dynamic>.from(jsonDecode(text) as Map);
      } catch (_) {
        throw ApiException('Unexpected response from backend', response.statusCode);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(data['error']?.toString() ?? 'HTTP ${response.statusCode}', response.statusCode);
      }
      return data;
    } on SocketException {
      throw const ApiException('Cannot reach the server. Check the network and backend address.');
    } on HandshakeException {
      throw const ApiException('TLS certificate verification failed. Use a trusted HTTPS certificate.');
    } on HttpException catch (e) {
      throw ApiException('Network request failed: ${e.message}');
    }
  }

  /// AI provider key stays on server; mobile only uses its operator token.
  Future<Map<String, dynamic>> aiStatus() => _request('/api/ai/status');
  Future<List<Map<String, dynamic>>> aiThreads() async {
    final data = await _request('/api/ai/threads');
    final raw = data['threads'];
    if (raw is! List) throw const ApiException('Invalid conversation list');
    return raw.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> aiThread(String id) =>
      _request('/api/ai/threads/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> aiChat({
    required String agentId,
    required String message,
    String? threadId,
  }) => _request('/api/ai/chat', method: 'POST', body: {
        'agentId': agentId,
        'message': message,
        if (threadId != null) 'threadId': threadId,
      });

  Future<ControlSnapshot> readState() async => ControlSnapshot.fromJson(await _request('/api/state'));

  Future<List<DomainEvent>> readEvents({int after = 0}) async {
    final data = await _request('/api/events?after=$after');
    final raw = data['events'];
    if (raw is! List) throw const ApiException('Invalid event response');
    return raw.map((e) => DomainEvent.fromJson(Map<String, dynamic>.from(e as Map))).toList(growable: false);
  }

  Future<void> submitTask({required String workerId, required String kind}) async {
    await _request('/api/tasks',
        method: 'POST',
        body: {'workerId': workerId, 'kind': kind},
        idempotencyKey: createIdempotencyKey());
  }

  Future<void> decide(String taskId, {required bool approve}) async {
    await _request('/api/tasks/${Uri.encodeComponent(taskId)}/decision',
        method: 'POST', body: {'approve': approve});
  }

  Future<void> cancel(String taskId) async {
    await _request('/api/tasks/${Uri.encodeComponent(taskId)}/cancel', method: 'POST');
  }

  static String createIdempotencyKey() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    return bytes.map((v) => v.toRadixString(16).padLeft(2, '0')).join();
  }
}

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
      final timeout = path == "/api/ai/chat" || path == "/api/ai/refine" || path.endsWith("/messages") ? const Duration(seconds: 85) : const Duration(seconds: 15);
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

  /// Public endpoints never send a bearer token or AI provider secret.
  static Future<Map<String, dynamic>> publicAccountRequest({
    required String backend,
    required String path,
    required Map<String, dynamic> body,
  }) async {
    final origin = validateEndpoint(backend);
    if (!const {'/api/auth/register', '/api/auth/verify', '/api/auth/login',
      '/api/auth/forgot', '/api/auth/reset', '/api/auth/resend'}.contains(path)) {
      throw const ApiException('Unsupported account action');
    }
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await http.postUrl(origin.resolve(path))
        .timeout(const Duration(seconds: 20));
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
      final response = await request.close().timeout(const Duration(seconds: 20));
      final payload = await utf8.decoder.bind(response).join().timeout(const Duration(seconds: 20));
      final data = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw ApiException(data['error']?.toString() ?? 'Account action failed',
          response.statusCode);
      }
      return data;
    } on SocketException {
      throw const ApiException('Cannot reach the backend. Check the network and HTTPS address.');
    } on HandshakeException {
      throw const ApiException('Backend HTTPS certificate is not trusted.');
    } finally {
      http.close(force: true);
    }
  }

  Future<void> logoutPersonalSession() async {
    await _request('/api/auth/logout', method: 'POST');
  }

  Future<Map<String, dynamic>> accountInfo() => _request('/api/me');

  /// Owner-only: one-use invitation; never display operator tokens to members.
  Future<Map<String, dynamic>> createInvitation(String label) =>
      _request('/api/accounts/invitations', method: 'POST', body: {'label': label});

  Future<List<Map<String, dynamic>>> members() async {
    final response = await _request('/api/accounts/members');
    return (response['members'] as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  Future<void> revokeMember(String id) async {
    await _request('/api/accounts/members/${Uri.encodeComponent(id)}', method: 'DELETE');
  }

  Future<Map<String, dynamic>> githubStatus() => _request('/api/account/github');

  Future<Map<String, dynamic>> connectGithub(String personalAccessToken) =>
    _request('/api/account/github', method: 'PUT',
      body: {'token': personalAccessToken});

  Future<void> disconnectGithub() async {
    await _request('/api/account/github', method: 'DELETE');
  }

  Future<List<Map<String, dynamic>>> githubRepos() async {
    final result = await _request('/api/account/github/repos');
    return (result['repos'] as List? ?? [])
      .map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> githubReadmeStatus() => _request('/api/account/github');

  Future<List<Map<String, dynamic>>> accountAttachments() async {
    final data = await _request('/api/account/attachments');
    return (data['attachments'] as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  Future<Map<String, dynamic>> uploadAccountAttachment({
    required String name, required String mimeType, required String base64,
  }) => _request('/api/account/attachments', method: 'POST', body: {
    'name': name, 'mimeType': mimeType, 'base64': base64,
  });

  Future<void> deleteAccountAttachment(String id) async {
    await _request('/api/account/attachments/' + Uri.encodeComponent(id),
      method: 'DELETE');
  }

  Future<Map<String, dynamic>> accountConnections() =>
      _request('/api/account/connections');

  Future<Map<String, dynamic>> setAccountConnection({
    required String provider,
    required String model,
    String? apiKey,
  }) => _request('/api/account/connections/${Uri.encodeComponent(provider)}',
      method: 'PUT', body: {
        'model': model,
        if (apiKey != null && apiKey.isNotEmpty) 'apiKey': apiKey,
      });

  Future<Map<String, dynamic>> verifyAccountConnection(String provider) =>
      _request('/api/account/connections/${Uri.encodeComponent(provider)}/verify',
        method: 'POST');

  Future<Map<String, dynamic>> deleteAccountConnection(String provider) =>
      _request('/api/account/connections/${Uri.encodeComponent(provider)}',
        method: 'DELETE');

  Future<List<Map<String, dynamic>>> accountThreads() async {
    final response = await _request('/api/account/threads');
    return (response['threads'] as List? ?? [])
      .map((x) => Map<String, dynamic>.from(x as Map)).toList();
  }

  Future<Map<String, dynamic>> accountThread(String id) =>
      _request('/api/account/threads/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> accountChat({
    required String provider,
    required String message,
    String? threadId,
    List<String> attachmentIds = const [],
    String? githubRepository,
  }) => _request('/api/account/chat', method: 'POST', body: {
    'provider': provider, 'agentId': 'navigator', 'message': message,
    if (threadId != null) 'threadId': threadId,
    if (attachmentIds.isNotEmpty) 'attachmentIds': attachmentIds,
    if (githubRepository != null) 'githubRepository': githubRepository,
  });

  /// Public pairing route; only works with a one-time owner-issued invitation.
  /// The claimed credential is saved by the controller in platform secure storage.
  static Future<String> claimInvitation({
    required String backend,
    required String invitationCode,
    required String displayName,
  }) async {
    final origin = validateEndpoint(backend);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final req = await client.postUrl(origin.resolve('/api/accounts/claim'))
        .timeout(const Duration(seconds: 15));
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode({
        'invitationCode': invitationCode.trim(), 'displayName': displayName.trim(),
      }));
      final response = await req.close().timeout(const Duration(seconds: 15));
      final data = jsonDecode(await utf8.decoder.bind(response).join()) as Map;
      if (response.statusCode != 201) {
        throw ApiException(data['error']?.toString() ?? 'Invitation rejected', response.statusCode);
      }
      final token = data['token'];
      if (token is! String || token.length < 40) {
        throw const ApiException('Server returned an invalid member session');
      }
      return token;
    } on SocketException {
      throw const ApiException('Cannot reach the backend. Check Tailscale and HTTPS URL.');
    } finally {
      client.close(force: true);
    }
  }

  /// Only returns a proposed prompt. Never dispatches a task or uses tools.
  Future<String> refinePrompt(String message, {String target = 'generic'}) async {
    final result = await _request('/api/ai/refine', method: 'POST', body: {
      'message': message, 'target': target,
    });
    final proposed = result['proposed'];
    if (proposed is! String || proposed.isEmpty) {
      throw const ApiException('AI returned no proposed prompt');
    }
    return proposed;
  }

  /// Submit a turn to the exact saved Codex CLI session. The server requires
  /// explicit initial approval and enforces per-action approvals during runs.
  Future<Map<String, dynamic>> requestCodexLocalTurn({
    required String projectId,
    required String sessionId,
    required String prompt,
    required String mode,
  }) => _request('/api/providers/codex/local/turns', method: 'POST', body: {
    'projectId': projectId,
    'sessionId': sessionId,
    'prompt': prompt,
    'mode': mode,
  }, idempotencyKey: createIdempotencyKey());

  Future<Map<String, dynamic>> taskDetail(String id) =>
      _request('/api/tasks/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> decideCodexAction({
    required String taskId,
    required String approvalId,
    required bool approve,
  }) => _request(
    '/api/tasks/${Uri.encodeComponent(taskId)}/approvals/${Uri.encodeComponent(approvalId)}/decision',
    method: 'POST', body: {'approve': approve});

  /// Requests a NEW Codex Cloud task via a connected laptop CLI.
  /// The backend must require a separate human approval before execution.
  Future<void> requestCodexTask({
    required String workerId,
    required String environmentId,
    required String prompt,
  }) async {
    await _request('/api/providers/codex/tasks', method: 'POST', body: {
      'workerId': workerId,
      'environmentId': environmentId,
      'prompt': prompt,
    }, idempotencyKey: createIdempotencyKey());
  }

  /// Unified project feed: real GitHub/Codex metadata and locally owned projects.
  Future<Map<String, dynamic>> projects() => _request('/api/projects');

  Future<Map<String, dynamic>> project(String id) =>
      _request('/api/projects/${Uri.encodeComponent(id)}');

  Future<Map<String, dynamic>> createProject(String title, String description) =>
      _request('/api/projects', method: 'POST', body: {
        'title': title, 'description': description,
      });

  /// Only O-AGENT-owned projects support this endpoint. Other providers
  /// expose read-only capabilities unless a documented write adapter exists.
  Future<Map<String, dynamic>> promptProject(String id, String message,
      {String agentId = 'navigator'}) =>
      _request('/api/projects/${Uri.encodeComponent(id)}/messages',
        method: 'POST', body: {'agentId': agentId, 'message': message});

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

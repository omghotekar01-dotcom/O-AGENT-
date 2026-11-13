import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

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
      final timeout = path == "/api/ai/chat" || path == "/api/account/chat" || path.endsWith("/verify") || path == "/api/ai/refine" || path.endsWith("/messages") ? const Duration(seconds: 85) : const Duration(seconds: 15);
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

  /// Authenticated server-sent event stream for the OWNER. Events carry
  /// state-change notifications, not fake agent output. Always refetch task
  /// detail from the server after a notification, never trust event text as
  /// authorization to execute an action.
  Stream<Map<String, dynamic>> ownerEventStream() async* {
    final request = await _http.getUrl(endpoint.resolve('/api/stream'))
      .timeout(const Duration(seconds: 15));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    final response = await request.close().timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) {
      throw ApiException('Remote event stream unavailable',
        response.statusCode);
    }
    await for (final line in utf8.decoder.bind(response).transform(const LineSplitter())) {
      if (!line.startsWith('data: ')) continue;
      try {
        final parsed = jsonDecode(line.substring(6));
        if (parsed is Map) yield Map<String, dynamic>.from(parsed);
      } catch (_) {
        // Ignore an invalid server event; the periodic refresh is authoritative.
      }
    }
  }

  /// View-only screen frames captured on the user's laptop with the native
  /// browser display picker. No remote keyboard/mouse control is supported.
  Future<Map<String, dynamic>> screenStatus() => _request('/api/screen/status');

  Future<Map<String, dynamic>> stopScreenShare() =>
    _request('/api/screen/stop', method: 'POST');

  Future<Uint8List?> screenFrame() async {
    final request = await _http.getUrl(endpoint.resolve('/api/screen/frame'))
      .timeout(const Duration(seconds: 10));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    request.headers.set(HttpHeaders.acceptHeader, 'image/jpeg');
    final response = await request.close().timeout(const Duration(seconds: 10));
    if (response.statusCode == 404) {
      await response.drain<void>();
      return null;
    }
    if (response.statusCode != 200 ||
        response.headers.contentType?.mimeType != 'image/jpeg') {
      await response.drain<void>();
      throw ApiException('Screen preview not available', response.statusCode);
    }
    final chunks = BytesBuilder(copy: false);
    await for (final bytes in response) {
      chunks.add(bytes);
      if (chunks.length > 160000) {
        throw const ApiException('Invalid oversized screen frame');
      }
    }
    return chunks.takeBytes();
  }

  /// Owner-only remote session, run and approval status.
  Future<Map<String, dynamic>> remoteAgentOverview() => _request('/api/remote/overview');

  // Cursor Cloud Agents v1 is scoped to the signed-in personal account.
  Future<Map<String, dynamic>> cursorStatus() => _request('/api/account/cursor');

  Future<Map<String, dynamic>> connectCursor(String apiKey) =>
    _request('/api/account/cursor', method: 'PUT', body: {'apiKey': apiKey});

  Future<Map<String, dynamic>> verifyCursor() =>
    _request('/api/account/cursor/verify', method: 'POST');

  Future<Map<String, dynamic>> disconnectCursor() =>
    _request('/api/account/cursor', method: 'DELETE');

  Future<List<Map<String, dynamic>>> cursorAgents() async {
    final response = await _request('/api/account/cursor/agents');
    return (response['agents'] as List? ?? []).map(
      (item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  /// Start a real provider-hosted coding agent. The caller has separately
  /// reviewed the repo/branch, prompt and provider billing implications.
  Future<Map<String, dynamic>> createCursorAgent({
    required String prompt,
    required String repoUrl,
    String? startingRef,
    String mode = 'plan',
    bool autoCreatePR = false,
    String? requestId,
  }) {
    final random = Random.secure();
    final nonce = List<int>.generate(24, (_) => random.nextInt(256));
    return _request('/api/account/cursor/agents', method: 'POST', body: {
      'requestId': requestId ?? base64UrlEncode(nonce),
      'prompt': prompt, 'repoUrl': repoUrl,
      'mode': mode, 'autoCreatePR': autoCreatePR,
      if (startingRef != null && startingRef.isNotEmpty) 'startingRef': startingRef,
    });
  }

  Future<Map<String, dynamic>> cursorAgent(String id) =>
    _request('/api/account/cursor/agents/' + Uri.encodeComponent(id));

  Future<List<Map<String, dynamic>>> cursorArtifacts(String agentId) async {
    final response = await _request('/api/account/cursor/agents/' +
      Uri.encodeComponent(agentId) + '/artifacts');
    return (response['artifacts'] as List? ?? [])
      .map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> cursorArtifactLink(
      String agentId, String artifactPath) =>
    _request('/api/account/cursor/agents/' + Uri.encodeComponent(agentId) +
      '/artifacts/download?path=' + Uri.encodeQueryComponent(artifactPath));

  Future<List<Map<String, dynamic>>> cursorRuns(String id) async {
    final response = await _request(
      '/api/account/cursor/agents/' + Uri.encodeComponent(id) + '/runs');
    return (response['runs'] as List? ?? []).map(
      (item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<Map<String, dynamic>> cursorRun(String agentId, String runId) =>
    _request('/api/account/cursor/agents/' + Uri.encodeComponent(agentId) +
      '/runs/' + Uri.encodeComponent(runId));

  Future<Map<String, dynamic>> cursorFollowUp({
    required String agentId,
    required String prompt,
    bool steer = false,
    String? requestId,
  }) {
    final random = Random.secure();
    final nonce = List<int>.generate(24, (_) => random.nextInt(256));
    return _request('/api/account/cursor/agents/' + Uri.encodeComponent(agentId) + '/runs',
      method: 'POST',
      body: {'prompt': prompt, 'requestId': requestId ?? base64UrlEncode(nonce),
        if (steer) 'delivery': 'steer'});
  }

  /// The private backend forwards only verified Cursor assistant/status/tool
  /// summaries. The event ID allows reconnect without replaying every delta.
  Stream<Map<String, dynamic>> cursorRunEvents(String agentId, String runId,
      {String? lastEventId}) async* {
    final path = '/api/account/cursor/agents/' + Uri.encodeComponent(agentId) +
      '/runs/' + Uri.encodeComponent(runId) + '/stream';
    final request = await _http.getUrl(endpoint.resolve(path))
      .timeout(const Duration(seconds: 20));
    request.headers.set(HttpHeaders.authorizationHeader, 'Bearer $_token');
    request.headers.set(HttpHeaders.acceptHeader, 'text/event-stream');
    if (lastEventId != null && lastEventId.isNotEmpty) {
      request.headers.set('Last-Event-ID', lastEventId);
    }
    final response = await request.close().timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw ApiException('Cursor live stream unavailable', response.statusCode);
    }
    var name = 'message';
    String? cursor;
    final data = <String>[];
    await for (final line in utf8.decoder.bind(response).transform(const LineSplitter())) {
      if (line.isEmpty) {
        if (data.isNotEmpty) {
          try {
            final raw = jsonDecode(data.join('\n'));
            if (raw is Map) {
              yield <String, dynamic>{
                'event': name, 'id': cursor, ...Map<String, dynamic>.from(raw),
              };
            }
          } catch (_) { /* Invalid event; keep the real-state fallback. */ }
        }
        name = 'message'; cursor = null; data.clear();
      } else if (line.startsWith('event:')) {
        name = line.substring(6).trim();
      } else if (line.startsWith('id:')) {
        cursor = line.substring(3).trim();
      } else if (line.startsWith('data:')) {
        if (data.join('').length < 20000) data.add(line.substring(5).trimLeft());
      }
    }
  }

  Future<Map<String, dynamic>> cursorCancel(String agentId, String runId) =>
    _request('/api/account/cursor/agents/' + Uri.encodeComponent(agentId) +
      '/runs/' + Uri.encodeComponent(runId) + '/cancel', method: 'POST');

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

  Future<Map<String, dynamic>> createSupervisedAgentTurn({
    required String workerId, required String providerKind,
    required String cwd, required String prompt,
    required String mode, String? sessionId,
  }) {
    if (!const {'claude_agent_turn', 'copilot_sdk_turn'}.contains(providerKind)) {
      throw const ApiException('Unknown agent bridge capability');
    }
    final random = Random.secure();
    final key = base64UrlEncode(List<int>.generate(24, (_) => random.nextInt(256)));
    return _request('/api/tasks', method: 'POST', idempotencyKey: key, body: {
      'workerId': workerId, 'kind': providerKind, 'cwd': cwd,
      'prompt': prompt, 'mode': mode,
      if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId,
    });
  }

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

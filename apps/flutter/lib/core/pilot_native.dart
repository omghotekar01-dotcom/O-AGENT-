import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/widgets.dart';
import 'package:flutter_appauth/flutter_appauth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const nativeClientId = 'oagent-mobile';
const nativeRedirectUri = 'com.omiiii.oagent:/oauth2redirect';

class PilotFailure implements Exception {
  const PilotFailure(this.message, [this.statusCode]);
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

Uri? privatePilotOrigin(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty ||
      uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.host == 'localhost' || uri.host == '127.0.0.1') return null;
  return Uri(scheme: 'https', host: uri.host,
      port: uri.hasPort ? uri.port : null, path: '/');
}

Map<String, dynamic> validatedPilotAuthConfig(
    Uri origin, Map<String, dynamic> data) {
  if (data['authEnabled'] != true || data['audience'] != 'oagent-api') {
    throw const PilotFailure('This server does not support O-AGENT native login.');
  }
  for (final key in ['authorizationEndpoint', 'tokenEndpoint']) {
    final value = Uri.tryParse(data[key]?.toString() ?? '');
    if (value == null || value.scheme != 'https' ||
        value.origin != origin.origin || value.userInfo.isNotEmpty ||
        value.hasFragment || value.hasQuery ||
        !value.path.startsWith('/auth/realms/oagent/protocol/openid-connect/')) {
      throw const PilotFailure('Identity endpoints differ from the private server address.');
    }
  }
  return data;
}

class PilotTokens {
  const PilotTokens({required this.accessToken,
    required this.expiresAt, this.refreshToken});
  final String accessToken;
  final String? refreshToken;
  final DateTime expiresAt;
}

abstract class PilotAuthenticator {
  Future<PilotTokens> signIn(Uri origin, Map<String, dynamic> config);
  Future<PilotTokens> renew(Uri origin, Map<String, dynamic> config, String refresh);
}

class AppAuthPilotAuthenticator implements PilotAuthenticator {
  AppAuthPilotAuthenticator([FlutterAppAuth? instance])
    : _appAuth = instance ?? const FlutterAppAuth();
  final FlutterAppAuth _appAuth;
  AuthorizationServiceConfiguration _service(Map<String, dynamic> config) =>
    AuthorizationServiceConfiguration(
      authorizationEndpoint: config['authorizationEndpoint'] as String,
      tokenEndpoint: config['tokenEndpoint'] as String);
  @override
  Future<PilotTokens> signIn(Uri origin, Map<String, dynamic> config) async {
    final answer = await _appAuth.authorizeAndExchangeCode(
      AuthorizationTokenRequest(nativeClientId, nativeRedirectUri,
        serviceConfiguration: _service(config),
        scopes: const ['openid', 'oagent-read', 'oagent-operate']));
    if (answer.accessToken == null || answer.accessToken!.isEmpty) {
      throw const PilotFailure('Secure sign-in returned no access token.');
    }
    return PilotTokens(accessToken: answer.accessToken!,
      refreshToken: answer.refreshToken,
      expiresAt: answer.accessTokenExpirationDateTime ??
        DateTime.now().add(const Duration(minutes: 5)));
  }
  @override
  Future<PilotTokens> renew(Uri origin, Map<String, dynamic> config, String refresh) async {
    final answer = await _appAuth.token(TokenRequest(nativeClientId,
      nativeRedirectUri, refreshToken: refresh,
      serviceConfiguration: _service(config)));
    if (answer.accessToken == null || answer.accessToken!.isEmpty) {
      throw const PilotFailure('Secure session expired; sign in again.');
    }
    return PilotTokens(accessToken: answer.accessToken!,
      refreshToken: answer.refreshToken ?? refresh,
      expiresAt: answer.accessTokenExpirationDateTime ??
        DateTime.now().add(const Duration(minutes: 5)));
  }
}

class StoredPilotSession {
  const StoredPilotSession(this.origin, this.refreshToken);
  final String origin, refreshToken;
}

abstract class PilotSessionStore {
  Future<StoredPilotSession?> read();
  Future<void> write(StoredPilotSession session);
  Future<void> clear();
}

class SecurePilotSessionStore implements PilotSessionStore {
  const SecurePilotSessionStore();
  static const _secure = FlutterSecureStorage();
  static const _key = 'oagent.native.pkce.session.v1';
  @override
  Future<StoredPilotSession?> read() async {
    final data = await _secure.read(key: _key);
    if (data == null) return null;
    final json = jsonDecode(data);
    if (json is! Map || json['origin'] is! String ||
        json['refreshToken'] is! String) return null;
    return StoredPilotSession(json['origin'] as String,
      json['refreshToken'] as String);
  }
  @override
  Future<void> write(StoredPilotSession session) => _secure.write(key: _key,
    value: jsonEncode({'origin': session.origin,
      'refreshToken': session.refreshToken}));
  @override
  Future<void> clear() => _secure.delete(key: _key);
}

typedef PilotRequest = Future<Map<String, dynamic>> Function(
  Uri url, String method, Map<String, dynamic>? body,
  String? bearer, Map<String, String> headers);

Future<Map<String, dynamic>> securePilotRequest(Uri url, String method,
  Map<String, dynamic>? body, String? bearer,
  Map<String, String> headers) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 12);
  try {
    final req = await client.openUrl(method, url).timeout(const Duration(seconds: 15));
    req.followRedirects = false;
    req.headers.set(HttpHeaders.acceptHeader, 'application/json');
    req.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
    if (bearer != null) {
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer ' + bearer);
    }
    for (final pair in headers.entries) {
      req.headers.set(pair.key, pair.value);
    }
    if (body != null) {
      req.headers.contentType = ContentType.json;
      req.write(jsonEncode(body));
    }
    final response = await req.close().timeout(const Duration(seconds: 20));
    final raw = await utf8.decoder.bind(response).join();
    Map<String, dynamic> decoded;
    try {
      decoded = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {
      throw const PilotFailure('Backend did not return valid JSON.');
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw PilotFailure(decoded['error']?.toString() ??
        'Request rejected by backend (HTTP ' + response.statusCode.toString() + ')',
        response.statusCode);
    }
    return decoded;
  } on SocketException {
    throw const PilotFailure('Laptop unreachable. Check Tailscale, Docker and worker connectivity.');
  } on HandshakeException {
    throw const PilotFailure('Private HTTPS certificate could not be verified.');
  } on TimeoutException {
    throw const PilotFailure('The backend did not respond. Keep your laptop on and awake.');
  } finally {
    client.close(force: true);
  }
}
List<Map<String, dynamic>> _items(Map<String, dynamic> data, String key) {
  final raw = data[key];
  if (raw is! List) throw PilotFailure('Missing response field: ' + key);
  return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
}
bool pilotDeviceOnline(Map<String, dynamic> d, [DateTime? now]) {
  if (d['revoked_at'] != null) return false;
  final seen = DateTime.tryParse(d['last_seen_at']?.toString() ?? '');
  final current = now ?? DateTime.now();
  return seen != null && current.difference(seen).inSeconds < 120 &&
    !seen.isAfter(current.add(const Duration(seconds: 10)));
}
String pilotPairingToken(String input, Uri server) {
  final raw = input.trim();
  final uri = Uri.tryParse(raw);
  final isLink = uri != null && uri.scheme == 'https';
  if (isLink && (uri.origin != server.origin ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery || !uri.fragment.startsWith('pair='))) {
    throw const PilotFailure('Pairing link belongs to another server.');
  }
  final token = isLink ? Uri.decodeComponent(uri.fragment.substring(5)) : raw;
  if (!RegExp(r'^oen_[A-Za-z0-9_-]{43}$').hasMatch(token)) {
    throw const PilotFailure('Invalid or expired-looking pairing link.');
  }
  return token;
}

String pilotCapabilityLabel(String kind) => switch (kind) {
  'workspace_inventory' => 'Workspace inventory',
  'codex_cli_turn' => 'Codex CLI session',
  'claude_agent_turn' => 'Claude Agent SDK',
  'copilot_sdk_turn' => 'GitHub Copilot SDK',
  _ => kind,
};

class NativePilotController extends ChangeNotifier with WidgetsBindingObserver {
  NativePilotController({PilotRequest? request, PilotAuthenticator? auth,
    PilotSessionStore? store})
    : _request = request ?? securePilotRequest,
      _auth = auth ?? AppAuthPilotAuthenticator(),
      _store = store ?? const SecurePilotSessionStore() {
    WidgetsBinding.instance.addObserver(this);
  }
  final PilotRequest _request;
  final PilotAuthenticator _auth;
  final PilotSessionStore _store;
  Timer? _timer;
  Uri? origin;
  Map<String, dynamic>? _config;
  PilotTokens? _tokens;
  String? error, selectedWorkspace;
  Map<String, dynamic> me = {};
  List<Map<String, dynamic>> devices = [], runs = [], approvals = [];
  bool busy = false, syncing = false;
  bool get connected => origin != null && _tokens != null && me.isNotEmpty;
  int get onlineDevices => devices.where(pilotDeviceOnline).length;
  int get activeRuns => runs.where((r) =>
    ['queued', 'running', 'waiting_for_approval',
      'waiting_for_tool', 'needs_recovery'].contains(r['status'])).length;

  Future<Map<String, dynamic>> _readConfig(Uri target) async =>
    validatedPilotAuthConfig(target, await _request(
      target.resolve('/v1/public-config'), 'GET', null, null, const {}));

  Future<void> signIn(String address, {bool rememberDevice = false}) async {
    if (busy) return;
    final target = privatePilotOrigin(address);
    if (target == null) {
      error = 'Enter your exact private HTTPS O-AGENT address.';
      notifyListeners(); return;
    }
    busy = true; error = null; notifyListeners();
    try {
      final cfg = await _readConfig(target);
      final tokens = await _auth.signIn(target, cfg);
      origin = target; _config = cfg; _tokens = tokens;
      me = await _api('/v1/me');
      if (rememberDevice && tokens.refreshToken != null) {
        await _store.write(StoredPilotSession(target.origin, tokens.refreshToken!));
      } else {
        await _store.clear();
      }
      _startPolling();
      await refresh();
    } catch (e) {
      error = pilotFriendlyError(e); _tokens = null; me = {};
    } finally {
      busy = false; notifyListeners();
    }
  }

  Future<void> restore() async {
    try {
      final saved = await _store.read();
      if (saved == null) return;
      final target = privatePilotOrigin(saved.origin);
      if (target == null) return;
      busy = true; notifyListeners();
      final config = await _readConfig(target);
      final fresh = await _auth.renew(target, config, saved.refreshToken);
      origin = target; _config = config; _tokens = fresh;
      me = await _api('/v1/me');
      if (fresh.refreshToken != null) {
        await _store.write(StoredPilotSession(target.origin, fresh.refreshToken!));
      }
      _startPolling();
      await refresh();
    } catch (e) {
      // Offline login recovery must not delete encrypted credentials.
      error = pilotFriendlyError(e); _tokens = null; me = {};
    } finally {
      busy = false; notifyListeners();
    }
  }

  Future<String> _bearer() async {
    final current = _tokens;
    if (current == null || origin == null || _config == null) {
      throw const PilotFailure('Sign in securely to continue.');
    }
    if (DateTime.now().isBefore(
        current.expiresAt.subtract(const Duration(seconds: 45)))) {
      return current.accessToken;
    }
    if (current.refreshToken == null) {
      throw const PilotFailure('Your session expired. Sign in again.');
    }
    final renewed = await _auth.renew(origin!, _config!, current.refreshToken!);
    _tokens = renewed;
    if (renewed.refreshToken != null) {
      await _store.write(StoredPilotSession(origin!.origin, renewed.refreshToken!));
    }
    return renewed.accessToken;
  }
  Future<Map<String, dynamic>> _api(String path, {
    String method = 'GET', Map<String, dynamic>? body,
    Map<String, String> headers = const {},
  }) async {
    if (origin == null) {
      throw const PilotFailure('Your private backend address is not configured.');
    }
    final token = await _bearer();
    return _request(origin!.resolve(path), method, body, token, {
      if (selectedWorkspace != null) 'x-oagent-workspace': selectedWorkspace!,
      ...headers,
    });
  }
  Future<void> refresh({bool silent = false}) async {
    if (!connected || syncing) return;
    syncing = true;
    if (!silent) notifyListeners();
    try {
      final responses = await Future.wait([
        _api('/v1/devices'), _api('/v1/runs'), _api('/v1/approvals'),
      ]);
      devices = _items(responses[0], 'devices');
      runs = _items(responses[1], 'runs');
      approvals = _items(responses[2], 'approvals');
      error = null;
    } catch (e) {
      error = pilotFriendlyError(e);
    } finally {
      syncing = false; notifyListeners();
    }
  }
  Future<Map<String, dynamic>> runDetail(String id) =>
    _api('/v1/runs/' + Uri.encodeComponent(id));
  Future<List<Map<String, dynamic>>> runEvents(String id) async {
    final result = await _api('/v1/runs/' +
      Uri.encodeComponent(id) + '/events?after=0');
    return _items(result, 'events');
  }
  Future<void> requestTurn({
    required Map<String, dynamic> device, required String kind,
    required String mode, required String prompt, String? sessionId,
  }) async {
    if (!pilotDeviceOnline(device)) {
      throw const PilotFailure('Laptop worker is offline. Keep the worker terminal running.');
    }
    if (!((device['capabilities'] as List?)?.contains(kind) ?? false)) {
      throw const PilotFailure('This worker has not enabled that provider adapter.');
    }
    if (kind == 'codex_cli_turn' && (sessionId == null || sessionId.isEmpty)) {
      throw const PilotFailure('Codex requires an existing verified native session ID.');
    }
    final cwd = device['workspace_root']?.toString() ?? '';
    if (kind != 'workspace_inventory' && cwd.isEmpty) {
      throw const PilotFailure('Worker has not verified an enrolled project folder.');
    }
    await _api('/v1/runs', method: 'POST',
      headers: {'idempotency-key': _requestKey()},
      body: {'deviceId': device['id'], 'kind': kind, 'mode': mode,
        'prompt': prompt, 'cwd': cwd,
        if (sessionId != null && sessionId.isNotEmpty) 'sessionId': sessionId});
    await refresh();
  }
  Future<void> decide(Map<String, dynamic> item, bool approve) async {
    final id = item['id']?.toString() ?? '';
    final hash = item['action_hash']?.toString() ?? '';
    if (!RegExp(r'^[a-f0-9-]{36}$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const PilotFailure('Approval fingerprint is missing or invalid.');
    }
    if (approve && item['actionable'] != true) {
      throw const PilotFailure('Request is no longer safe to approve.');
    }
    await _api('/v1/approvals/' + Uri.encodeComponent(id) + '/decision',
      method: 'POST',
      body: {'approve': approve, 'expectedActionHash': hash});
    await refresh();
  }
  Future<Map<String, dynamic>> inspectPairing(String link) async {
    if (me['role'] != 'owner' || origin == null) {
      throw const PilotFailure('Only a signed-in owner can enroll a worker.');
    }
    return _api('/v1/devices/enrollments/inspect', method: 'POST',
      body: {'pairingToken': pilotPairingToken(link, origin!)});
  }
  Future<void> approvePairing(String link, String expectedFingerprint) async {
    if (me['role'] != 'owner' || origin == null) {
      throw const PilotFailure('Only the workspace owner may approve enrollment.');
    }
    if (!RegExp(r'^[a-f0-9]{24}$').hasMatch(expectedFingerprint)) {
      throw const PilotFailure('Worker fingerprint is not valid.');
    }
    await _api('/v1/devices/enrollments/approve', method: 'POST',
      body: {'pairingToken': pilotPairingToken(link, origin!),
        'expectedFingerprint': expectedFingerprint});
    await refresh();
  }

  Future<void> revokeDevice(Map<String, dynamic> device) async {
    if (me['role'] != 'owner') {
      throw const PilotFailure('Only the owner can revoke a trusted device.');
    }
    final id = device['id']?.toString() ?? '';
    if (!RegExp(r'^[0-9a-f-]{36}' + r'$').hasMatch(id)) {
      throw const PilotFailure('Device identifier was not verified.');
    }
    await _api('/v1/devices/' + Uri.encodeComponent(id) + '/revoke',
      method: 'POST', body: {});
    await refresh();
  }
  Future<void> signOut() async {
    _timer?.cancel();
    await _store.clear();
    _tokens = null; _config = null; me = {};
    devices = []; runs = []; approvals = [];
    error = null; selectedWorkspace = null; notifyListeners();
  }
  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 6),
      (_) => refresh(silent: true));
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) _timer?.cancel();
    if (state == AppLifecycleState.resumed && connected) {
      _startPolling();
      unawaited(refresh());
    }
  }
  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

String pilotFriendlyError(Object error) {
  if (error is PilotFailure) return error.message;
  return 'Secure operation failed. Check your private server or sign in again.';
}
String _requestKey() {
  final secure = Random.secure();
  return base64UrlEncode(List<int>.generate(24, (_) => secure.nextInt(256)))
    .replaceAll('=', '');
}

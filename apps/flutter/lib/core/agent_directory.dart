import 'pilot_native.dart';

/// One truthful provider catalog across iOS and Android. A provider is
/// "session ready" only when a *real recorded session* belongs to a
/// currently-online, capable, non-revoked worker.
enum AgentRoute { sessions, devices, legacyWorkspace, remoteDesktop }
enum AgentState { sessionReady, workerEnabled, offline, needsSetup, separateWorkspace, externalOnly }

class AgentDirectoryEntry {
  const AgentDirectoryEntry({
    required this.id, required this.name, required this.summary,
    required this.status, required this.state, required this.route,
    this.sessionCount = 0, this.officialUrl,
  });
  final String id;
  final String name;
  final String summary;
  final String status;
  final AgentState state;
  final AgentRoute route;
  final int sessionCount;
  final String? officialUrl;

  bool get hasVerifiedSession => state == AgentState.sessionReady;
}

/// Pure catalog projection. Never converts a connected machine into a
/// connected provider account, and never implies consumer chat takeover.
List<AgentDirectoryEntry> buildAgentDirectory({
  required bool signedIn,
  required List<Map<String, dynamic>> devices,
  required List<Map<String, dynamic>> codexSessions,
  required List<Map<String, dynamic>> sdkSessions,
  DateTime? now,
}) {
  final online = signedIn
    ? devices.where((d) => pilotDeviceOnline(d, now)).toList()
    : <Map<String, dynamic>>[];
  final onlineIds = online.map((d) => d['id']?.toString()).toSet();

  bool enabled(String capability) => online.any((d) =>
    (d['capabilities'] is List) &&
    (d['capabilities'] as List).contains(capability));

  final current = now ?? DateTime.now();
  bool recentCodex(Map<String, dynamic> s) {
    final synced = DateTime.tryParse(s['syncedAt']?.toString() ?? '');
    return synced != null &&
      !synced.isAfter(current.add(const Duration(seconds: 10))) &&
      current.difference(synced).inMinutes < 5 &&
      s['sessionId'] is String &&
      (s['sessionId'] as String).length >= 8 &&
      s['cwd'] is String &&
      (s['cwd'] as String).isNotEmpty;
  }

  int readyCodex() => codexSessions.where((s) =>
    recentCodex(s) && onlineIds.contains(s['deviceId']?.toString()) &&
    online.any((d) => d['id']?.toString() == s['deviceId']?.toString() &&
      (d['capabilities'] is List) &&
      (d['capabilities'] as List).contains('codex_cli_turn'))).length;

  List<Map<String, dynamic>> forSdk(String kind) => sdkSessions.where(
    (s) => s['kind'] == kind && s['sessionId'] is String &&
      (s['sessionId'] as String).length >= 8 &&
      s['cwd'] is String && (s['cwd'] as String).isNotEmpty).toList();

  int readySdk(String kind) => forSdk(kind).where((s) =>
    onlineIds.contains(s['deviceId']?.toString()) &&
    online.any((d) => d['id']?.toString() == s['deviceId']?.toString() &&
      (d['capabilities'] is List) &&
      (d['capabilities'] as List).contains(kind))).length;

  AgentDirectoryEntry workerAgent({
    required String id, required String name, required String summary,
    required String capability, required int total, required int ready,
  }) {
    final active = signedIn && ready > 0;
    final configured = enabled(capability);
    final state = active ? AgentState.sessionReady
      : configured ? AgentState.workerEnabled
      : signedIn && total > 0 ? AgentState.offline : AgentState.needsSetup;
    return AgentDirectoryEntry(
      id: id, name: name, summary: summary,
      status: active ? (ready == 1
          ? '$ready resume-eligible session' : '$ready resume-eligible sessions')
        : configured ? 'Worker enabled · no verified active session'
        : signedIn && total > 0
          ? 'Saved sessions · worker offline or adapter unavailable'
        : signedIn ? 'Not enabled on a connected worker' : 'Sign in to discover',
      state: state, route: AgentRoute.sessions,
      sessionCount: signedIn ? total : 0,
    );
  }

  return [
    workerAgent(
      id: 'codex', name: 'OpenAI Codex CLI / IDE',
      summary: 'Verified local Codex threads within your enrolled project.',
      capability: 'codex_cli_turn',
      total: codexSessions.length, ready: readyCodex(),
    ),
    workerAgent(
      id: 'claude_sdk', name: 'Claude Agent SDK',
      summary: 'O-AGENT supervised Claude SDK sessions, not claude.ai tabs.',
      capability: 'claude_agent_turn',
      total: forSdk('claude_agent_turn').length,
      ready: readySdk('claude_agent_turn'),
    ),
    workerAgent(
      id: 'copilot_sdk', name: 'GitHub Copilot SDK',
      summary: 'Verified Copilot SDK conversations on your trusted worker.',
      capability: 'copilot_sdk_turn',
      total: forSdk('copilot_sdk_turn').length,
      ready: readySdk('copilot_sdk_turn'),
    ),
    AgentDirectoryEntry(
      id: 'vscode', name: 'VS Code / project workspace',
      summary: 'Enrolled project access; not control of every open IDE tab.',
      status: !signedIn ? 'Sign in to discover'
        : enabled('workspace_inventory')
          ? 'Trusted project worker online'
          : 'No compatible worker online',
      state: enabled('workspace_inventory')
        ? AgentState.workerEnabled : AgentState.needsSetup,
      route: AgentRoute.devices,
    ),
    const AgentDirectoryEntry(
      id: 'github', name: 'GitHub repositories & Actions',
      summary: 'Use the existing O-AGENT Projects and Actions controls from Remote.',
      status: 'Remote project connector · authorize once',
      state: AgentState.separateWorkspace,
      route: AgentRoute.legacyWorkspace,
    ),
    const AgentDirectoryEntry(
      id: 'cursor', name: 'Cursor Cloud agents',
      summary: 'Existing Cursor Cloud runs and follow-ups in the remote workspace.',
      status: 'Remote cloud connector · authorize once',
      state: AgentState.separateWorkspace,
      route: AgentRoute.legacyWorkspace,
    ),
    const AgentDirectoryEntry(
      id: 'chatgpt', name: 'ChatGPT',
      summary: 'See and interact with your own shared ChatGPT browser window via Remote. Direct chat sync is unavailable.',
      status: 'Control through consented laptop screen',
      state: AgentState.externalOnly,
      route: AgentRoute.remoteDesktop,
    ),
    const AgentDirectoryEntry(
      id: 'claude_web', name: 'Claude (web)',
      summary: 'Claude.ai is accessible via shared desktop; Claude Code has its own official remote control.',
      status: 'Consented desktop or separate Claude Code Remote',
      state: AgentState.externalOnly,
      route: AgentRoute.remoteDesktop,
    ),
    const AgentDirectoryEntry(
      id: 'gemini', name: 'Google Gemini',
      summary: 'Interact with an already-open Gemini browser via consented laptop screen. Gemini CLI sessions need an adapter.',
      status: 'Control through consented laptop screen',
      state: AgentState.externalOnly,
      route: AgentRoute.remoteDesktop,
    ),
  ];
}

/// When several worker capabilities are available, an AI conversation
/// wins over a read-only diagnostic. Explicit user selection is preserved.
String? preferredAgentOperation(Iterable<String> available,
    {String? selected}) {
  final kinds=available.toSet();
  if(selected != null && kinds.contains(selected))return selected;
  for(final kind in const [
    'codex_cli_turn','claude_agent_turn','copilot_sdk_turn'
  ]) {
    if(kinds.contains(kind))return kind;
  }
  return kinds.contains('workspace_inventory')
    ? 'workspace_inventory' : null;
}

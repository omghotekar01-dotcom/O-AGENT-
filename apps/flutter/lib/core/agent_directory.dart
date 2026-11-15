import 'pilot_native.dart';

/// One truthful provider catalog across iOS and Android. A provider is
/// "session ready" only when a *real recorded session* belongs to a
/// currently-online, capable, non-revoked worker.
enum AgentRoute { sessions, devices, legacyWorkspace, officialService }
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

  int readyCodex() => codexSessions.where((s) =>
    onlineIds.contains(s['deviceId']?.toString()) &&
    online.any((d) => d['id']?.toString() == s['deviceId']?.toString() &&
      (d['capabilities'] is List) &&
      (d['capabilities'] as List).contains('codex_cli_turn'))).length;

  List<Map<String, dynamic>> forSdk(String kind) => sdkSessions.where(
    (s) => s['kind'] == kind && s['sessionId'] is String &&
      (s['sessionId'] as String).isNotEmpty).toList();

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
          ? '$ready resumable session' : '$ready resumable sessions')
        : configured ? 'Worker enabled · no verified active session'
        : signedIn && total > 0 ? 'Saved sessions · worker offline'
        : signedIn ? 'Not enabled on a connected worker' : 'Sign in to discover',
      state: state, route: AgentRoute.sessions, sessionCount: total,
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
      summary: 'Projects, Actions and PRs via separately configured legacy connector.',
      status: 'Separate workspace · not linked to this private pilot',
      state: AgentState.separateWorkspace,
      route: AgentRoute.legacyWorkspace,
    ),
    const AgentDirectoryEntry(
      id: 'cursor', name: 'Cursor Cloud agents',
      summary: 'Previously developed connector is in the separate legacy workspace.',
      status: 'Separate workspace · requires its own connection',
      state: AgentState.separateWorkspace,
      route: AgentRoute.legacyWorkspace,
    ),
    const AgentDirectoryEntry(
      id: 'chatgpt', name: 'ChatGPT',
      summary: 'Existing ChatGPT chats and Work sessions are not controllable here.',
      status: 'Official app / website only',
      state: AgentState.externalOnly,
      route: AgentRoute.officialService,
      officialUrl: 'https://chatgpt.com/',
    ),
    const AgentDirectoryEntry(
      id: 'claude_web', name: 'Claude (web)',
      summary: 'claude.ai conversations are separate from Claude Agent SDK sessions.',
      status: 'Official app / website only',
      state: AgentState.externalOnly,
      route: AgentRoute.officialService,
      officialUrl: 'https://claude.ai/',
    ),
    const AgentDirectoryEntry(
      id: 'gemini', name: 'Google Gemini',
      summary: 'Existing consumer chats are not connected to the private worker.',
      status: 'Official app / website only',
      state: AgentState.externalOnly,
      route: AgentRoute.officialService,
      officialUrl: 'https://gemini.google.com/',
    ),
  ];
}

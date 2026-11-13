import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/api_client.dart';
import 'account_workspace.dart';
import 'public_account.dart';
import '../core/models.dart';
import '../theme.dart';
import 'projects.dart';
import 'remote_mission_control.dart';

const _muted = Color(0xFF777A78);
const _ok = Color(0xFF437963);
const _alert = Color(0xFFB46B50);

/// Agent-first mobile workspace. All counters, conversations, approvals and
/// machine statuses come from the real authenticated O-AGENT control plane.
class StudioShell extends StatefulWidget {
  const StudioShell({super.key, required this.controller});
  final ControlController controller;

  @override
  State<StudioShell> createState() => _StudioShellState();
}

class _StudioShellState extends State<StudioShell> {
  int index = 0;
  String agentId = 'navigator';
  Map<String, dynamic>? status;
  Map<String, dynamic>? thread;
  List<Map<String, dynamic>> threads = const [];
  final TextEditingController message = TextEditingController();
  bool loading = false;
  bool loaded = false;
  bool sending = false;
  String? error;

  ControlController get c => widget.controller;
  bool get aiReady => status?['configured'] == true;
  bool get aiVerified => status?['health'] == 'connected';
  List<Map<String, dynamic>> get agents {
    final raw = status?['agents'];
    if (raw is! List) return [];
    return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
  }
  Map<String, dynamic> get activeAgent => agents.firstWhere(
    (a) => a['id'] == agentId,
    orElse: () => {'id': agentId, 'name': 'Agent', 'role': 'Assistant', 'summary': ''},
  );

  @override
  void initState() {
    super.initState();
    c.addListener(_handleConnection);
    if (c.connected && !c.isMember) Future.microtask(_load);
    else Future.microtask(c.reconnectSavedSession);
  }

  void _handleConnection() {
    if (c.connected && !c.isMember && !loaded && !loading) Future.microtask(_load);
    if (!c.connected) {
      loaded = false;
      status = null;
      thread = null;
      threads = const [];
    }
  }

  Future<void> _load() async {
    final api = c.client;
    if (api == null || loading) return;
    setState(() { loading = true; error = null; });
    try {
      final nextStatus = await api.aiStatus();
      final nextThreads = await api.aiThreads();
      if (!mounted || api != c.client) return;
      setState(() {
        status = nextStatus;
        threads = nextThreads;
        loaded = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() { error = e.toString(); loaded = true; });
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Future<void> _openThread(String id) async {
    final api = c.client;
    if (api == null) return;
    setState(() { loading = true; error = null; });
    try {
      final loadedThread = await api.aiThread(id);
      if (!mounted || api != c.client) return;
      setState(() {
        thread = loadedThread;
        agentId = loadedThread['agentId']?.toString() ?? agentId;
        index = 2;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _selectAgent(String next) {
    setState(() {
      agentId = next;
      thread = null;
      index = 2;
    });
  }

  Future<void> _send() async {
    final api = c.client;
    final prompt = message.text.trim();
    if (api == null || sending || prompt.isEmpty) return;
    setState(() { sending = true; error = null; });
    try {
      final next = await api.aiChat(agentId: agentId, message: prompt, threadId: thread?['id']?.toString());
      if (!mounted || api != c.client) return;
      message.clear();
      setState(() { thread = next; });
      final refreshed = await api.aiThreads();
      if (mounted && api == c.client) setState(() => threads = refreshed);
      await c.refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
      try {
        final fresh = await api.aiStatus();
        if (mounted) setState(() => status = fresh);
      } catch (_) { /* preserve original provider error */ }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _task(String kind, String workerId) async {
    final ok = kind == 'system_info'
      ? await c.requestSystemInfo(workerId)
      : await c.requestInventory(workerId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Task queued on your actual machine' : (c.error ?? 'Could not start task'))),
    );
    if (ok) setState(() => index = kind == 'workspace_inventory' ? 4 : 3);
  }

  void _settings() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const _Eyebrow('PREFERENCES'),
            const SizedBox(height: 7),
            const Text('Connection & privacy', style: TextStyle(fontSize: 25, fontWeight: FontWeight.w700, color: OTheme.ink)),
            const SizedBox(height: 18),
            const Text('Control plane', style: TextStyle(color: _muted, fontSize: 12)),
            const SizedBox(height: 4),
            SelectableText(c.endpoint ?? 'Not connected', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text(aiReady ? 'AI: ${status?['provider']} / ${status?['model']}' : 'AI provider not configured on backend'),
            const SizedBox(height: 10),
            Text(c.hasSavedSession ? 'The operator token is protected in Android Keystore / iOS Keychain on this device. Disconnect deletes it. Model keys remain on your backend.' : 'The operator token is in app memory only. Model keys stay on your backend.', style: const TextStyle(fontSize: 12, color: _muted, height: 1.5)),
            const SizedBox(height: 15),
            SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.push(context, MaterialPageRoute<void>(
                  builder: (_) => AccountWorkspaceScreen(controller: c)));
              },
              icon: const Icon(Icons.hub_outlined),
              label: const Text('My AI accounts & invitations'),
            )),
            const SizedBox(height: 15),
            SizedBox(width: double.infinity, child: OutlinedButton.icon(
              onPressed: () { Navigator.pop(ctx); c.disconnect(); },
              icon: const Icon(Icons.logout), label: const Text('Disconnect'),
            )),
          ]),
        ),
      ),
    );
  }

  @override
  void dispose() {
    c.removeListener(_handleConnection);
    message.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: c,
      builder: (context, _) {
        if (!c.connected) return StudioConnect(controller: c);
        if (c.isMember) return AccountWorkspaceScreen(controller: c);
        return Scaffold(
          appBar: AppBar(
            titleSpacing: 22,
            title: const Row(mainAxisSize: MainAxisSize.min, children: [
              _Mark(size: 29),
              SizedBox(width: 9),
              Text('o-agent', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 21, letterSpacing: -1.2)),
            ]),
            actions: [
              if (loading || c.refreshing) const Padding(
                padding: EdgeInsets.all(15), child: SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              IconButton(tooltip: 'Refresh', onPressed: () async { await c.refresh(); await _load(); }, icon: const Icon(Icons.sync_rounded)),
              IconButton(tooltip: 'Connection settings', onPressed: _settings, icon: const Icon(Icons.tune_rounded)),
              const SizedBox(width: 8),
            ],
          ),
          body: SafeArea(
            child: Center(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 860),
              child: Column(children: [
                if (error != null) MaterialBanner(
                  content: Text(error!), actions: [
                    TextButton(onPressed: () => setState(() => error = null), child: const Text('Dismiss')),
                  ],
                ),
                if (c.error != null) MaterialBanner(
                  content: Text(c.error!), actions: [
                    TextButton(onPressed: c.clearError, child: const Text('Dismiss')),
                  ],
                ),
                Expanded(child: switch (index) {
                  0 => RemoteMissionControlScreen(controller: c),
                  1 => _agents(),
                  2 => _chat(),
                  3 => _tasks(),
                  _ => _approvals(),
                }),
              ]),
            )),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            onDestinationSelected: (next) => setState(() => index = next),
            destinations: const [
              NavigationDestination(icon: Icon(Icons.settings_remote_outlined), selectedIcon: Icon(Icons.settings_remote_rounded), label: 'Remote'),
              NavigationDestination(icon: Icon(Icons.grid_view_outlined), selectedIcon: Icon(Icons.grid_view_rounded), label: 'Agents'),
              NavigationDestination(icon: Icon(Icons.chat_bubble_outline_rounded), selectedIcon: Icon(Icons.chat_bubble_rounded), label: 'Chat'),
              NavigationDestination(icon: Icon(Icons.list_alt_rounded), label: 'Activity'),
              NavigationDestination(icon: Icon(Icons.verified_user_outlined), selectedIcon: Icon(Icons.verified_user_rounded), label: 'Approvals'),
            ],
          ),
        );
      },
    );
  }

  // Kept for the transitional dashboard while project-first navigation is validated.
  // ignore: unused_element
  Widget _home() {
    final snapshot = c.snapshot!;
    final online = snapshot.machines.where((m) => m.online).toList();
    return RefreshIndicator(
      onRefresh: () async { await c.refresh(); await _load(); },
      child: ListView(padding: const EdgeInsets.fromLTRB(22, 16, 22, 28), children: [
        const _Eyebrow('THE WORKSPACE'),
        const SizedBox(height: 11),
        const Text('Make room for\nbetter ideas.', style: TextStyle(
          fontSize: 37, height: 1.12, letterSpacing: -1.6,
          fontWeight: FontWeight.w700, color: OTheme.ink,
        )),
        const SizedBox(height: 12),
        const Text('Think with your agents. Act with your tools. Stay in control.',
            style: TextStyle(fontSize: 14, height: 1.5, color: _muted)),
        const SizedBox(height: 25),
        _Tile(
          bg: OTheme.lavender,
          padding: const EdgeInsets.all(22),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.forum_outlined, color: OTheme.violet, size: 21),
              const Spacer(),
              _StatusLabel(label: aiVerified ? 'AI VERIFIED' : (aiReady ? 'AI UNVERIFIED' : 'SETUP REQUIRED'), color: aiVerified ? _ok : _alert),
            ]),
            const SizedBox(height: 18),
            const Text('Start a conversation', style: TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
            const SizedBox(height: 6),
            Text(aiReady ? 'Ask a question, make a plan or get your connected machine status.' : 'Add a provider API key to your laptop backend to unlock agent conversations.',
              style: const TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF5E5970))),
            const SizedBox(height: 20),
            Align(alignment: Alignment.centerLeft, child: FilledButton.icon(
              onPressed: aiReady ? () { setState(() { index = 2; thread = null; }); } : _settings,
              icon: Icon(aiReady ? Icons.arrow_outward_rounded : Icons.settings_outlined, size: 18),
              label: Text(aiReady ? 'New conversation' : 'Provider setup'),
            )),
          ]),
        ),
        const SizedBox(height: 27),
        _SectionHeading('Your agents', action: 'See all', onTap: () => setState(() => index = 1)),
        const SizedBox(height: 11),
        Row(children: [
          for (final (i, id) in ['navigator', 'researcher', 'operator'].indexed) ...[
            Expanded(child: _AgentSmallCard(
              label: ['Navigator', 'Researcher', 'Operator'][i],
              icon: [Icons.explore_outlined, Icons.manage_search_outlined, Icons.devices_other_outlined][i],
              color: [OTheme.warm, OTheme.sage, OTheme.lavender][i],
              onTap: () => _selectAgent(id),
            )),
            if (i < 2) const SizedBox(width: 9),
          ],
        ]),
        const SizedBox(height: 29),
        _SectionHeading('Connected machines', action: 'Refresh', onTap: c.refresh),
        const SizedBox(height: 10),
        if (online.isEmpty)
          const _EmptyState(icon: Icons.computer_outlined, title: 'No machine online',
            description: 'Start the O-AGENT worker on your laptop to connect it here.')
        else
          for (final machine in online)
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _Tile(
                child: Row(children: [
                  Container(width: 42, height: 42,
                    decoration: BoxDecoration(color: OTheme.sage, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.laptop_rounded, color: OTheme.ink)),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(machine.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text(machine.id, style: const TextStyle(fontSize: 12, color: _muted)),
                  ])),
                  TextButton(onPressed: () => _machineActions(machine), child: const Text('Manage')),
                ]),
              ),
            ),
        const SizedBox(height: 26),
        _SectionHeading('Recent conversations', action: 'Open chat', onTap: () => setState(() => index = 2)),
        const SizedBox(height: 10),
        if (threads.isEmpty)
          const _EmptyState(icon: Icons.edit_note_rounded, title: 'A blank page',
            description: 'Start your first conversation. Threads are stored by your local control plane.')
        else
          for (final item in threads.take(3))
            Padding(
              padding: const EdgeInsets.only(bottom: 9),
              child: _Tile(
                child: InkWell(
                  onTap: () => _openThread(item['id'].toString()),
                  child: Row(children: [
                    const Icon(Icons.arrow_outward, size: 20, color: OTheme.violet),
                    const SizedBox(width: 12),
                    Expanded(child: Text(item['title']?.toString() ?? 'Conversation', maxLines: 2, overflow: TextOverflow.ellipsis)),
                    const Icon(Icons.chevron_right_rounded, color: _muted),
                  ]),
                ),
              ),
            ),
      ]),
    );
  }

  Widget _agents() => ListView(
    padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
    children: [
      const _Eyebrow('A TEAM YOU SHAPE'),
      const SizedBox(height: 9),
      const Text('Meet your agents.', style: _heading),
      const SizedBox(height: 9),
      const Text('Different ways to think and work with one real provider connection.', style: TextStyle(color: _muted, height: 1.5)),
      const SizedBox(height: 21),
      if (!aiReady) const _EmptyState(icon: Icons.key_outlined, title: 'AI not connected',
        description: 'Configure a provider API key on the backend, then refresh here.'),
      for (final (i, agent) in agents.indexed)
        Padding(padding: const EdgeInsets.only(bottom: 12),
          child: _Tile(padding: const EdgeInsets.all(20), child: InkWell(
            onTap: aiReady ? () => _selectAgent(agent['id'].toString()) : null,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(width: 44, height: 44,
                  decoration: BoxDecoration(color: [OTheme.warm, OTheme.sage, OTheme.lavender][i % 3], borderRadius: BorderRadius.circular(13)),
                  child: Icon([Icons.explore_rounded, Icons.search_rounded, Icons.dns_rounded][i % 3], color: OTheme.ink)),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(agent['name'].toString(), style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  Text(agent['role'].toString(), style: const TextStyle(color: _muted, fontSize: 12)),
                ])),
                const Icon(Icons.arrow_outward_rounded, color: OTheme.violet),
              ]),
              const SizedBox(height: 15),
              Text(agent['summary'].toString(), style: const TextStyle(height: 1.45, color: OTheme.ink, fontSize: 13)),
              const SizedBox(height: 12),
              Text(aiReady ? 'Uses ${status?['model']}' : 'Requires backend AI setup',
                style: const TextStyle(color: _muted, fontSize: 11)),
            ]),
          )),
        ),
      const SizedBox(height: 9),
      const _Note('These are server-defined agent profiles, not claims of independently running cloud agents. Tools are restricted to the installed local gateway.'),
    ],
  );

  Widget _chat() {
    final msgs = (thread?['messages'] is List ? thread!['messages'] as List : const []).cast<dynamic>();
    return Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(21, 10, 21, 10), child: Row(children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const _Eyebrow('CONVERSATION'),
          const SizedBox(height: 5),
          Text(activeAgent['name'].toString(), style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700, letterSpacing: -0.6)),
          Text(aiReady ? (aiVerified ? 'Provider connected · ' : 'Provider not verified · ') + status!['provider'].toString() + ' · ' + status!['model'].toString() : 'Provider not configured',
            style: const TextStyle(color: _muted, fontSize: 11), maxLines: 1, overflow: TextOverflow.ellipsis),
        ])),
        PopupMenuButton<String>(
          tooltip: 'Switch agent',
          icon: const Icon(Icons.swap_horiz_rounded),
          onSelected: _selectAgent,
          itemBuilder: (context) => agents.map((a) => PopupMenuItem(
            value: a['id'].toString(), child: Text(a['name'].toString()),
          )).toList(),
        ),
        IconButton(tooltip: 'New thread', onPressed: () => setState(() => thread = null), icon: const Icon(Icons.add_rounded)),
      ])),
      const Divider(height: 1),
      Expanded(child: msgs.isEmpty
        ? ListView(padding: const EdgeInsets.all(25), children: [
          const SizedBox(height: 45),
          const _Mark(size: 49),
          const SizedBox(height: 17),
          const Text('Where should we begin?', style: TextStyle(fontSize: 27, fontWeight: FontWeight.w700, letterSpacing: -0.5)),
          const SizedBox(height: 8),
          Text(aiReady
            ? 'Ask ${activeAgent['name']} anything. It can also look up real machine and task state through approved tools.'
            : 'Your agent will be ready after you configure an API key on the backend.',
            style: const TextStyle(fontSize: 13, color: _muted, height: 1.5)),
          const SizedBox(height: 22),
          for (final prompt in [
            'Which of my laptops are online?',
            'Check recent tasks and tell me what happened.',
            'Help me plan my next project.',
          ]) Padding(padding: const EdgeInsets.only(bottom: 9), child:
            OutlinedButton(
              onPressed: aiReady ? () => setState(() => message.text = prompt) : null,
              child: Align(alignment: Alignment.centerLeft, child: Text(prompt, maxLines: 2)),
            ),
          ),
          if (!aiReady) Padding(padding: const EdgeInsets.only(top: 18),
            child: FilledButton(onPressed: _settings, child: const Text('View setup status'))),
        ])
        : ListView.builder(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          reverse: true,
          itemCount: msgs.length + (sending ? 1 : 0),
          itemBuilder: (context, index) {
            if (sending && index == 0) return const Padding(
              padding: EdgeInsets.all(12), child: Row(children: [
                SizedBox(height: 15, width: 15, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 10), Text('Thinking and checking tools…', style: TextStyle(color: _muted, fontSize: 12)),
              ]),
            );
            final item = Map<String, dynamic>.from(msgs[msgs.length - 1 - index + (sending ? 1 : 0)] as Map);
            final user = item['role'] == 'user';
            return Align(alignment: user ? Alignment.centerRight : Alignment.centerLeft,
              child: Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
                constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.83),
                decoration: BoxDecoration(
                  color: user ? OTheme.lavender : Colors.white,
                  border: user ? null : Border.all(color: OTheme.hairline),
                  borderRadius: BorderRadius.circular(17),
                ),
                child: SelectableText(item['content']?.toString() ?? '',
                  style: const TextStyle(fontSize: 14, height: 1.5, color: OTheme.ink)),
              ),
            );
          },
        )),
      Container(
        padding: const EdgeInsets.fromLTRB(15, 11, 15, 14),
        decoration: const BoxDecoration(color: OTheme.paper, border: Border(top: BorderSide(color: OTheme.hairline))),
        child: SafeArea(top: false, child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(child: TextField(
            controller: message,
            maxLines: 4, minLines: 1,
            maxLength: 4000,
            enabled: aiReady && !sending,
            textCapitalization: TextCapitalization.sentences,
            keyboardType: TextInputType.multiline,
            decoration: const InputDecoration(
              hintText: 'Ask or give a task…',
              counterText: '',
            ),
            onSubmitted: (_) => _send(),
          )),
          const SizedBox(width: 9),
          Padding(padding: const EdgeInsets.only(bottom: 2), child: IconButton.filled(
            tooltip: 'Send message',
            onPressed: aiReady && !sending ? _send : null,
            icon: sending
              ? const SizedBox(height: 17, width: 17, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.arrow_upward_rounded),
          )),
        ])),
      ),
    ]);
  }

  Widget _tasks() {
    final tasks = c.snapshot!.tasks;
    return RefreshIndicator(onRefresh: c.refresh, child: ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 28),
      children: [
        const _Eyebrow('ACTIVITY LOG'),
        const SizedBox(height: 9),
        const Text('The work, in progress.', style: _heading),
        const SizedBox(height: 8),
        const Text('Every task below is a real backend record, never an estimate.', style: TextStyle(color: _muted)),
        const SizedBox(height: 22),
        if (tasks.isEmpty) const _EmptyState(icon: Icons.hourglass_empty_rounded,
          title: 'Nothing in the queue', description: 'Ask an agent to check your machine, or open a device to start a task.'),
        ...tasks.take(35).map((task) => Padding(padding: const EdgeInsets.only(bottom: 9), child:
          _Tile(child: InkWell(onTap: () => _taskDetails(task), child: Row(children: [
            Icon(task.kind == 'system_info' ? Icons.monitor_heart_outlined : Icons.folder_copy_outlined, color: OTheme.violet),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 3),
              Text(task.workerId, style: const TextStyle(color: _muted, fontSize: 12)),
            ])),
            _StatusLabel(label: task.status.replaceAll('_', ' '),
              color: task.status == 'completed' ? _ok : task.awaitingApproval ? _alert : OTheme.violet),
          ]))),
        )),
      ],
    ));
  }

  Widget _approvals() {
    final items = c.snapshot!.tasks.where((t) => t.awaitingApproval).toList();
    final pendingActions = <({AgentTask task, Map<String, dynamic> approval})>[];
    for (final task in c.snapshot!.tasks.where((t) => t.running)) {
      for (final raw in (task.approvals ?? {}).values) {
        if (raw is Map && raw['state'] == 'pending') {
          pendingActions.add((task: task, approval: Map<String, dynamic>.from(raw)));
        }
      }
    }
    return RefreshIndicator(onRefresh: c.refresh, child: ListView(
      padding: const EdgeInsets.fromLTRB(22, 14, 22, 30),
      children: [
        const _Eyebrow('HUMAN IN THE LOOP'),
        const SizedBox(height: 9),
        const Text('Your call.', style: _heading),
        const SizedBox(height: 8),
        const Text('Nothing happens here without your decision.', style: TextStyle(color: _muted)),
        const SizedBox(height: 22),
        if (items.isEmpty && pendingActions.isEmpty) const _EmptyState(icon: Icons.verified_user_outlined,
          title: 'All clear', description: 'Requests requiring a decision will appear here.'),
        for (final task in items) Padding(padding: const EdgeInsets.only(bottom: 12), child: _Tile(
          padding: const EdgeInsets.all(19),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _StatusLabel(label: 'NEEDS APPROVAL', color: _alert),
            const SizedBox(height: 14),
            Text(task.title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text('Machine: ${task.workerId}', style: const TextStyle(fontSize: 13, color: _muted)),
            const SizedBox(height: 7),
            Text(task.kind == 'codex_cli_turn'
                ? 'Resumes your selected Codex CLI session through the official app-server. Read-only mode prevents file edits; project edits mode can change files within the selected workspace.'
                : task.kind == 'codex_cloud_submit'
                  ? 'Creates a NEW Codex Cloud task in the selected environment, potentially using provider credits.'
                  : 'Lists only the top-level workspace filenames.',
              style: const TextStyle(fontSize: 12, height: 1.5, color: _muted)),
            if (task.kind == 'codex_cli_turn') ...[
              const SizedBox(height: 9),
              Text('Workspace: ' + (task.parameters?['cwd']?.toString() ?? ''),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              Text('Mode: ' + (task.parameters?['mode']?.toString() ?? ''),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SelectableText('Exact Codex prompt: ' + (task.parameters?['prompt']?.toString() ?? ''),
                style: const TextStyle(fontSize: 12, height: 1.5)),
            ],
            if (task.kind == 'codex_cloud_submit') ...[
              const SizedBox(height: 8),
              Text('Environment: ' + (task.parameters?['environmentId']?.toString() ?? 'Unknown'),
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SelectableText('Exact prompt: ' + (task.parameters?['prompt']?.toString() ?? ''),
                style: const TextStyle(fontSize: 12, height: 1.5)),
            ],
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: OutlinedButton(
                onPressed: c.acting ? null : () => _decide(task, false), child: const Text('Deny'),
              )),
              const SizedBox(width: 10),
              Expanded(child: FilledButton(
                onPressed: c.acting ? null : () => _decide(task, true), child: const Text('Approve'),
              )),
            ]),
          ]),
        )),
        for (final pair in pendingActions)
          Padding(padding: const EdgeInsets.only(bottom: 12), child: _Tile(
            padding: const EdgeInsets.all(19),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _StatusLabel(label: 'CODEX TOOL APPROVAL', color: _alert),
              const SizedBox(height: 11),
              Text(pair.approval['kind']?.toString() ?? 'Tool request',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
              const SizedBox(height: 8),
              Text('Machine: ' + pair.task.workerId,
                style: const TextStyle(fontSize: 12, color: _muted)),
              const SizedBox(height: 8),
              SelectableText(pair.approval['description']?.toString() ?? '',
                style: const TextStyle(fontSize: 12, height: 1.5)),
              const SizedBox(height: 13),
              Row(children: [
                Expanded(child: OutlinedButton(
                  onPressed: () => _decideCodexPermission(pair.task, pair.approval, false),
                  child: const Text('Deny'))),
                const SizedBox(width: 10),
                Expanded(child: FilledButton(
                  onPressed: () => _decideCodexPermission(pair.task, pair.approval, true),
                  child: const Text('Approve action'))),
              ]),
            ]),
          )),
        const SizedBox(height: 12),
        const _Note('Review the complete target and exact prompt before approving. Cloud task submissions may incur provider charges; O-AGENT approval only authorizes the specified request.'),
      ],
    ));
  }

  Future<void> _decideCodexPermission(AgentTask task,
      Map<String, dynamic> request, bool approve) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(approve ? 'Approve this Codex action?' : 'Deny this Codex action?'),
      content: SingleChildScrollView(child: SelectableText(
        'Workspace: ' + (task.parameters?['cwd']?.toString() ?? '') +
        '\nType: ' + (request['kind']?.toString() ?? '') +
        '\n\n' + (request['description']?.toString() ?? '') +
        '\n\nOnly this specific request will be decided.')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          child: Text(approve ? 'Authorize action' : 'Deny')),
      ],
    ));
    if (yes != true || !mounted) return;
    try {
      await c.client!.decideCodexAction(
        taskId: task.id, approvalId: request['id'].toString(), approve: approve);
      await c.refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _decide(AgentTask task, bool approve) async {
    final allowed = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(approve ? 'Approve this request?' : 'Reject this request?'),
      content: Text('${task.title}\n\nMachine: ${task.workerId}\nTask ID: ${task.id}\n\nFor local Codex turns, this resumes the selected session with the exact approved prompt and sandbox mode. For cloud tasks, it starts a NEW provider task. For inventory, it lists filenames only.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(approve ? 'Approve' : 'Reject')),
      ],
    ));
    if (allowed != true) return;
    final ok = await c.resolveApproval(task.id, approve);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(ok ? 'Decision recorded by the backend' : (c.error ?? 'Failed'))));
  }

  void _taskDetails(AgentTask t) {
    showModalBottomSheet<void>(context: context, showDragHandle: true,
      isScrollControlled: true, builder: (ctx) => SafeArea(child: Padding(
        padding: const EdgeInsets.all(22), child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Eyebrow('TASK DETAILS'),
            const SizedBox(height: 10),
            Text(t.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w700)),
            const SizedBox(height: 9),
            _StatusLabel(label: t.status.replaceAll('_', ' '), color: t.status == 'completed' ? _ok : _alert),
            const SizedBox(height: 12),
            SelectableText('Machine: ${t.workerId}\nTask ID: ${t.id}', style: const TextStyle(color: _muted, height: 1.6)),
            if (t.parameters != null) ...[
              const SizedBox(height: 16),
              const Text('Approved action arguments', style: TextStyle(fontWeight: FontWeight.w700)),
              SelectableText(const JsonEncoder.withIndent('  ').convert(t.parameters),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
            if (t.result != null) ...[
              const SizedBox(height: 17),
              const Text('Verified worker output', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              SelectableText(const JsonEncoder.withIndent('  ').convert(t.result),
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
            if (t.error != null) Padding(padding: const EdgeInsets.only(top: 15),
              child: Text(t.error!, style: const TextStyle(color: _alert))),
          ],
        )),
      )));
  }

  void _machineActions(Machine machine) {
    showModalBottomSheet<void>(context: context, showDragHandle: true, builder: (ctx) => SafeArea(
      child: Padding(padding: const EdgeInsets.all(22), child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Eyebrow('CONNECTED MACHINE'),
          const SizedBox(height: 8),
          Text(machine.name, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700)),
          Text(machine.id, style: const TextStyle(fontSize: 12, color: _muted)),
          const SizedBox(height: 20),
          SizedBox(width: double.infinity, child: FilledButton.icon(
            onPressed: () { Navigator.pop(ctx); _task('system_info', machine.id); },
            icon: const Icon(Icons.monitor_heart_outlined), label: const Text('Get system report'),
          )),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: OutlinedButton.icon(
            onPressed: () { Navigator.pop(ctx); _task('workspace_inventory', machine.id); },
            icon: const Icon(Icons.folder_open_rounded), label: const Text('Request workspace inventory'),
          )),
        ],
      )),
    ));
  }
}

class StudioConnect extends StatefulWidget {
  const StudioConnect({super.key, required this.controller});
  final ControlController controller;
  @override
  State<StudioConnect> createState() => _StudioConnectState();
}

class _StudioConnectState extends State<StudioConnect> {
  final url = TextEditingController(text: 'http://127.0.0.1:8787');
  final token = TextEditingController();
  final inviteCode = TextEditingController();
  final displayName = TextEditingController();
  bool joining = false;
  bool hidden = true;
  bool rememberDevice = false;
  @override
  void dispose() { url.dispose(); token.dispose(); inviteCode.dispose(); displayName.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(animation: widget.controller, builder: (context, _) =>
    Scaffold(body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 460),
      child: SingleChildScrollView(padding: const EdgeInsets.all(27), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _Mark(size: 55),
          const SizedBox(height: 30),
          const _Eyebrow('WELCOME TO O-AGENT'),
          const SizedBox(height: 11),
          const Text('Good work\nstarts here.', style: TextStyle(color: OTheme.ink,
            fontSize: 40, height: 1.14, letterSpacing: -1.5, fontWeight: FontWeight.w700)),
          const SizedBox(height: 12),
          const Text('Only real machines and real AI responses appear here. Connect to your own control plane to begin.',
            style: TextStyle(fontSize: 14, color: _muted, height: 1.5)),
          const SizedBox(height: 31),
          const Text('Choose your workspace connection', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
          const SizedBox(height: 11),
          Row(children: [
            Expanded(child: ChoiceChip(label: const Text('My owner workspace'),
              selected: !joining, onSelected: (_) => setState(() => joining = false))),
            const SizedBox(width: 9),
            Expanded(child: ChoiceChip(label: const Text('Join with invitation'),
              selected: joining, onSelected: (_) => setState(() => joining = true))),
          ]),
          const SizedBox(height: 10),
          TextButton.icon(
            onPressed: () => Navigator.push(context, MaterialPageRoute<void>(
              builder: (_) => PublicAccountScreen(controller: widget.controller,
                backend: url.text, remember: rememberDevice))),
            icon: const Icon(Icons.person_add_alt_outlined),
            label: const Text('Public cloud account: sign up / sign in'),
          ),
          const SizedBox(height: 14),
          TextField(controller: url, keyboardType: TextInputType.url,
            decoration: const InputDecoration(labelText: 'Backend HTTPS URL', prefixIcon: Icon(Icons.link))),
          const SizedBox(height: 13),
          if (joining) ...[
            const Padding(padding: EdgeInsets.only(bottom: 10),
              child: Text('Your code works only once. On a private phone, enable Remember this device to keep your new personal account after closing the app.',
                style: TextStyle(color: _muted, fontSize: 12, height: 1.5))),
            TextField(controller: displayName, maxLength: 80,
              decoration: const InputDecoration(labelText: 'Your display name',
                prefixIcon: Icon(Icons.person_outline))),
            const SizedBox(height: 10),
            TextField(controller: inviteCode, autocorrect: false, enableSuggestions: false,
              decoration: const InputDecoration(labelText: 'One-time invitation code',
                prefixIcon: Icon(Icons.mail_outline))),
          ] else TextField(controller: token, obscureText: hidden, autocorrect: false, enableSuggestions: false,
            decoration: InputDecoration(labelText: 'Operator token',
              prefixIcon: const Icon(Icons.key_outlined),
              suffixIcon: IconButton(tooltip: 'Toggle token visibility', icon: Icon(hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => hidden = !hidden)))),
          const SizedBox(height: 8),
          CheckboxListTile(
            value: rememberDevice,
            onChanged: (v) => setState(() => rememberDevice = v ?? false),
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Remember this device', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: const Text('Uses Android Keystore / iOS Keychain. Avoid on shared phones.', style: TextStyle(fontSize: 11)),
          ),
          const SizedBox(height: 8),
          SizedBox(width: double.infinity, child: FilledButton(
            onPressed: widget.controller.connecting || widget.controller.restoringSession ? null : () async {
              if (joining) {
                try {
                  final personalToken = await AgentApi.claimInvitation(
                    backend: url.text, invitationCode: inviteCode.text,
                    displayName: displayName.text);
                  final ok = await widget.controller.connect(url.text, personalToken,
                    remember: rememberDevice);
                  if (ok) inviteCode.clear();
                } catch (e) {
                  if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(e.toString())));
                }
              } else {
                final ok = await widget.controller.connect(url.text, token.text,
                  remember: rememberDevice);
                if (ok) token.clear();
              }
            },
            child: Text(widget.controller.connecting ? 'Connecting…'
              : joining ? 'Join my private AI workspace' : 'Connect to O-AGENT'),
          )),
          if (widget.controller.restoringSession)
            const Padding(padding: EdgeInsets.only(top: 12),
              child: Text('Restoring your saved connection…', style: TextStyle(color: _muted))),
          if (widget.controller.hasSavedSession && !widget.controller.restoringSession)
            Padding(padding: const EdgeInsets.only(top: 11),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.lock_open_outlined),
                onPressed: widget.controller.reconnectSavedSession,
                label: const Text('Reconnect saved device'),
              )),
          if (widget.controller.error != null) Padding(padding: const EdgeInsets.only(top: 12),
            child: Text(widget.controller.error!, style: const TextStyle(color: _alert))),
          const SizedBox(height: 25),
          const _Note('Owners use their existing token; invited members use a one-time code. New public accounts require an HTTPS hosted backend with verified email configured. Everyone supplies their own AI keys in Connections. Computer controls stay owner-only.'),
        ],
      )),
    )))),
  );
}

const _heading = TextStyle(fontSize: 29, height: 1.16, letterSpacing: -0.9, fontWeight: FontWeight.w700, color: OTheme.ink);
class _Mark extends StatelessWidget {
  const _Mark({this.size = 31});
  final double size;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size,
    decoration: BoxDecoration(color: OTheme.violet, borderRadius: BorderRadius.circular(size * .29)),
    child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * .55),
  );
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Text(text, style: const TextStyle(
    color: OTheme.violet, fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w800,
  ));
}
class _Tile extends StatelessWidget {
  const _Tile({required this.child, this.bg = Colors.white, this.padding = const EdgeInsets.all(15)});
  final Widget child;
  final Color bg;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(18),
      border: Border.all(color: bg == Colors.white ? OTheme.hairline : bg)),
    child: child,
  );
}
class _StatusLabel extends StatelessWidget {
  const _StatusLabel({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
    decoration: BoxDecoration(color: color.withValues(alpha: .10), borderRadius: BorderRadius.circular(20)),
    child: Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w800)),
  );
}
class _SectionHeading extends StatelessWidget {
  const _SectionHeading(this.title, {required this.action, required this.onTap});
  final String title, action;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, letterSpacing: -.4))),
    TextButton(onPressed: onTap, child: Text(action)),
  ]);
}
class _AgentSmallCard extends StatelessWidget {
  const _AgentSmallCard({required this.label, required this.icon, required this.color, required this.onTap});
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap, borderRadius: BorderRadius.circular(16),
    child: Container(
      constraints: const BoxConstraints(minHeight: 106),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: OTheme.ink, size: 24),
          const SizedBox(height: 14),
          FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
            child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
        ]),
    ),
  );
}
class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.icon, required this.title, required this.description});
  final IconData icon;
  final String title, description;
  @override
  Widget build(BuildContext context) => _Tile(child: Padding(
    padding: const EdgeInsets.symmetric(vertical: 15),
    child: Column(children: [
      Icon(icon, size: 32, color: OTheme.violet),
      const SizedBox(height: 11),
      Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      const SizedBox(height: 5),
      Text(description, textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 12, height: 1.5, color: _muted)),
    ]),
  ));
}
class _Note extends StatelessWidget {
  const _Note(this.message);
  final String message;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    const Icon(Icons.info_outline, color: _muted, size: 17),
    const SizedBox(width: 9),
    Expanded(child: Text(message, style: const TextStyle(fontSize: 12, height: 1.5, color: _muted))),
  ]);
}

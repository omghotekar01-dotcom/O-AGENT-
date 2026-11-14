import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/api_client.dart';
import 'codex_session.dart';
import 'agent_sdk_bridge.dart';
import 'screen_preview.dart';
import 'remote_fullscreen.dart';
import 'push_devices.dart';
import 'vscode_remote.dart';
import 'cursor_cloud.dart';
import 'ios_components.dart';
import 'projects.dart';
import 'free_ai_hub.dart';
import 'account_workspace.dart';

Map<String, dynamic> remoteMap(Object? v) => v is Map
  ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> remoteList(Object? v) => v is List
  ? v.whereType<Map>().map(remoteMap).toList() : <Map<String, dynamic>>[];

/// Owner-only agent control center. It never mistakes a saved CLI session for
/// an actively shared IDE window. In-app SSE notifies changes; the backend
/// snapshot is reloaded to make decisions based on authoritative state.
class RemoteMissionControlScreen extends StatefulWidget {
  const RemoteMissionControlScreen({super.key, required this.controller});
  final ControlController controller;
  @override State<RemoteMissionControlScreen> createState() =>
    _RemoteMissionControlState();
}
class _RemoteMissionControlState extends State<RemoteMissionControlScreen>
    with WidgetsBindingObserver {
  Timer? poller;
  StreamSubscription<Map<String, dynamic>>? liveEvents;
  Map<String, dynamic>? data;
  String? error;
  bool loading = false;
  String filter = 'all';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    _watchEvents();
    poller = Timer.periodic(const Duration(seconds: 12), (_) {
      _refresh();
      if (liveEvents == null) _watchEvents();
    });
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refresh();
      if (liveEvents == null) _watchEvents();
    }
  }
  @override
  void dispose() {
    poller?.cancel();
    liveEvents?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  void _watchEvents() {
    final api = widget.controller.client;
    if (api == null || liveEvents != null) return;
    liveEvents = api.ownerEventStream().listen((event) {
      if (!mounted || api != widget.controller.client) return;
      final type = event['type']?.toString() ?? '';
      if (type.startsWith('codex.') || type.startsWith('task.') ||
          type.startsWith('provider.codex_local.') ||
          type == 'machine.online') _refresh();
    }, onError: (Object _) {
      liveEvents = null;
    }, onDone: () {
      liveEvents = null;
    }, cancelOnError: true);
  }
  Future<void> _refresh() async {
    if (!mounted || loading) return;
    final api = widget.controller.client;
    if (api == null) {
      setState(() => error = 'The owner backend is offline.');
      return;
    }
    loading = true;
    try {
      final next = await api.remoteAgentOverview();
      if (mounted && api == widget.controller.client) {
        setState(() { data = next; error = null; });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is ApiException && e.statusCode == 404
          ? 'This backend does not have the Remote endpoint. On your laptop, '
            'stop O-AGENT, run git pull origin main, and restart O-AGENT.cmd. '
            'Check that your phone uses the same private Tailscale URL, '
            'then tap Retry.'
          : e.toString());
      }
    } finally { loading = false; }
  }
  void _openCodex(Map<String, dynamic> session, {String? taskId}) {
    final project = session['projectId']?.toString() ?? '';
    final id = session['sessionId']?.toString() ?? '';
    if (project.isEmpty || id.isEmpty) return;
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
      CodexSessionScreen(
        controller: widget.controller,
        projectId: project, sessionId: id,
        sessionTitle: session['title']?.toString() ??
          session['sessionTitle']?.toString() ?? 'Codex session',
        cwd: session['cwd']?.toString() ?? '',
        initialTaskId: taskId,
      )));
  }
  void _openBridge([String? task]) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      AgentSdkBridgeScreen(controller: widget.controller, taskId: task)));
  void _openVsCode([String? task]) => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      VsCodeRemoteScreen(controller: widget.controller, taskId: task)));
  void _openPush() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      PushDeviceScreen(controller: widget.controller)));
  // One tap from Remote opens the actual live console instead of requiring
  // a separate preview page, then an extra Full screen / trackpad button.
  void _openScreen() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      RemoteFullscreenScreen(controller: widget.controller)));
  void _openScreenSetup() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      ScreenPreviewScreen(controller: widget.controller)));
  void _openCursor() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      CursorCloudScreen(controller: widget.controller)));
  void _openProjects() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      ProjectHubScreen(controller: widget.controller)));
  void _openAiApps() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) => const FreeAiHubScreen()));
  void _openOwnedChats() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      AccountWorkspaceScreen(controller: widget.controller)));

  String _runTitle(Map<String, dynamic> run) {
    final title = run['sessionTitle']?.toString() ??
      run['projectTitle']?.toString();
    if (title != null && title.trim().isNotEmpty) return title;
    switch (run['kind']?.toString()) {
      case 'codex_cli_turn': return 'Codex CLI turn';
      case 'codex_cloud_submit': return 'Codex Cloud task';
      case 'claude_agent_turn': return 'Claude Agent SDK run';
      case 'copilot_sdk_turn': return 'GitHub Copilot SDK run';
      case 'vscode_open_file': return 'VS Code file request';
      default: return 'O-AGENT supervised task';
    }
  }

  Widget _statCard(IconData icon, String count, String label, Color tint) =>
    OSurface(padding: const EdgeInsets.all(15), child: Row(children: [
      Container(width: 39, height: 39,
        decoration: BoxDecoration(color: tint.withValues(alpha: .09),
          borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, size: 20, color: tint)),
      const SizedBox(width: 11),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(count, style: TextStyle(fontSize: 23,
            color: OVisual.label(context), fontWeight: FontWeight.w800)),
          Text(label, style: TextStyle(fontSize: 11,
            color: OVisual.muted(context))),
        ])),
    ]));

  Widget _runCard(Map<String, dynamic> run,
      List<Map<String, dynamic>> sessions) {
    final match = sessions.where((s) =>
      s['projectId'] == run['projectId'] &&
      s['sessionId'] == run['sessionId']);
    final session = match.isEmpty ? run : match.first;
    final approvals = remoteList(run['pendingApprovals']);
    final status = run['status']?.toString() ?? 'unknown';
    final exactApproval = approvals.isNotEmpty ||
      status == 'waiting_for_approval';
    return Padding(padding: const EdgeInsets.only(bottom: 10),
      child: OSurface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(CupertinoIcons.chevron_left_slash_chevron_right,
              size: 20, color: OVisual.primary),
            const SizedBox(width: 11),
            Expanded(child: Text(_runTitle(run),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: OVisual.label(context),
                fontSize: 15, fontWeight: FontWeight.w800))),
            const SizedBox(width: 7),
            OStatePill(status),
          ]),
          if (run['promptPreview']?.toString().isNotEmpty == true)
            Padding(padding: const EdgeInsets.only(top: 10),
              child: Text(run['promptPreview'].toString(),
                maxLines: 3, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: OVisual.muted(context),
                  fontSize: 13, height: 1.4))),
          if (run['latestEvent'] != null)
            Padding(padding: const EdgeInsets.only(top: 9),
              child: Text('Latest update · ' +
                (remoteMap(run['latestEvent'])['text']?.toString() ?? ''),
                maxLines: 2, overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11,
                  color: OVisual.muted(context)))),
          if (approvals.isNotEmpty) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(approvals.length.toString() +
              ' exact action approval(s) awaiting review',
              style: const TextStyle(color: OVisual.gold,
                fontSize: 12, fontWeight: FontWeight.w700))),
          const SizedBox(height: 11),
          if (run['canOpenVscodeTask'] == true)
            SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
              onPressed: () => _openVsCode(run['id']?.toString()),
              icon: const Icon(CupertinoIcons.folder_open, size: 18),
              label: const Text('Inspect VS Code open request')))
          else if (run['canOpenBridgeTask'] == true)
            SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
              onPressed: () => _openBridge(run['id']?.toString()),
              icon: Icon(exactApproval ? CupertinoIcons.checkmark_shield
                : CupertinoIcons.doc_text, size: 18),
              label: Text(exactApproval ? 'Review provider permissions'
                : 'Inspect live SDK run')))
          else if (run['canOpenSession'] == true)
            SizedBox(width: double.infinity, child: FilledButton.tonalIcon(
              onPressed: () => _openCodex(session, taskId: run['id']?.toString()),
              icon: Icon(exactApproval ? CupertinoIcons.checkmark_shield
                : CupertinoIcons.doc_text, size: 18),
              label: Text(exactApproval ? 'Review exact approval'
                : 'Inspect real activity'),
            ))
          else Text('Provider status only. This is not an attached browser session.',
            style: TextStyle(color: OVisual.muted(context), fontSize: 11)),
        ],
      )));
  }
  Widget _sessionCard(Map<String, dynamic> session) {
    final ready = session['syncFresh'] == true &&
      session['workerOnline'] == true;
    final project = session['projectTitle']?.toString() ?? 'Codex project';
    final preview = (session['title']?.toString() ?? '').trim();
    final projectLabel = project.isNotEmpty ? project : 'Codex project';
    return Padding(padding: const EdgeInsets.only(bottom: 10),
      child: OSurface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(projectLabel,
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: OVisual.label(context),
                fontWeight: FontWeight.w700, fontSize: 15))),
            OStatePill(ready ? 'online' : 'offline',
              label: ready ? 'Available' : 'Unavailable'),
          ]),
          const SizedBox(height: 6),
          Text(preview.isEmpty ? 'Saved Codex conversation'
            : 'Last conversation: ' + preview,
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: OVisual.muted(context),
              fontSize: 12, height: 1.45)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: ready ? () => _openCodex(session) : null,
              icon: const Icon(CupertinoIcons.paperplane, size: 17),
              label: const Text('Open conversation')),
          ),
        ])));
  }
  @override
  Widget build(BuildContext context) {
    final sessions = remoteList(data?['sessions']);
    final runs = remoteList(data?['runs']);
    final active = runs.where((r) => const {
      'waiting_for_approval','queued','running'
    }.contains(r['status'])).toList();
    final urgent = active.where((r) =>
      r['status'] == 'waiting_for_approval' ||
      remoteList(r['pendingApprovals']).isNotEmpty).toList();
    final recent = runs.where((r) => !active.contains(r)).take(12).toList();
    final machines = remoteList(data?['machines']);
    final sources = remoteList(data?['sources']);
    final cards = filter == 'approvals' ? urgent :
      filter == 'active' ? active : [...active, ...recent];
    return Scaffold(
      backgroundColor: OVisual.canvas(context),
      appBar: AppBar(title: const Text('Remote'),
        actions: [
          IconButton(tooltip: 'Refresh',
            onPressed: _refresh, icon: const Icon(CupertinoIcons.refresh)),
          IconButton(tooltip: 'All projects',
            onPressed: _openProjects, icon: const Icon(CupertinoIcons.folder)),
        ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 790),
        child: RefreshIndicator(onRefresh: _refresh,
          child: ListView(physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(19, 12, 19, 44),
            children: [
              const OScreenTitle(
                eyebrow: 'Your control center',
                title: 'Your projects.\nIn your pocket.',
                subtitle: 'Review supervised coding runs, real provider '
                  'conversations, workspace changes, and approvals.'),
              const SizedBox(height: 19),
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 300;
                final tiles = [
                  _statCard(CupertinoIcons.waveform_path_ecg,
                    (data?['activeRuns']?.toString() ?? '—'), 'Active runs',
                    OVisual.primary),
                  _statCard(CupertinoIcons.checkmark_shield,
                    (data?['pendingApprovals']?.toString() ?? '—'),
                    'Needs review', OVisual.gold),
                ];
                return wide
                  ? Row(children: [
                      Expanded(child: tiles[0]), const SizedBox(width: 11),
                      Expanded(child: tiles[1]),
                    ])
                  : Column(children: [tiles[0], const SizedBox(height: 10), tiles[1]]);
              }),
              if (data == null && loading)
                const Padding(padding: EdgeInsets.only(top: 13),
                  child: OLoadingState()),
              if (error != null) Padding(
                padding: const EdgeInsets.only(top: 13),
                child: OSurface(tint: const Color(0xFFFFF2F2),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(error!, style: const TextStyle(
                        color: Color(0xFFB34E52), fontSize: 12)),
                      TextButton(onPressed: _refresh, child: const Text('Retry')),
                    ]))),
              OSectionTitle('Live desktop connection',
                action: 'View screen', onAction: _openScreen),
              OSurface(child: Row(children: [
                Icon(CupertinoIcons.desktopcomputer,
                  color: OVisual.primary, size: 23),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment:
                  CrossAxisAlignment.start, children: [
                    Text(remoteMap(data?['screenStreaming'])['fresh'] == true
                      ? 'Receiving laptop frames'
                      : 'Screen is not currently sharing live frames',
                      style: TextStyle(fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: OVisual.label(context))),
                    const SizedBox(height: 5),
                    Text(remoteMap(remoteMap(data?['screenStreaming'])['input'])['paired'] == true
                      ? 'Windows pointer and keyboard paired'
                      : 'Desktop input is not paired',
                      style: TextStyle(fontSize: 12,
                        color: OVisual.muted(context))),
                  ])),
                IconButton(onPressed: _openScreen,
                  icon: const Icon(CupertinoIcons.arrow_up_right_square)),
              ])),
              const OSectionTitle('My Codex conversations'),
              if (sessions.isEmpty && data != null)
                const OEmptyState(icon: CupertinoIcons.square_stack,
                  title: 'No conversations found yet',
                  message: 'Sign in to Codex on your laptop, create a '
                    'conversation, and enable local sync in CONFIGURE-PROJECTS.cmd.'),
              for (final session in sessions.take(4)) _sessionCard(session),
              if (sessions.length > 4) Padding(
                padding: const EdgeInsets.only(top: 5, bottom: 8),
                child: TextButton.icon(
                  onPressed: _openProjects,
                  icon: const Icon(CupertinoIcons.square_stack, size: 17),
                  label: Text('Browse all ${sessions.length} conversations'),
                )),

              const OSectionTitle('Real AI conversations'),
              OIconTile(icon: CupertinoIcons.chat_bubble_2_fill,
                title: 'O-AGENT provider chats',
                subtitle: 'Open conversations generated through your own '
                  'OpenAI, Anthropic or Gemini API connections. This does '
                  'not import private ChatGPT or other website chats.',
                onTap: _openOwnedChats, color: OVisual.mint),
              const OSectionTitle('Start here'),
              OIconTile(icon: CupertinoIcons.folder_fill,
                title: 'My projects',
                subtitle: 'Browse real coding projects and saved conversations',
                onTap: _openProjects, color: OVisual.mint),
              const SizedBox(height: 10),
              OIconTile(icon: CupertinoIcons.desktopcomputer,
                title: 'Control laptop screen',
                subtitle: 'Open the live desktop directly. Once the laptop '
                  'has been trusted locally, tap Control to type, click '
                  'and send prompts from your phone.',
                onTap: _openScreen, color: OVisual.primary),
              const SizedBox(height: 9),
              OIconTile(icon: CupertinoIcons.settings,
                title: 'Screen-sharing setup & stop',
                subtitle: 'Select what the laptop shares, inspect capture '
                  'status or revoke screen sharing.',
                onTap: _openScreenSetup, color: OVisual.mint),
              const SizedBox(height: 10),
              OIconTile(icon: CupertinoIcons.square_stack_3d_up,
                title: 'VS Code live file changes',
                subtitle: 'Real Git changes and unsaved filenames from a '
                  'trusted editor companion, not simulated code history.',
                onTap: () => _openVsCode(), color: OVisual.mint),
              const SizedBox(height: 10),
              OIconTile(icon: CupertinoIcons.globe,
                title: 'AI website bookmarks (not integrations)',
                subtitle: 'Convenient browser links only. They do not sync '
                  'ChatGPT, Grok, Claude or other existing chats.',
                onTap: _openAiApps, color: OVisual.primary),
              ExpansionTile(
                title: const Text('Connect more AI tools (optional)',
                  style: TextStyle(fontWeight: FontWeight.w700)),
                subtitle: const Text('Cursor Cloud and official Claude/Copilot '
                  'SDK runtimes require individual sign-in and enrollment.',
                  style: TextStyle(fontSize: 11)),
                childrenPadding: const EdgeInsets.symmetric(
                  horizontal: 9, vertical: 8),
                children: [
                  OIconTile(icon: CupertinoIcons.cloud_fill,
                    title: 'Cursor Cloud Agents',
                    subtitle: 'Requires provider access; not needed to '
                      'test your Codex laptop connection',
                    onTap: _openCursor, color: OVisual.primary),
                  const SizedBox(height: 8),
                  OIconTile(icon: CupertinoIcons.chevron_left_slash_chevron_right,
                    title: 'Claude & GitHub Copilot',
                    subtitle: 'Use a signed-in agent SDK on your laptop',
                    onTap: () => _openBridge(), color: OVisual.primary),
                ],
              ),
              OSectionTitle('Laptop connection',
                action: 'Refresh', onAction: _refresh),
              if (machines.isEmpty) const OEmptyState(
                icon: CupertinoIcons.desktopcomputer,
                title: 'Laptop worker not connected',
                message: 'Start O-AGENT.cmd on your enrolled Windows device '
                  'to supervise its saved Codex CLI sessions.'),
              for (final machine in machines)
                Padding(padding: const EdgeInsets.only(bottom: 9),
                  child: OIconTile(icon: CupertinoIcons.desktopcomputer,
                    title: machine['name']?.toString() ?? 'Enrolled laptop',
                    subtitle: (machine['id']?.toString() ?? '') + ' · ' +
                      (machine['status']?.toString() ?? ''),
                    trailing: OStatePill(machine['status']?.toString() ?? 'offline'))),
              OSectionTitle('Supervised coding agent activity',
                action: 'Refresh', onAction: _refresh),
              Padding(padding: const EdgeInsets.only(bottom: 12),
                child: CupertinoSlidingSegmentedControl<String>(
                  groupValue: filter,
                  children: const {
                    'all': Padding(padding: EdgeInsets.symmetric(
                      horizontal: 9, vertical: 8), child: Text('All')),
                    'active': Padding(padding: EdgeInsets.symmetric(
                      horizontal: 9, vertical: 8), child: Text('Running')),
                    'approvals': Padding(padding: EdgeInsets.symmetric(
                      horizontal: 9, vertical: 8), child: Text('Approvals')),
                  },
                  onValueChanged: (next) {
                    if (next != null) setState(() => filter = next);
                  })),
              if (cards.isEmpty && data != null)
                OEmptyState(
                  icon: filter == 'approvals'
                    ? CupertinoIcons.checkmark_shield
                    : CupertinoIcons.waveform_path,
                  title: filter == 'approvals'
                    ? 'No pending approvals'
                    : filter == 'active' ? 'No active runs' : 'No recent coding agent runs',
                  message: 'Only actual O-AGENT-supervised runs appear here. '
                    'Open a saved session to submit an explicit, approval-gated turn.'),
              for (final r in cards) _runCard(r, sessions),
              ExpansionTile(
                title: const Text('Provider connection status',
                  style: TextStyle(fontWeight: FontWeight.w600)),
                initiallyExpanded: false,
                children: [
              OSurface(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Verified provider capabilities',
                    style: TextStyle(fontWeight: FontWeight.w800,
                      color: OVisual.label(context), fontSize: 15)),
                  const SizedBox(height: 7),
                  Text('Unsupported providers are not represented as live connections.',
                    style: TextStyle(color: OVisual.muted(context),
                      fontSize: 12)),
                  const SizedBox(height: 10),
                  for (final source in sources.where((s) => const {
                    'codex_cli','codex_cloud','copilot_sdk','claude_code',
                    'cursor','vscode','chatgpt_work','openai_api',
                    'anthropic_api','gemini_api',
                  }.contains(s['id']))) ...[
                    const Divider(height: 18),
                    Row(children: [
                      Expanded(child: Text(source['label']?.toString() ?? '',
                        maxLines: 2, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: OVisual.label(context),
                          fontSize: 13, fontWeight: FontWeight.w600))),
                      OStatePill(source['status']?.toString() ?? 'unknown'),
                    ]),
                    const SizedBox(height: 4),
                    Text(source['limitation']?.toString() ?? '',
                      style: TextStyle(fontSize: 11, height: 1.45,
                        color: OVisual.muted(context))),
                  ],
                ])),
                ],
              ),
              const OSectionTitle('Alerts and approvals'),
              OIconTile(icon: CupertinoIcons.bell_fill,
                title: 'Push notifications and device permissions',
                subtitle: 'Opt into alerts for real agent approvals and '
                  'status changes. Firebase setup required.',
                onTap: _openPush, color: OVisual.primary),
              const SizedBox(height: 9),
            ],
          )),
      ))),
    );
  }
}

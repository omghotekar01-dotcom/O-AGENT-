import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import 'codex_session.dart';
import 'agent_sdk_bridge.dart';
import 'screen_preview.dart';
import 'vscode_remote.dart';
import 'cursor_cloud.dart';
import 'ios_components.dart';
import 'projects.dart';

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
      if (mounted) setState(() => error = e.toString());
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
  void _openScreen() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      ScreenPreviewScreen(controller: widget.controller)));
  void _openCursor() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      CursorCloudScreen(controller: widget.controller)));
  void _openProjects() => Navigator.push(context,
    MaterialPageRoute<void>(builder: (_) =>
      ProjectHubScreen(controller: widget.controller)));

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
            Expanded(child: Text(run['sessionTitle']?.toString() ??
                run['projectTitle']?.toString() ??
                (run['kind'] == 'codex_cli_turn'
                  ? 'Codex CLI supervised turn' : 'Codex Cloud task'),
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
    return Padding(padding: const EdgeInsets.only(bottom: 10),
      child: OSurface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(session['title']?.toString() ?? 'Saved Codex session',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: OVisual.label(context),
                fontWeight: FontWeight.w700, fontSize: 15))),
            OStatePill(ready ? 'online' : 'offline',
              label: ready ? 'Available' : 'Unavailable'),
          ]),
          const SizedBox(height: 6),
          Text(session['cwd']?.toString() ?? '',
            maxLines: 2, overflow: TextOverflow.ellipsis,
            style: TextStyle(color: OVisual.muted(context),
              fontSize: 11, height: 1.45)),
          const SizedBox(height: 12),
          SizedBox(width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: ready ? () => _openCodex(session) : null,
              icon: const Icon(CupertinoIcons.paperplane, size: 17),
              label: const Text('Open and prompt Codex')),
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
                title: 'Stay in control.\nFrom anywhere.',
                subtitle: 'Supervise real coding-agent sessions, examine work '
                  'and handle approval requests without being at your desk.'),
              const SizedBox(height: 19),
              LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth >= 470;
                final tiles = [
                  _statCard(CupertinoIcons.waveform_path_ecg,
                    (data?['activeRuns'] ?? 0).toString(), 'Active runs',
                    OVisual.primary),
                  _statCard(CupertinoIcons.checkmark_shield,
                    (data?['pendingApprovals'] ?? 0).toString(),
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
              const OSectionTitle('Your workspaces'),
              OIconTile(icon: CupertinoIcons.cloud_fill,
                title: 'Cursor Cloud Agents',
                subtitle: 'Official hosted agent API · independently '
                  'authenticated using your own Cursor key',
                onTap: _openCursor, color: OVisual.primary),
              const SizedBox(height: 10),
              const SizedBox(height: 10),
              OIconTile(icon: CupertinoIcons.chevron_left_slash_chevron_right,
                title: 'Claude Agent SDK & GitHub Copilot',
                subtitle: 'Run officially authenticated SDK sessions on '
                  'a trusted laptop, with exact owner approvals',
                onTap: () => _openBridge(), color: OVisual.primary),
              const SizedBox(height: 10),
              OIconTile(icon: CupertinoIcons.square_stack_3d_up,
                title: 'VS Code workspace companion',
                subtitle: 'Opt-in editor extension, owner-approved '
                  'file navigation and separate local confirmation',
                onTap: () => _openVsCode(), color: OVisual.primary),
              const SizedBox(height: 10),
              OIconTile(icon: CupertinoIcons.folder_fill,
                title: 'Projects and repositories',
                subtitle: 'Browse verified projects, external work and Codex sessions',
                onTap: _openProjects, color: OVisual.mint),
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
              OSectionTitle('Codex activity',
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
                    : filter == 'active' ? 'No active runs' : 'No recent Codex runs',
                  message: 'Only actual O-AGENT-supervised runs appear here. '
                    'Open a saved session to submit an explicit, approval-gated turn.'),
              for (final r in cards) _runCard(r, sessions),
              const OSectionTitle('Saved Codex sessions'),
              if (sessions.isEmpty && data != null)
                const OEmptyState(icon: CupertinoIcons.square_stack,
                  title: 'No sessions synced yet',
                  message: 'On Windows, sign in to Codex CLI, create a saved '
                    'project session, and enable local sync in CONFIGURE-PROJECTS.cmd.'),
              for (final session in sessions) _sessionCard(session),
              const OSectionTitle('Integration availability'),
              OSurface(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Source capabilities',
                    style: TextStyle(fontWeight: FontWeight.w800,
                      color: OVisual.label(context), fontSize: 15)),
                  const SizedBox(height: 7),
                  Text('Unsupported providers are not represented as live connections.',
                    style: TextStyle(color: OVisual.muted(context),
                      fontSize: 12)),
                  const SizedBox(height: 10),
                  for (final source in sources.where((s) => const {
                    'codex_cli','codex_cloud','copilot_sdk','claude_code',
                    'cursor','vscode','chatgpt_work',
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
              const OSectionTitle('Desktop and browser viewing'),
              OIconTile(icon: CupertinoIcons.desktopcomputer,
                title: 'View consented laptop preview',
                subtitle: 'See temporary real screen or window frames selected '
                  'by the laptop user. Owner-only, view-only, no mouse control.',
                onTap: _openScreen, color: OVisual.primary),
              const SizedBox(height: 9),
              const OIconTile(icon: CupertinoIcons.shield_lefthalf_fill,
                title: 'Capture requires explicit human consent',
                subtitle: 'Laptop browser selection and a visible sharing '
                  'indicator are required. No silent desktop takeover.'),
            ],
          )),
      ))),
    );
  }
}

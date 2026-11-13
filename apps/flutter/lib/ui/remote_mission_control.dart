import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import 'codex_session.dart';

Map<String, dynamic> remoteMap(Object? v) => v is Map
  ? Map<String, dynamic>.from(v) : <String, dynamic>{};
List<Map<String, dynamic>> remoteList(Object? v) => v is List
  ? v.map(remoteMap).toList() : <Map<String, dynamic>>[];

/// Owner-only view of real laptop Codex sessions, tasks and pending approvals.
/// This makes no claim to capture an existing ChatGPT website or IDE screen.
class RemoteMissionControlScreen extends StatefulWidget {
  const RemoteMissionControlScreen({super.key, required this.controller});
  final ControlController controller;
  @override
  State<RemoteMissionControlScreen> createState() => _RemoteMissionControlState();
}
class _RemoteMissionControlState extends State<RemoteMissionControlScreen>
    with WidgetsBindingObserver {
  Timer? poller;
  Map<String, dynamic>? data;
  String? error;
  bool loading = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
    poller = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }
  @override
  void dispose() {
    poller?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  Future<void> _refresh() async {
    if (!mounted || loading) return;
    final api = widget.controller.client;
    if (api == null) {
      setState(() => error = 'Owner backend is disconnected');
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
  void _open(Map<String, dynamic> session, {String? taskId}) {
    final project = session['projectId']?.toString() ?? '';
    final id = session['sessionId']?.toString() ?? '';
    if (project.isEmpty || id.isEmpty) return;
    Navigator.push(context, MaterialPageRoute<void>(builder: (_) =>
      CodexSessionScreen(
        controller: widget.controller,
        projectId: project,
        sessionId: id,
        sessionTitle: session['title']?.toString() ??
          session['sessionTitle']?.toString() ?? 'Saved Codex session',
        cwd: session['cwd']?.toString() ?? '',
        initialTaskId: taskId,
      )));
  }
  Widget _card(Widget child) => Card(
    elevation: 0, color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(17),
      side: const BorderSide(color: Color(0xFFE3E2E0))),
    child: Padding(padding: const EdgeInsets.all(16), child: child));
  Widget _heading(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(0, 19, 0, 9),
    child: Text(label, style: const TextStyle(
      fontSize: 18, fontWeight: FontWeight.w800)));
  Widget _run(Map<String, dynamic> run, List<Map<String, dynamic>> sessions) {
    final matching = sessions.where((s) =>
      s['projectId'] == run['projectId'] &&
      s['sessionId'] == run['sessionId']);
    final session = matching.isEmpty ? run : matching.first;
    final approvals = remoteList(run['pendingApprovals']);
    return _card(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(run['kind'] == 'codex_cli_turn' ? 'Codex CLI run' : 'Codex Cloud task',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 5),
      Text((run['status']?.toString() ?? '') + ' · ' +
        (run['workerId']?.toString() ?? ''), style: const TextStyle(
          fontSize: 11, color: Colors.grey)),
      if (run['promptPreview']?.toString().isNotEmpty == true)
        Padding(padding: const EdgeInsets.only(top: 7),
          child: Text(run['promptPreview'].toString(),
            maxLines: 3, overflow: TextOverflow.ellipsis)),
      if (run['latestEvent'] != null)
        Padding(padding: const EdgeInsets.only(top: 7),
          child: Text('Last actual event: ' +
            (remoteMap(run['latestEvent'])['text']?.toString() ?? ''),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
            maxLines: 3, overflow: TextOverflow.ellipsis)),
      if (approvals.isNotEmpty)
        Padding(padding: const EdgeInsets.only(top: 7),
          child: Text(approvals.length.toString() +
            ' live permission request(s) awaiting your decision',
            style: const TextStyle(color: Color(0xFFB46B50),
              fontWeight: FontWeight.w700))),
      const SizedBox(height: 10),
      if (run['canOpenSession'] == true)
        FilledButton.tonalIcon(
          icon: const Icon(Icons.visibility_outlined),
          label: Text(approvals.isNotEmpty ||
            run['status'] == 'waiting_for_approval'
              ? 'Review exact request' : 'View actual output'),
          onPressed: () => _open(session, taskId: run['id']?.toString()))
      else const Text('Cloud task status only; existing provider session '
        'takeover is not available.', style: TextStyle(
          fontSize: 11, color: Colors.grey)),
    ]));
  }
  @override
  Widget build(BuildContext context) {
    final sessions = remoteList(data?['sessions']);
    final runs = remoteList(data?['runs']);
    final active = runs.where((r) =>
      const {'waiting_for_approval','queued','running'}
        .contains(r['status'])).toList();
    final recent = runs.where((r) => !active.contains(r)).take(10).toList();
    final machines = remoteList(data?['machines']);
    final sources = remoteList(data?['sources']);
    return Scaffold(
      appBar: AppBar(title: const Text('Remote mission control'),
        actions: [
          IconButton(onPressed: _refresh, tooltip: 'Refresh real state',
            icon: const Icon(Icons.sync_rounded)),
        ]),
      body: SafeArea(child: ListView(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 28),
        children: [
          const Text('REAL CODING AGENTS',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800,
              letterSpacing: 1.5, color: Color(0xFF6654A3))),
          const SizedBox(height: 8),
          const Text('Work from anywhere.',
            style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          const Text('See actual Codex CLI projects, running turns, output '
            'and permission requests. Refreshes every 3 seconds while open. '
            'No separate OpenAI API chatbot key is required for Codex CLI.',
            style: TextStyle(fontSize: 12, color: Colors.grey, height: 1.5)),
          if (data == null && loading) const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: LinearProgressIndicator(minHeight: 2)),
          if (error != null) _card(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(error!, style: const TextStyle(color: Colors.red)),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ])),
          if (data != null) ...[
            const SizedBox(height: 13),
            _card(Row(children: [
              const Icon(Icons.play_circle_outline),
              const SizedBox(width: 8),
              Text('Active runs: ' + (data!['activeRuns']?.toString() ?? '0')),
              const Spacer(),
              const Icon(Icons.verified_user_outlined),
              const SizedBox(width: 7),
              Text('Approvals: ' + (data!['pendingApprovals']?.toString() ?? '0')),
            ])),
            _heading('Connected laptop workers'),
            if (machines.isEmpty) _card(const Text('No registered laptop. '
              'Start O-AGENT.cmd on Windows.')),
            for (final m in machines)
              _card(Row(children: [
                Icon(m['status'] == 'online' ? Icons.laptop_rounded
                  : Icons.laptop_outlined, color: m['status'] == 'online'
                    ? const Color(0xFF437963) : Colors.orange),
                const SizedBox(width: 10),
                Expanded(child: Text((m['name']?.toString() ?? 'Laptop') +
                  ' · ' + (m['status']?.toString() ?? 'unknown'))),
              ])),
            _heading('Active Codex runs & approvals'),
            if (active.isEmpty)
              _card(const Text('No run is active. Select a genuine '
                'Codex session below to start an approval-gated turn.')),
            for (final run in active) _run(run, sessions),
            _heading('Saved Codex CLI / IDE sessions'),
            if (sessions.isEmpty)
              _card(const Text('No sessions synced. On your laptop, install '
                'and sign in to Codex CLI, create a real project session, '
                'then use CONFIGURE-PROJECTS.cmd to enable local Codex sync '
                'and restart O-AGENT.cmd.')),
            for (final s in sessions)
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(s['title']?.toString() ?? 'Session',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 5),
                  Text(s['cwd']?.toString() ?? '',
                    style: const TextStyle(color: Colors.grey, fontSize: 11)),
                  const SizedBox(height: 5),
                  Text(s['syncFresh'] == true
                    ? 'Saved session; metadata recently synced'
                    : 'Stale metadata; check worker',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  const SizedBox(height: 9),
                  FilledButton.tonalIcon(
                    onPressed: s['syncFresh'] == true &&
                      s['workerOnline'] == true ? () => _open(s) : null,
                    icon: const Icon(Icons.send_rounded),
                    label: const Text('Prompt supervised Codex session')),
                ])),
            _heading('Recent task history'),
            if (recent.isEmpty) _card(const Text('No past Codex runs.')),
            for (final run in recent) _run(run, sessions),
            _heading('Provider integration status'),
            for (final source in sources.where((s) =>
              const {'codex_cli','codex_cloud','copilot_sdk','claude_code',
                'cursor','vscode','chatgpt_work'}.contains(s['id'])))
              _card(Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text((source['label']?.toString() ?? '') + ' · ' +
                    (source['status']?.toString() ?? ''),
                    style: const TextStyle(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 5),
                  Text(source['limitation']?.toString() ?? '',
                    style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ])),
            _heading('Screen and browser viewing'),
            _card(const Text('Not available yet. A user-consented '
              'Windows streaming companion is needed. Agent log output '
              'is not a live screenshot or independent browser session.')),
          ],
        ],
      )),
    );
  }
}

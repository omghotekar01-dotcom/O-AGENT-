import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import 'ios_components.dart';

Map<String, dynamic> bridgeMap(Object? x) =>
  x is Map ? Map<String, dynamic>.from(x) : <String, dynamic>{};
List<Map<String, dynamic>> bridgeList(Object? x) =>
  x is List ? x.whereType<Map>().map(bridgeMap).toList() : [];
String bridgeText(Object? x) => x?.toString() ?? '';

/// Explicitly enrolled, SDK-owned local sessions with owner approval.
class AgentSdkBridgeScreen extends StatefulWidget {
  const AgentSdkBridgeScreen({super.key, required this.controller, this.taskId,
    this.resumeSession, this.resumeKind, this.resumeWorkerId, this.resumeCwd});
  final ControlController controller;
  final String? taskId;
  final String? resumeSession, resumeKind, resumeWorkerId, resumeCwd;
  @override State<AgentSdkBridgeScreen> createState() => _SdkBridgeState();
}
class _SdkBridgeState extends State<AgentSdkBridgeScreen> {
  final cwd = TextEditingController();
  final prompt = TextEditingController();
  final resume = TextEditingController();
  List<Map<String, dynamic>> workers = [];
  Map<String, dynamic>? task;
  String provider = 'claude_agent_turn', mode = 'read_only';
  String? worker, taskId, error;
  bool busy = false;
  Timer? timer;
  @override void initState() {
    super.initState();
    taskId = widget.taskId;
    if (widget.resumeSession != null) {
      resume.text = widget.resumeSession!;
      if (const {'claude_agent_turn', 'copilot_sdk_turn'}
          .contains(widget.resumeKind)) {
        provider = widget.resumeKind!;
      }
      worker = widget.resumeWorkerId;
      cwd.text = widget.resumeCwd ?? '';
    }
    _reload();
    timer = Timer.periodic(const Duration(seconds: 4), (_) => _reload());
  }
  @override void dispose() {
    timer?.cancel();
    cwd.dispose(); prompt.dispose(); resume.dispose();
    super.dispose();
  }
  List<Map<String, dynamic>> get enrolled => workers.where((w) =>
    w['status'] == 'online' && w['capabilities'] is List &&
    (w['capabilities'] as List).contains(provider)).toList();
  Future<void> _reload() async {
    if (busy || !mounted) return;
    final api = widget.controller.client;
    if (api == null) return;
    try {
      final status = await api.remoteAgentOverview();
      final next = taskId == null ? null : await api.taskDetail(taskId!);
      if (!mounted || widget.controller.client != api) return;
      setState(() {
        workers = bridgeList(status['machines']);
        if (next != null) task = next;
        // Never switch a resumed session onto another worker automatically.
        if (widget.resumeSession == null &&
            !enrolled.any((w) => w['id'] == worker)) {
          worker = enrolled.isNotEmpty ? bridgeText(enrolled.first['id']) : null;
        }
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }
  Future<bool> _confirm(String title, String details, String action) async =>
    await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: SelectableText(details)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ])) == true;
  Future<void> _send() async {
    if (busy || worker == null || cwd.text.trim().isEmpty ||
        prompt.text.trim().isEmpty ||
        !enrolled.any((w) => w['id'] == worker)) return;
    final details = 'Agent: ' + provider + '\nMachine: ' + worker! +
      '\nFolder: ' + cwd.text.trim() + '\nPermission mode: ' + mode +
      '\nSDK session: ' + (resume.text.trim().isEmpty
        ? 'new session' : resume.text.trim()) +
      '\n\nInstruction:\n' + prompt.text.trim() +
      '\n\nA second owner approval is required before execution.';
    if (!await _confirm('Request a supervised agent turn?',
        details, 'Create approval request') || !mounted) return;
    setState(() => busy = true);
    try {
      final next = await widget.controller.client!.createSupervisedAgentTurn(
        workerId: worker!, providerKind: provider, cwd: cwd.text.trim(),
        prompt: prompt.text.trim(), mode: mode, sessionId: resume.text.trim());
      if (mounted) setState(() { task = next; taskId = bridgeText(next['id']); });
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> _approveTurn(bool approve) async {
    if (taskId == null || busy) return;
    final p = bridgeMap(task?['parameters']);
    final text = 'Worker: ' + bridgeText(task?['workerId']) +
      '\nDirectory: ' + bridgeText(p['cwd']) +
      '\nMode: ' + bridgeText(p['mode']) +
      '\n\nExact instruction:\n' + bridgeText(p['prompt']);
    if (!await _confirm('Review exact provider turn', text,
        approve ? 'Approve turn' : 'Reject turn') || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.controller.client!.decide(taskId!, approve: approve);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
    await _reload();
  }
  Future<void> _approveTool(Map<String, dynamic> item, bool approve) async {
    if (taskId == null || busy) return;
    if (!await _confirm('Exact provider tool permission',
        bridgeText(item['description']) +
        '\n\nOne-time decision only. No blanket access.',
        approve ? 'Approve once' : 'Deny') || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.controller.client!.decideCodexAction(
        taskId: taskId!, approvalId: bridgeText(item['id']), approve: approve);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
    await _reload();
  }
  Widget _taskStatus() {
    final state = bridgeText(task?['status']);
    final approvals = bridgeMap(task?['approvals']).values
      .map(bridgeMap).where((x) => x['state'] == 'pending').toList();
    final result = bridgeMap(task?['result']);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const OSectionTitle('Supervised run'),
      OSurface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(bridgeText(task?['kind']),
              style: const TextStyle(fontWeight: FontWeight.w800))),
            OStatePill(state),
          ]),
          const SizedBox(height: 12),
          SelectableText(bridgeText(bridgeMap(task?['parameters'])['prompt'])),
          if (state == 'waiting_for_approval')
            Padding(padding: const EdgeInsets.only(top: 12),
              child: Row(children: [
                Expanded(child: OutlinedButton(onPressed: busy
                  ? null : () => _approveTurn(false), child: const Text('Reject'))),
                const SizedBox(width: 8),
                Expanded(child: FilledButton(onPressed: busy
                  ? null : () => _approveTurn(true), child: const Text('Approve'))),
              ])),
        ])),
      for (final item in approvals) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: OSurface(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const OStatePill('waiting_for_approval',
              label: 'Exact tool permission required'),
            const SizedBox(height: 11),
            SelectableText(bridgeText(item['description'])),
            const SizedBox(height: 11),
            Row(children: [
              Expanded(child: OutlinedButton(onPressed: busy
                ? null : () => _approveTool(item, false),
                child: const Text('Deny'))),
              const SizedBox(width: 8),
              Expanded(child: FilledButton(onPressed: busy
                ? null : () => _approveTool(item, true),
                child: const Text('Approve once'))),
            ]),
          ]))),
      const OSectionTitle('Actual provider events'),
      OSurface(child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (final event in bridgeList(task?['updates']).reversed.take(60)) ...[
            Text(bridgeText(event['type']), style: const TextStyle(
              color: OVisual.primary, fontWeight: FontWeight.w800, fontSize: 11)),
            const SizedBox(height: 4),
            SelectableText(bridgeText(event['text'])),
            const Divider(height: 17),
          ],
          if (result['response'] != null) ...[
            const Text('Final response', style: TextStyle(
              fontWeight: FontWeight.w800)),
            SelectableText(bridgeText(result['response'])),
          ],
          if (result['sessionId'] != null) ...[
            const SizedBox(height: 9),
            const Text('SDK session ID'),
            SelectableText(bridgeText(result['sessionId'])),
          ],
          if (task?['error'] != null)
            Text(bridgeText(task?['error']), style: const TextStyle(
              color: OVisual.rose)),
        ])),
    ]);
  }
  @override Widget build(BuildContext context) => Scaffold(
    backgroundColor: OVisual.canvas(context),
    appBar: AppBar(title: const Text('Agent SDK bridges'), actions: [
      IconButton(onPressed: _reload, icon: const Icon(CupertinoIcons.refresh)),
    ]),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 720),
      child: ListView(padding: const EdgeInsets.fromLTRB(19, 14, 19, 32),
        children: [
          const OScreenTitle(eyebrow: 'Enrolled agent runtimes',
            title: 'Work with your agents.',
            subtitle: 'Supervise Claude Agent SDK or GitHub Copilot SDK '
              'sessions on a trusted, online worker. Not a browser takeover.'),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 13),
            child: OSurface(child: Text(error!,
              style: const TextStyle(color: OVisual.rose)))),
          if (taskId == null) ...[
            const OSectionTitle('Start a supervised turn'),
            OSurface(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                SegmentedButton<String>(segments: const [
                  ButtonSegment(value: 'claude_agent_turn', label: Text('Claude')),
                  ButtonSegment(value: 'copilot_sdk_turn', label: Text('Copilot')),
                ], selected: {provider},
                  onSelectionChanged: widget.resumeSession != null ? null : (v) =>
                    setState(() { provider = v.first; worker = null; })),
                const SizedBox(height: 12),
                if (enrolled.isEmpty) const Text('No enrolled online worker. '
                  'Install and sign in to the official SDK, then enable its '
                  'O-AGENT worker capability.'),
                if (widget.resumeSession != null &&
                    !enrolled.any((w) => w['id'] == worker))
                  const Padding(padding: EdgeInsets.only(top: 8),
                    child: Text('The original session worker is offline or '
                      'does not advertise this SDK. Resume is disabled until '
                      'that same worker reconnects.',
                      style: TextStyle(color: OVisual.rose))),
                if (enrolled.isNotEmpty) DropdownButtonFormField<String>(
                  initialValue: enrolled.any((w) => w['id'] == worker)
                    ? worker : null,
                  isExpanded: true, decoration: const InputDecoration(
                    labelText: 'Online enrolled machine'),
                  items: enrolled.map((w) => DropdownMenuItem(
                    value: bridgeText(w['id']),
                    child: Text(bridgeText(w['name'])))).toList(),
                  onChanged: widget.resumeSession != null ? null :
                    (v) => setState(() => worker = v)),
                const SizedBox(height: 12),
                TextField(controller: cwd, decoration: const InputDecoration(
                  labelText: 'Existing enrolled workspace folder')),
                const SizedBox(height: 10),
                TextField(controller: resume,
                  readOnly: widget.resumeSession != null,
                  decoration: const InputDecoration(
                    labelText: 'SDK session ID to resume (optional)')),
                const SizedBox(height: 10),
                TextField(controller: prompt, maxLength: 4000, minLines: 3,
                  maxLines: 6, decoration: const InputDecoration(
                    labelText: 'Exact agent instruction')),
                const SizedBox(height: 10),
                SegmentedButton<String>(segments: const [
                  ButtonSegment(value: 'read_only', label: Text('Read-only')),
                  ButtonSegment(value: 'workspace_write', label: Text('Project edits')),
                ], selected: {mode}, onSelectionChanged: (v) =>
                    setState(() => mode = v.first)),
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: FilledButton.icon(
                  onPressed: busy || worker == null ||
                    !enrolled.any((w) => w['id'] == worker) ? null : _send,
                  icon: const Icon(CupertinoIcons.paperplane, size: 17),
                  label: const Text('Review exact request'))),
              ])),
          ] else _taskStatus(),
          const OSectionTitle('Permission boundary'),
          const OIconTile(icon: CupertinoIcons.shield_lefthalf_fill,
            title: 'Owner approval, each write action',
            subtitle: 'Every turn needs approval. Write-capable operations '
              'require separate, expiring decisions. Unrelated website chats, '
              'unknown tools and unauthorized folders cannot be controlled.'),
        ])),
    )),
  );
}

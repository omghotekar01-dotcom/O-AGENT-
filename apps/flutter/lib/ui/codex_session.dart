import 'dart:async';
import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../theme.dart';
import 'projects.dart';

/// Real, server-authoritative Codex session events and explicit decisions.
/// This does not automate the ChatGPT consumer website.
class CodexSessionScreen extends StatefulWidget {
  const CodexSessionScreen({super.key, required this.controller, required this.projectId,
    required this.sessionId, required this.sessionTitle, required this.cwd});
  final ControlController controller;
  final String projectId, sessionId, sessionTitle, cwd;

  @override
  State<CodexSessionScreen> createState() => _CodexSessionState();
}
class _CodexSessionState extends State<CodexSessionScreen> {
  final composer = TextEditingController();
  Timer? poller;
  Map<String, dynamic>? task;
  String? taskId, error;
  bool busy = false, loading = false;
  String mode = 'read_only';

  @override
  void initState() {
    super.initState();
    for (final t in widget.controller.snapshot?.tasks ?? []) {
      if (t.kind == 'codex_cli_turn' && t.parameters?['sessionId'] == widget.sessionId) {
        taskId = t.id;
        break;
      }
    }
    _refresh();
    poller = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }
  @override
  void dispose() { poller?.cancel(); composer.dispose(); super.dispose(); }
  Future<void> _refresh() async {
    if (taskId == null || loading || !mounted) return;
    loading = true;
    try {
      final data = await widget.controller.client!.taskDetail(taskId!);
      if (mounted) setState(() { task = data; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally { loading = false; }
  }

  Future<bool> _confirm(String title, String content, String action) async =>
    await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: SelectableText(content)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
      ],
    )) == true;

  Future<void> _submit() async {
    final value = composer.text.trim();
    if (busy || value.isEmpty) return;
    final yes = await _confirm('Request a real Codex turn?',
      'Folder: ' + widget.cwd +
      '\n\nMode: ' + mode +
      '\n\nA separate approval is required before execution.' +
      '\n\nRead-only prevents file edits, but Codex may read other files accessible to your Windows account. Project edits permits writing inside the chosen workspace. Network access is disabled by the sandbox.' +
      '\n\nExact prompt:\n' + value, 'Create approval request');
    if (!yes || !mounted) return;
    setState(() => busy = true);
    try {
      final created = await widget.controller.client!.requestCodexLocalTurn(
        projectId: widget.projectId, sessionId: widget.sessionId, prompt: value, mode: mode);
      if (mounted) {
        composer.clear();
        setState(() { taskId = created['id'].toString(); task = created; error = null; });
        await widget.controller.refresh();
        await _refresh();
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Future<void> _decideTurn(bool approve) async {
    if (task == null || busy) return;
    final p = asMap(task!['parameters']);
    final yes = await _confirm(
      approve ? 'Authorize this Codex turn?' : 'Reject this Codex turn?',
      'Project: ' + (p['cwd'] ?? '').toString() +
      '\nMode: ' + (p['mode'] ?? '').toString() +
      '\n\nPrompt:\n' + (p['prompt'] ?? '').toString() +
      '\n\nCodex runs using your existing CLI login, not a ChatGPT website tab.',
      approve ? 'Approve execution' : 'Reject');
    if (!yes || !mounted) return;
    setState(() => busy = true);
    try {
      final ok = await widget.controller.resolveApproval(taskId!, approve);
      if (!ok && mounted) setState(() => error = widget.controller.error ?? 'Approval failed');
      await _refresh();
    } finally { if (mounted) setState(() => busy = false); }
  }
  Future<void> _decideAction(Map<String,dynamic> a, bool approve) async {
    if (busy) return;
    final yes = await _confirm(
      approve ? 'Approve this exact Codex action?' : 'Deny this Codex action?',
      'Type: ' + (a['kind'] ?? '').toString() +
      '\n\nRequested action:\n' + (a['description'] ?? '').toString() +
      '\n\nThis decision applies only to this request. It may run a command or modify files.',
      approve ? 'Authorize action' : 'Deny action');
    if (!yes || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.controller.client!.decideCodexAction(
        taskId: taskId!, approvalId: a['id'].toString(), approve: approve);
      await _refresh();
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
  }

  @override
  Widget build(BuildContext context) {
    final status = task?['status']?.toString() ?? 'not_started';
    final active = const {'waiting_for_approval','queued','running'}.contains(status);
    final approvals = asMap(task?['approvals']).values.map((x) => asMap(x))
      .where((a) => a['state'] == 'pending').toList();
    final events = asItems(task?['updates']);
    final result = asMap(task?['result']);
    return Scaffold(
      appBar: AppBar(title: const Text('Codex session'), actions: [
        IconButton(tooltip: 'Refresh actual Codex events', onPressed: _refresh,
          icon: const Icon(Icons.sync_rounded)),
      ]),
      body: SafeArea(child: Column(children: [
        Expanded(child: ListView(padding: const EdgeInsets.fromLTRB(18, 17, 18, 23), children: [
          Row(children: [
            Container(width: 44, height: 44, alignment: Alignment.center,
              decoration: BoxDecoration(color: OTheme.violet, borderRadius: BorderRadius.circular(14)),
              child: const Icon(Icons.terminal_rounded, color: Colors.white, size: 23)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('REMOTE AGENT CONSOLE', style: TextStyle(fontSize: 10,
                fontWeight: FontWeight.w800, letterSpacing: 1.5, color: OTheme.violet)),
              SizedBox(height: 3),
              Text('Codex CLI / IDE', style: TextStyle(fontSize: 21,
                fontWeight: FontWeight.w700, color: OTheme.ink)),
            ])),
          ]),
          const SizedBox(height: 17),
          InfoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SELECTED SAVED SESSION', style: TextStyle(
              color: OTheme.violet, fontSize: 10, letterSpacing: 1,
              fontWeight: FontWeight.w700)),
            const SizedBox(height: 9),
            Text(widget.sessionTitle.replaceAll(RegExp(r'\s+'), ' ').trim(),
              maxLines: 3, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: OTheme.ink, height: 1.4)),
            const SizedBox(height: 9),
            Row(children: [
              const Icon(Icons.folder_outlined, size: 16, color: Colors.grey),
              const SizedBox(width: 6),
              Expanded(child: Text(widget.cwd, maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11, color: Colors.grey))),
            ]),
            const SizedBox(height: 8),
            Text('Session ID: ' + (widget.sessionId.length > 8
              ? widget.sessionId.substring(0, 8) : widget.sessionId),
              style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ])),
          const SizedBox(height: 13),
          Row(children: [
            StatePill(status),
            const SizedBox(width: 8),
            const Expanded(child: Text('Actual events refreshed every 3 seconds',
              style: TextStyle(fontSize: 11, color: Colors.grey))),
          ]),
          if (error != null) ...[
            const SizedBox(height: 13),
            InfoPanel(background: const Color(0xFFF9EDE8), child: Text(error!)),
          ],
          if (status == 'waiting_for_approval') ...[
            const SizedBox(height: 15),
            InfoPanel(background: OTheme.lavender, child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Execution approval required', style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                const Text('The worker cannot start this Codex turn until you review and approve it.'),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: busy ? null : () => _decideTurn(false),
                    child: const Text('Reject'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: busy ? null : () => _decideTurn(true),
                    child: const Text('Approve'))),
                ]),
              ])),
          ],
          for (final a in approvals) ...[
            const SizedBox(height: 13),
            InfoPanel(background: const Color(0xFFFFF2E7),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('LIVE CODEX PERMISSION REQUEST', style: TextStyle(
                  fontWeight: FontWeight.w800, color: OTheme.violet, fontSize: 11)),
                const SizedBox(height: 8),
                Text(a['kind']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 7),
                SelectableText(a['description']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12, height: 1.5)),
                const SizedBox(height: 12),
                Row(children: [
                  Expanded(child: OutlinedButton(onPressed: busy ? null : () => _decideAction(a, false),
                    child: const Text('Deny'))),
                  const SizedBox(width: 8),
                  Expanded(child: FilledButton(onPressed: busy ? null : () => _decideAction(a, true),
                    child: const Text('Approve action'))),
                ]),
              ])),
          ],
          const SizedBox(height: 22),
          const Heading('Live activity timeline'),
          const SizedBox(height: 11),
          if (events.isEmpty)
            const InfoPanel(child: Text('No actual Codex events yet. Request and approve a turn below.')),
          for (final e in events)
            Padding(padding: const EdgeInsets.only(bottom: 9), child: InfoPanel(
              background: e['type'] == 'agent_delta' ? OTheme.lavender : Colors.white,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text((e['type'] ?? '').toString().replaceAll('_',' ').toUpperCase(),
                  style: const TextStyle(color: OTheme.violet, fontSize: 10,
                    fontWeight: FontWeight.w800)),
                const SizedBox(height: 6),
                SelectableText(e['text']?.toString() ?? '',
                  style: const TextStyle(fontSize: 12, height: 1.45)),
              ]),
            )),
          if (result['output']?.toString().isNotEmpty == true) ...[
            const SizedBox(height: 15),
            const Heading('Final Codex reply'),
            const SizedBox(height: 9),
            InfoPanel(child: SelectableText(result['output'].toString())),
          ],
          if (task?['error']?.toString().isNotEmpty == true)
            InfoPanel(background: const Color(0xFFF9EDE8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.error_outline_rounded, color: Color(0xFF9B4835), size: 19),
                  SizedBox(width: 7),
                  Text('Provider error', style: TextStyle(
                    fontWeight: FontWeight.w700, color: Color(0xFF9B4835))),
                ]),
                const SizedBox(height: 8),
                SelectableText(task!['error'].toString(),
                  style: const TextStyle(fontSize: 12, height: 1.5)),
                const SizedBox(height: 8),
                const Text('A failed attempt remains in history. Retrying creates a NEW approval request.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
                const SizedBox(height: 9),
                OutlinedButton.icon(
                  onPressed: busy || active ? null : () {
                    final previous = asMap(task?['parameters']);
                    final message = previous['prompt']?.toString() ?? '';
                    if (message.isEmpty) return;
                    setState(() {
                      composer.text = message;
                      mode = previous['mode'] == 'workspace_write'
                        ? 'workspace_write' : 'read_only';
                    });
                  },
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('Reuse prompt for new attempt'),
                ),
              ])),
          const SizedBox(height: 18),
          const Text('This connects to the official Codex app-server, not the consumer ChatGPT website or a separate running terminal window.',
            style: TextStyle(fontSize: 11, color: Colors.grey)),
        ])),
        Container(padding: const EdgeInsets.fromLTRB(15, 10, 15, 14),
          decoration: const BoxDecoration(color: OTheme.paper,
            border: Border(top: BorderSide(color: OTheme.hairline))),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              ChoiceChip(label: const Text('Read-only'), selected: mode == 'read_only',
                onSelected: active ? null : (_) => setState(() => mode = 'read_only')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Project edits'), selected: mode == 'workspace_write',
                onSelected: active ? null : (_) => setState(() => mode = 'workspace_write')),
            ]),
            const Text('Read-only blocks changes, not all reads outside this folder.',
              style: TextStyle(fontSize: 10, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: TextField(controller: composer, maxLength: 4000,
                maxLines: 4, minLines: 1, enabled: !busy && !active,
                decoration: const InputDecoration(hintText: 'Prompt this actual Codex session',
                  counterText: ''))),
              const SizedBox(width: 7),
              IconButton.filled(tooltip: 'Request real Codex turn',
                onPressed: active || busy ? null : _submit,
                icon: const Icon(Icons.arrow_upward)),
            ]),
          ]),
        ),
      ])),
    );
  }
}

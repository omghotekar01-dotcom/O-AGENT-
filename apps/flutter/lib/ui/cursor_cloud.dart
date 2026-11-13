import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/controller.dart';
import 'ios_components.dart';

List<Map<String, dynamic>> _rows(Object? value) => value is List
  ? value.whereType<Map>().map((m) => Map<String, dynamic>.from(m)).toList()
  : <Map<String, dynamic>>[];
String _value(Object? x, [String fallback = '']) => x?.toString() ?? fallback;
bool _active(Object? status) => const {
  'CREATING', 'RUNNING', 'WAITING_FOR_BACKGROUND_WORK'
}.contains(status);

/// Real, separately authenticated Cursor Cloud Agents v1. This is a hosted
/// provider workspace, not a mirror of an open Cursor IDE window.
class CursorCloudScreen extends StatefulWidget {
  const CursorCloudScreen({super.key, required this.controller});
  final ControlController controller;
  @override State<CursorCloudScreen> createState() => _CursorCloudState();
}
class _CursorCloudState extends State<CursorCloudScreen> {
  Map<String, dynamic>? connection;
  List<Map<String, dynamic>> agents = [];
  String? error;
  bool busy = false;
  @override
  void initState() { super.initState(); _refresh(); }
  Future<void> _refresh() async {
    if (busy || !mounted) return;
    final api = widget.controller.client;
    if (api == null) {
      setState(() => error = 'Connect to your O-AGENT backend first.');
      return;
    }
    setState(() { busy = true; error = null; });
    try {
      final current = await api.cursorStatus();
      final list = current['connected'] == true
        ? await api.cursorAgents() : <Map<String, dynamic>>[];
      if (!mounted || api != widget.controller.client) return;
      setState(() { connection = current; agents = list; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Future<void> _connect() async {
    final key = await showModalBottomSheet<String>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => const CursorKeySheet());
    if (key == null || !mounted) return;
    final api = widget.controller.client;
    if (api == null) return;
    setState(() { busy = true; error = null; });
    try {
      await api.connectCursor(key);
      await api.verifyCursor();
    } catch (e) {
      if (mounted) setState(() => error =
        'The key may have been saved, but verification did not succeed: ' +
        e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await _refresh();
  }
  Future<void> _verify() async {
    final api = widget.controller.client;
    if (api == null) return;
    setState(() { busy = true; error = null; });
    try {
      await api.verifyCursor();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cursor API identity verified.')));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await _refresh();
  }
  Future<void> _disconnect() async {
    final answer = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect Cursor?'),
        content: const Text('Your encrypted Cursor key will be erased from '
          'this O-AGENT account. Existing Cursor Cloud agents remain with Cursor.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep connected')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Disconnect')),
        ]));
    if (answer != true || !mounted) return;
    try { await widget.controller.client?.disconnectCursor(); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    await _refresh();
  }
  void _openAgent(Map<String, dynamic> agent) {
    Navigator.push(context, MaterialPageRoute<void>(
      builder: (_) => CursorAgentDetailScreen(
        controller: widget.controller, agent: agent)));
  }
  Widget _agentCard(Map<String, dynamic> agent) {
    final status = _value(agent['status'], 'UNKNOWN');
    return Padding(padding: const EdgeInsets.only(bottom: 10),
      child: OSurface(onTap: () => _openAgent(agent), child: Row(children: [
        Container(width: 48, height: 48,
          decoration: BoxDecoration(
            color: OVisual.primary.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(15)),
          child: const Icon(CupertinoIcons.cloud, color: OVisual.primary)),
        const SizedBox(width: 13),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_value(agent['name'], 'Cloud agent'),
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: OVisual.label(context),
                fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 7),
            OStatePill(status),
          ])),
        const SizedBox(width: 8),
        const Icon(CupertinoIcons.chevron_right, size: 16),
      ])));
  }
  @override
  Widget build(BuildContext context) {
    final connected = connection?['connected'] == true;
    final verified = connection?['status'] == 'connected';
    return Scaffold(
      backgroundColor: OVisual.canvas(context),
      appBar: AppBar(title: const Text('Cursor Cloud'),
        actions: [
          IconButton(tooltip: 'Refresh cloud agents',
            onPressed: busy ? null : _refresh,
            icon: const Icon(CupertinoIcons.refresh)),
        ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: RefreshIndicator(onRefresh: _refresh, child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(19, 14, 19, 40),
          children: [
            const OScreenTitle(
              eyebrow: 'Hosted coding agents',
              title: 'Your cloud workspace.',
              subtitle: 'See real Cursor agents, continue their project work, '
                'inspect run results and cancel supported runs from your phone.'),
            const SizedBox(height: 19),
            if (connection == null && busy) const OLoadingState(),
            if (error != null) Padding(padding: const EdgeInsets.only(bottom: 14),
              child: OSurface(tint: const Color(0xFFFFF2F1),
                child: Text(error!, style: const TextStyle(
                  color: Color(0xFF9C3D42), fontSize: 12, height: 1.5)))),
            if (connection != null) OSurface(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Icon(CupertinoIcons.person_crop_circle,
                    color: OVisual.primary, size: 26),
                  const SizedBox(width: 11),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(verified ? 'Identity verified' :
                        connected ? 'Needs verification' : 'Connect your API key',
                        style: TextStyle(color: OVisual.label(context),
                          fontWeight: FontWeight.w800, fontSize: 15)),
                      const SizedBox(height: 3),
                      Text(connected ? _value(connection?['identity'], 'Cursor account')
                        : 'Your credential stays in the encrypted account vault.',
                        style: TextStyle(fontSize: 12,
                          color: OVisual.muted(context)),
                        overflow: TextOverflow.ellipsis),
                    ])),
                  OStatePill(_value(connection?['status'], 'not connected')),
                ]),
                const SizedBox(height: 17),
                Wrap(spacing: 8, runSpacing: 8, children: [
                  FilledButton.icon(onPressed: busy ? null : _connect,
                    icon: Icon(connected ? CupertinoIcons.arrow_2_circlepath
                      : CupertinoIcons.link, size: 17),
                    label: Text(connected ? 'Replace key' : 'Connect key')),
                  if (connected) OutlinedButton(
                    onPressed: busy ? null : _verify,
                    child: const Text('Verify')),
                  if (connected) TextButton(
                    onPressed: busy ? null : _disconnect,
                    child: const Text('Disconnect')),
                ]),
                const SizedBox(height: 9),
                Text('Cursor API access and cloud runs may require a paid '
                  'Cursor plan. O-AGENT does not provide free Cursor credits.',
                  style: TextStyle(fontSize: 11, height: 1.45,
                    color: OVisual.muted(context))),
              ])),
            const OSectionTitle('Your agents'),
            if (connected && busy && agents.isEmpty) const OLoadingState(
              message: 'Reading Cursor Cloud agents'),
            if (!connected) OEmptyState(
              icon: CupertinoIcons.cloud,
              title: 'Connect your Cursor account',
              message: 'Use a personal Cursor Cloud API key. O-AGENT will list '
                'only agents visible to that key, never arbitrary IDE tabs.',
              action: FilledButton.icon(onPressed: busy ? null : _connect,
                icon: const Icon(CupertinoIcons.link),
                label: const Text('Add API key'))),
            if (connected && agents.isEmpty && !busy)
              const OEmptyState(icon: CupertinoIcons.square_stack_3d_up,
                title: 'No agents returned',
                message: 'No Cloud Agents were returned by Cursor. Start an '
                  'agent in Cursor and refresh to see it here.'),
            for (final a in agents) _agentCard(a),
            const OSectionTitle('How this connection works'),
            const OIconTile(icon: CupertinoIcons.shield_lefthalf_fill,
              title: 'Your credentials, your agent sessions',
              subtitle: 'This uses the official Cursor Cloud Agents v1 API. '
                'Each O-AGENT user supplies an independent encrypted key.'),
            const SizedBox(height: 9),
            const OIconTile(icon: CupertinoIcons.desktopcomputer,
              title: 'Not desktop takeover',
              subtitle: 'A Cursor Cloud run is not the live Cursor IDE screen '
                'on your laptop. Local screen streaming requires separate consent.'),
          ],
        )),
      ))),
    );
  }
}

class CursorKeySheet extends StatefulWidget {
  const CursorKeySheet({super.key});
  @override State<CursorKeySheet> createState() => _CursorKeySheetState();
}
class _CursorKeySheetState extends State<CursorKeySheet> {
  final key = TextEditingController();
  bool show = false;
  @override
  void dispose() { key.clear(); key.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: EdgeInsets.fromLTRB(22, 10, 22,
      MediaQuery.viewInsetsOf(context).bottom + 25),
    child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Connect Cursor Cloud', style: TextStyle(
          fontSize: 24, fontWeight: FontWeight.w800)),
        const SizedBox(height: 10),
        const Text('Create a personal key under Cursor Dashboard → API Keys. '
          'Your key is encrypted on your O-AGENT backend, never put into the APK.',
          style: TextStyle(fontSize: 13, height: 1.5)),
        const SizedBox(height: 18),
        TextField(controller: key, obscureText: !show,
          autocorrect: false, enableSuggestions: false,
          decoration: InputDecoration(labelText: 'Cursor Cloud API key',
            prefixIcon: const Icon(CupertinoIcons.lock),
            suffixIcon: IconButton(
              tooltip: show ? 'Hide key' : 'Show key',
              icon: Icon(show ? CupertinoIcons.eye_slash : CupertinoIcons.eye),
              onPressed: () => setState(() => show = !show)))),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: () {
            if (key.text.trim().length < 12) return;
            Navigator.pop(context, key.text.trim());
          },
          child: const Text('Save and verify')),
        ),
        const SizedBox(height: 10),
        Text('Verification checks your Cursor API identity without '
          'creating or starting a cloud agent.',
          style: TextStyle(fontSize: 11, height: 1.4,
            color: OVisual.muted(context))),
      ],
    )),
  ));
}

/// Runs are fetched from Cursor itself, not invented by the phone. Polling is
/// foreground-only: there are no claims of push notifications while app is off.
class CursorAgentDetailScreen extends StatefulWidget {
  const CursorAgentDetailScreen({super.key, required this.controller,
    required this.agent});
  final ControlController controller;
  final Map<String, dynamic> agent;
  @override State<CursorAgentDetailScreen> createState() => _CursorAgentDetailState();
}
class _CursorAgentDetailState extends State<CursorAgentDetailScreen> {
  Map<String, dynamic>? details;
  List<Map<String, dynamic>> runs = [];
  Timer? timer;
  bool busy = false;
  String? error;
  String get agentId => _value(widget.agent['id']);
  @override
  void initState() {
    super.initState();
    _refresh();
    timer = Timer.periodic(const Duration(seconds: 10), (_) => _refresh());
  }
  @override
  void dispose() { timer?.cancel(); super.dispose(); }
  Future<void> _refresh() async {
    final api = widget.controller.client;
    if (api == null || !mounted || busy) return;
    setState(() => busy = true);
    try {
      final next = await api.cursorAgent(agentId);
      final nextRuns = await api.cursorRuns(agentId);
      if (!mounted || widget.controller.client != api) return;
      setState(() { details = next; runs = nextRuns; error = null; });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
  Future<void> _prompt() async {
    final draft = await showModalBottomSheet<CursorPromptDraft>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => const CursorPromptSheet());
    if (draft == null || !mounted) return;
    final accepted = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: Text(draft.steer ? 'Steer this active run?' : 'Start a new run?'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('This sends an instruction to your authenticated '
              'Cursor Cloud agent and may incur provider charges.'),
            const SizedBox(height: 12),
            Text('Agent: ' + _value(details?['name'], agentId),
              style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 9),
            SelectableText(draft.prompt, style: const TextStyle(fontSize: 13)),
          ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Confirm send')),
        ]));
    if (accepted != true || !mounted) return;
    final api = widget.controller.client;
    if (api == null) return;
    setState(() { busy = true; error = null; });
    try {
      await api.cursorFollowUp(agentId: agentId,
        prompt: draft.prompt, steer: draft.steer);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cursor accepted the request. Refreshing real runs.')));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await _refresh();
  }
  Future<void> _cancelRun(String runId) async {
    final accepted = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel the running agent task?'),
        content: const Text('Cancellation is terminal for this run. '
          'You can start another run on the same agent later.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep running')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Cancel run')),
        ]));
    if (accepted != true || !mounted) return;
    final api = widget.controller.client;
    if (api == null) return;
    setState(() { busy = true; error = null; });
    try { await api.cursorCancel(agentId, runId); }
    catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => busy = false); }
    await _refresh();
  }
  Future<void> _openRun(String runId) async {
    final api = widget.controller.client;
    if (api == null) return;
    try {
      final result = await api.cursorRun(agentId, runId);
      if (!mounted) return;
      await showModalBottomSheet<void>(context: context,
        isScrollControlled: true, showDragHandle: true,
        builder: (_) => SafeArea(child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: FractionallySizedBox(heightFactor: .76,
            child: ListView(children: [
              Text('Actual run details', style: TextStyle(
                color: OVisual.label(context), fontSize: 22,
                fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              OStatePill(_value(result['status'], 'UNKNOWN')),
              const SizedBox(height: 14),
              SelectableText(_value(result['result'],
                  'No final assistant reply yet. Refresh when the run finishes.'),
                style: const TextStyle(fontSize: 14, height: 1.55)),
              const SizedBox(height: 16),
              for (final branch in _rows(result['branches']))
                Padding(padding: const EdgeInsets.only(bottom: 9),
                  child: Text(_value(branch['repo']) + ' · ' +
                    _value(branch['branch']),
                    style: TextStyle(fontSize: 12,
                      color: OVisual.muted(context)))),
            ])),
        )));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }
  Future<void> _openProvider() async {
    final url = _value(details?['url'], _value(widget.agent['url']));
    final parsed = Uri.tryParse(url);
    if (parsed == null || parsed.scheme != 'https' ||
        !(parsed.host == 'cursor.com' || parsed.host == 'www.cursor.com')) return;
    if (!await launchUrl(parsed, mode: LaunchMode.externalApplication) && mounted) {
      setState(() => error = 'Could not open Cursor.');
    }
  }
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: OVisual.canvas(context),
      appBar: AppBar(title: const Text('Agent details'), actions: [
        IconButton(onPressed: busy ? null : _refresh,
          icon: const Icon(CupertinoIcons.refresh)),
      ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 750),
        child: RefreshIndicator(onRefresh: _refresh, child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(19, 14, 19, 36),
          children: [
            OScreenTitle(eyebrow: 'Cursor Cloud / live provider',
              title: _value(details?['name'], _value(widget.agent['name'], 'Agent')),
              subtitle: 'This is the provider-owned cloud session. '
                'Its real runs and final outputs are read directly from Cursor.'),
            const SizedBox(height: 19),
            OSurface(child: Row(children: [
              const Icon(CupertinoIcons.cloud_fill, size: 24,
                color: OVisual.primary),
              const SizedBox(width: 11),
              Expanded(child: Text('Agent status',
                style: TextStyle(fontWeight: FontWeight.w700,
                  color: OVisual.label(context)))),
              OStatePill(_value(details?['status'],
                _value(widget.agent['status'], 'unknown'))),
            ])),
            const SizedBox(height: 11),
            Wrap(spacing: 9, runSpacing: 9, children: [
              FilledButton.icon(
                onPressed: busy ? null : _prompt,
                icon: const Icon(CupertinoIcons.paperplane, size: 18),
                label: const Text('Send prompt')),
              OutlinedButton.icon(onPressed: _openProvider,
                icon: const Icon(CupertinoIcons.arrow_up_right_square, size: 17),
                label: const Text('Open in Cursor')),
            ]),
            if (error != null) Padding(padding: const EdgeInsets.only(top: 12),
              child: OSurface(tint: const Color(0xFFFFF1F1),
                child: Text(error!, style: const TextStyle(
                  color: Color(0xFFB34D51), fontSize: 12)))),
            const OSectionTitle('Actual cloud runs'),
            if (busy && runs.isEmpty) const OLoadingState(),
            if (!busy && runs.isEmpty) const OEmptyState(
              icon: CupertinoIcons.terminal,
              title: 'No runs returned',
              message: 'Cursor has no recorded runs for this agent. '
                'Tap Send prompt to start an explicitly confirmed follow-up.'),
            for (final r in runs) Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: OSurface(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Text(_value(r['id']),
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: OVisual.label(context),
                        fontWeight: FontWeight.w700, fontSize: 13))),
                    OStatePill(_value(r['status'], 'UNKNOWN')),
                  ]),
                  const SizedBox(height: 7),
                  Text(_value(r['updatedAt'], 'No timestamp'),
                    style: TextStyle(color: OVisual.muted(context),
                      fontSize: 11)),
                  const SizedBox(height: 13),
                  Wrap(spacing: 9, runSpacing: 8, children: [
                    OutlinedButton.icon(
                      onPressed: busy ? null : () => _openRun(_value(r['id'])),
                      icon: const Icon(CupertinoIcons.doc_text, size: 16),
                      label: const Text('View result')),
                    if (_active(r['status'])) TextButton.icon(
                      onPressed: busy ? null : () => _cancelRun(_value(r['id'])),
                      icon: const Icon(CupertinoIcons.stop_circle, size: 17),
                      label: const Text('Cancel run')),
                  ]),
                ]))),
            const OSectionTitle('Permissions and limits'),
            const OIconTile(icon: CupertinoIcons.checkmark_shield,
              title: 'Cursor account permissions apply',
              subtitle: 'You can only operate agents your Cursor API key permits. '
                'Provider billing, plan limits and repository permissions apply.'),
            const SizedBox(height: 9),
            const OIconTile(icon: CupertinoIcons.hand_raised,
              title: 'No fabricated approval buttons',
              subtitle: 'Cursor Cloud v1 does not expose the same per-tool '
                'human approval callback protocol as the Codex CLI adapter.'),
          ],
        )),
      ))),
    );
  }
}
class CursorPromptDraft {
  const CursorPromptDraft(this.prompt, this.steer);
  final String prompt;
  final bool steer;
}
class CursorPromptSheet extends StatefulWidget {
  const CursorPromptSheet({super.key});
  @override State<CursorPromptSheet> createState() => _CursorPromptSheetState();
}
class _CursorPromptSheetState extends State<CursorPromptSheet> {
  final prompt = TextEditingController();
  bool steer = false;
  @override
  void dispose() { prompt.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: EdgeInsets.fromLTRB(21, 9, 21,
      MediaQuery.viewInsetsOf(context).bottom + 22),
    child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Send to Cursor agent', style: TextStyle(
          fontWeight: FontWeight.w800, fontSize: 23)),
        const SizedBox(height: 8),
        const Text('This sends a real instruction to the selected cloud agent, '
          'not to the local chatbot.',
          style: TextStyle(fontSize: 12, height: 1.5)),
        const SizedBox(height: 16),
        TextField(controller: prompt, minLines: 3, maxLines: 7,
          maxLength: 4000,
          decoration: const InputDecoration(
            hintText: 'Describe the changes to this project…',
            labelText: 'Exact prompt')),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Steer current run'),
          subtitle: const Text('If your Cursor account supports it, '
            'deliver this prompt to an active run instead of creating a new run.'),
          value: steer, onChanged: (v) => setState(() => steer = v)),
        const SizedBox(height: 10),
        SizedBox(width: double.infinity, child: FilledButton(
          onPressed: () {
            if (prompt.text.trim().isEmpty) return;
            Navigator.pop(context, CursorPromptDraft(prompt.text.trim(), steer));
          },
          child: const Text('Review prompt before sending'))),
      ],
    )),
  ));
}

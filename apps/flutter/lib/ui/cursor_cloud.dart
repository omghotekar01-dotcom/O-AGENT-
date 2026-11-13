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
  Future<void> _createAgent() async {
    final draft = await showModalBottomSheet<CursorCreateDraft>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => const CursorCreateAgentSheet());
    if (draft == null || !mounted) return;
    final approved = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create a real cloud agent?'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Cursor will receive this task, access the selected '
              'repository and may incur cloud-agent charges.',
              style: TextStyle(fontSize: 13, height: 1.45)),
            const SizedBox(height: 13),
            Text('Repository: ' + draft.repoUrl,
              style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            Text('Starting branch: ' +
              (draft.startingRef.isEmpty ? 'Provider default' : draft.startingRef)),
            Text('Mode: ' + draft.mode),
            Text('Auto-create PR: ' + (draft.autoCreatePR ? 'Yes' : 'No')),
            const SizedBox(height: 11),
            const Text('Exact initial instruction:',
              style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 5),
            SelectableText(draft.prompt, style: const TextStyle(fontSize: 13)),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Create cloud agent')),
        ],
      ));
    if (approved != true || !mounted) return;
    final api = widget.controller.client;
    if (api == null) return;
    setState(() { busy = true; error = null; });
    Map<String, dynamic>? newAgent;
    try {
      final result = await api.createCursorAgent(
        prompt: draft.prompt, repoUrl: draft.repoUrl,
        startingRef: draft.startingRef, mode: draft.mode,
        autoCreatePR: draft.autoCreatePR);
      if (!mounted) return;
      if (result['agent'] is Map) {
        newAgent = Map<String, dynamic>.from(result['agent'] as Map);
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cursor accepted the new cloud agent.')));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
    await _refresh();
    if (mounted && newAgent != null && _value(newAgent['id']).isNotEmpty) {
      _openAgent(newAgent);
    }
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
            OSectionTitle('Your agents',
              action: verified ? 'New agent' : null,
              onAction: verified && !busy ? _createAgent : null),
            if (verified) Padding(padding: const EdgeInsets.only(bottom: 13),
              child: SizedBox(width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy ? null : _createAgent,
                  icon: const Icon(CupertinoIcons.add, size: 18),
                  label: const Text('Create a hosted coding agent')))),
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
                message: 'No agents were returned by Cursor. Create one here '
                  'or refresh after starting an agent in Cursor.'),
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
  List<Map<String, dynamic>> artifacts = [];
  String? artifactWarning;
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
      List<Map<String, dynamic>> nextArtifacts = [];
      String? warning;
      try { nextArtifacts = await api.cursorArtifacts(agentId); }
      catch (e) {
        // An unsupported artifact listing must not hide real run results.
        warning = 'Artifact listing unavailable: ' + e.toString();
      }
      if (!mounted || widget.controller.client != api) return;
      setState(() {
        details = next;
        runs = nextRuns;
        artifacts = nextArtifacts;
        artifactWarning = warning;
        error = null;
      });
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
  Future<void> _openArtifact(Map<String, dynamic> item) async {
    final path = _value(item['path']);
    if (path.isEmpty) return;
    final api = widget.controller.client;
    if (api == null) return;
    try {
      final result = await api.cursorArtifactLink(agentId, path);
      final uri = Uri.tryParse(_value(result['url']));
      if (uri == null || uri.scheme != 'https' ||
          !uri.host.startsWith('cloud-agent-artifacts.') ||
          !uri.host.endsWith('.amazonaws.com')) {
        throw const FormatException('Untrusted cloud artifact link');
      }
      if (!mounted) return;
      final file = path.split('/').last.toLowerCase();
      final image = file.endsWith('.png') || file.endsWith('.jpg') ||
        file.endsWith('.jpeg') || file.endsWith('.webp') || file.endsWith('.gif');
      if (image) {
        await showDialog<void>(context: context, builder: (ctx) => Dialog(
          child: Padding(padding: const EdgeInsets.all(14),
            child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(path.split('/').last,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800)),
                const SizedBox(height: 12),
                ConstrainedBox(constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(ctx).height * .67),
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Image.network(uri.toString(),
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Padding(
                        padding: EdgeInsets.all(20),
                        child: Text('This image could not be loaded. '
                          'Check your connection or refresh the artifact.')))),
                ),
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Close'))),
              ]),
          )));
      } else {
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          throw const FormatException('Could not open this signed download');
        }
      }
    } catch (e) {
      if (mounted) setState(() =>
        artifactWarning = 'Could not open this artifact: ' + e.toString());
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
              icon: Icons.terminal_rounded,
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
                    if (_active(r['status'])) FilledButton.tonalIcon(
                      onPressed: () => Navigator.push(context,
                        MaterialPageRoute<void>(builder: (_) =>
                          CursorLiveRunScreen(
                            controller: widget.controller,
                            agentId: agentId, runId: _value(r['id'])))),
                      icon: const Icon(CupertinoIcons.waveform_path, size: 17),
                      label: const Text('Watch live')),
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
            OSectionTitle('Generated files and previews',
              action: 'Refresh', onAction: _refresh),
            if (artifactWarning != null)
              Padding(padding: const EdgeInsets.only(bottom: 10),
                child: OSurface(child: Text(artifactWarning!,
                  style: const TextStyle(color: OVisual.rose,
                    fontSize: 12, height: 1.45)))),
            if (artifacts.isEmpty && !busy && artifactWarning == null)
              const OEmptyState(icon: CupertinoIcons.photo,
                title: 'No generated files',
                message: 'If Cursor saves screenshots, PDFs or project '
                  'artifacts, they appear here. This is a saved artifact '
                  'viewer, not live computer screen sharing.'),
            for (final item in artifacts)
              Padding(padding: const EdgeInsets.only(bottom: 10),
                child: OIconTile(
                  icon: RegExp(r'\.(png|jpg|jpeg|webp|gif)
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


/// Run-specific live progress through Cursor's documented SSE endpoint.
/// This is a provider event feed, not a hidden display-capture or reasoning
/// transcript. It runs only while the phone screen is open.
class CursorLiveRunScreen extends StatefulWidget {
  const CursorLiveRunScreen({super.key, required this.controller,
    required this.agentId, required this.runId});
  final ControlController controller;
  final String agentId, runId;
  @override State<CursorLiveRunScreen> createState() => _CursorLiveRunState();
}
class _CursorLiveRunState extends State<CursorLiveRunScreen> {
  StreamSubscription<Map<String, dynamic>>? subscription;
  Map<String, dynamic>? result;
  List<Map<String, String>> toolEvents = [];
  String output = '';
  String? lastEventId;
  String? error;
  String status = 'CREATING';
  bool streaming = false;
  @override
  void initState() { super.initState(); _start(); }
  @override
  void dispose() { subscription?.cancel(); super.dispose(); }
  Future<void> _start() async {
    subscription?.cancel();
    subscription = null;
    await _readCurrent();
    if (!mounted || const {'FINISHED','ERROR','CANCELLED','EXPIRED'}
        .contains(status)) return;
    _connect();
  }
  Future<void> _readCurrent() async {
    final api = widget.controller.client;
    if (api == null) return;
    try {
      final next = await api.cursorRun(widget.agentId, widget.runId);
      if (!mounted || api != widget.controller.client) return;
      setState(() {
        result = next;
        status = _value(next['status'], status);
        if (const {'FINISHED','ERROR','CANCELLED','EXPIRED'}
          .contains(status) && next['result'] != null) {
          output = _value(next['result']);
        }
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }
  void _connect() {
    final api = widget.controller.client;
    if (api == null || subscription != null) return;
    setState(() { streaming = true; error = null; });
    subscription = api.cursorRunEvents(widget.agentId, widget.runId,
      lastEventId: lastEventId).listen((message) {
      if (!mounted || api != widget.controller.client) return;
      final kind = _value(message['event']);
      final eventId = _value(message['id']);
      setState(() {
        if (eventId.isNotEmpty) lastEventId = eventId;
        switch (kind) {
          case 'assistant':
            output += _value(message['text']);
            if (output.length > 16000) output = output.substring(output.length - 16000);
          case 'tool_call':
            toolEvents.add({
              'name': _value(message['name'], 'Tool operation'),
              'status': _value(message['status'], 'unknown'),
            });
            if (toolEvents.length > 80) toolEvents.removeAt(0);
          case 'status':
            status = _value(message['status'], status);
          case 'result':
            status = _value(message['status'], status);
            if (message['text'] != null) output = _value(message['text']);
          case 'error':
            error = _value(message['message'], 'Provider stream unavailable');
            lastEventId = null;
          case 'done':
            streaming = false;
        }
      });
      if (kind == 'done' || kind == 'result') _readCurrent();
    }, onError: (Object e) {
      if (mounted) setState(() {
        streaming = false;
        error = 'Live stream disconnected. Refresh for the official run state.';
      });
      subscription = null;
      _readCurrent();
    }, onDone: () {
      if (mounted) setState(() => streaming = false);
      subscription = null;
      _readCurrent();
    }, cancelOnError: true);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: OVisual.canvas(context),
    appBar: AppBar(title: const Text('Live agent output'), actions: [
      IconButton(tooltip: 'Reload run and reconnect',
        onPressed: _start, icon: const Icon(CupertinoIcons.refresh)),
    ]),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 730),
      child: ListView(padding: const EdgeInsets.fromLTRB(19, 16, 19, 32),
        children: [
          const OScreenTitle(eyebrow: 'Cursor / authenticated event stream',
            title: 'Watch the work.',
            subtitle: 'Live assistant text and sanitized tool statuses '
              'from this single Cursor Cloud run. No desktop capture.'),
          const SizedBox(height: 18),
          OSurface(child: Row(children: [
            Icon(streaming ? CupertinoIcons.waveform_path
              : CupertinoIcons.pause_circle,
              color: streaming ? OVisual.primary : OVisual.secondary),
            const SizedBox(width: 10),
            Expanded(child: Text(streaming ? 'Receiving live events'
              : 'Stream paused or complete', style: TextStyle(
                color: OVisual.label(context), fontWeight: FontWeight.w700,
                fontSize: 12))),
            OStatePill(status),
          ])),
          if (error != null) Padding(
            padding: const EdgeInsets.only(top: 11),
            child: OSurface(tint: const Color(0xFFFFF1F1),
              child: Text(error!, style: const TextStyle(
                color: Color(0xFFAA4B51), fontSize: 12)))),
          const OSectionTitle('Assistant output'),
          OSurface(child: SelectableText(output.isEmpty
            ? 'No assistant text received yet. The final result is also '
              'available from Cursor once this run finishes.' : output,
            style: TextStyle(color: OVisual.label(context),
              fontSize: 14, height: 1.55))),
          const OSectionTitle('Tool activity'),
          if (toolEvents.isEmpty) const OEmptyState(
            icon: CupertinoIcons.hammer,
            title: 'No tool events yet',
            message: 'Only provider-reported tool names and statuses appear '
              'here. Raw tool arguments and model reasoning are not forwarded.'),
          for (final e in toolEvents)
            Padding(padding: const EdgeInsets.only(bottom: 8),
              child: OIconTile(icon: CupertinoIcons.hammer,
                title: e['name'] ?? 'Tool', subtitle: e['status'] ?? '')),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: _start,
            icon: const Icon(CupertinoIcons.arrow_clockwise),
            label: const Text('Refresh official run status')),
          if (result != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Run ID: ' + widget.runId,
              style: TextStyle(color: OVisual.muted(context), fontSize: 11))),
        ]),
    ))),
  );
}


/// Explicitly reviewed creation of a billable provider agent. Launching a
/// cloud agent is separate from controlling a user's existing IDE window.
class CursorCreateDraft {
  const CursorCreateDraft({
    required this.prompt, required this.repoUrl,
    required this.startingRef, required this.mode,
    required this.autoCreatePR,
  });
  final String prompt, repoUrl, startingRef, mode;
  final bool autoCreatePR;
}
class CursorCreateAgentSheet extends StatefulWidget {
  const CursorCreateAgentSheet({super.key});
  @override State<CursorCreateAgentSheet> createState() =>
    _CursorCreateAgentSheetState();
}
class _CursorCreateAgentSheetState extends State<CursorCreateAgentSheet> {
  final repo = TextEditingController();
  final branch = TextEditingController(text: 'main');
  final task = TextEditingController();
  String mode = 'plan';
  bool autoPR = false;
  String? validation;
  @override
  void dispose() {
    repo.dispose(); branch.dispose(); task.dispose(); super.dispose();
  }
  void _submit() {
    final u = Uri.tryParse(repo.text.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty ||
        u.userInfo.isNotEmpty || u.query.isNotEmpty || u.fragment.isNotEmpty ||
        !u.pathSegments.where((p) => p.isNotEmpty).isNotEmpty) {
      setState(() => validation = 'Enter an HTTPS URL to a repository.');
      return;
    }
    if (task.text.trim().isEmpty || task.text.length > 4000) {
      setState(() => validation = 'Enter an initial task (up to 4000 characters).');
      return;
    }
    final ref = branch.text.trim();
    if (ref.isNotEmpty &&
        (!RegExp(r'^[A-Za-z0-9._/-]{1,120}$').hasMatch(ref) ||
        ref.contains('..'))) {
      setState(() => validation = 'Enter a valid branch name.');
      return;
    }
    Navigator.pop(context, CursorCreateDraft(
      prompt: task.text.trim(),
      repoUrl: repo.text.trim(),
      startingRef: ref, mode: mode, autoCreatePR: autoPR,
    ));
  }
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: EdgeInsets.fromLTRB(21, 9, 21,
      MediaQuery.viewInsetsOf(context).bottom + 24),
    child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('New cloud agent',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        Text('This creates a real, possibly billable coding agent in your '
          'Cursor account. It uses a new branch instead of pushing '
          'directly to your existing branch.',
          style: TextStyle(fontSize: 12, height: 1.5,
            color: OVisual.muted(context))),
        const SizedBox(height: 16),
        TextField(controller: repo, autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Repository HTTPS URL',
            hintText: 'https://github.com/owner/project',
            prefixIcon: Icon(CupertinoIcons.folder))),
        const SizedBox(height: 11),
        TextField(controller: branch, autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Starting branch',
            helperText: 'Leave blank for the provider default branch',
            prefixIcon: Icon(CupertinoIcons.arrow_branch))),
        const SizedBox(height: 11),
        TextField(controller: task, minLines: 3, maxLines: 6, maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'Exact initial task',
            hintText: 'Investigate the issue and suggest a safe fix…',
            alignLabelWithHint: true)),
        const SizedBox(height: 9),
        Text('Execution mode', style: TextStyle(
          color: OVisual.label(context), fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        CupertinoSlidingSegmentedControl<String>(
          groupValue: mode,
          children: const {
            'plan': Padding(padding: EdgeInsets.symmetric(
              horizontal: 12, vertical: 8), child: Text('Plan first')),
            'agent': Padding(padding: EdgeInsets.symmetric(
              horizontal: 12, vertical: 8), child: Text('Implement')),
          },
          onValueChanged: (next) {
            if (next != null) setState(() => mode = next);
          }),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Open a pull request when ready'),
          subtitle: const Text('The provider may create a PR after the run '
            'finishes. Direct pushes to your current branch are disabled.'),
          value: autoPR, onChanged: (v) => setState(() => autoPR = v)),
        if (validation != null) Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(validation!, style: const TextStyle(
            color: OVisual.rose, fontSize: 12))),
        const SizedBox(height: 11),
        SizedBox(width: double.infinity,
          child: FilledButton.icon(onPressed: _submit,
            icon: const Icon(CupertinoIcons.arrow_right, size: 17),
            label: const Text('Review before creating'))),
      ],
    )),
  ));
}
,
                    caseSensitive: false)
                    .hasMatch(_value(item['path']))
                    ? CupertinoIcons.photo
                    : CupertinoIcons.doc,
                  title: _value(item['path']).split('/').last,
                  subtitle: _value(item['sizeBytes'], 'Unknown size') +
                    ' bytes · ' + _value(item['updatedAt'], 'Saved artifact') +
                    '\nTemporary provider download; expires after 15 minutes',
                  onTap: busy ? null : () => _openArtifact(item))),
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


/// Run-specific live progress through Cursor's documented SSE endpoint.
/// This is a provider event feed, not a hidden display-capture or reasoning
/// transcript. It runs only while the phone screen is open.
class CursorLiveRunScreen extends StatefulWidget {
  const CursorLiveRunScreen({super.key, required this.controller,
    required this.agentId, required this.runId});
  final ControlController controller;
  final String agentId, runId;
  @override State<CursorLiveRunScreen> createState() => _CursorLiveRunState();
}
class _CursorLiveRunState extends State<CursorLiveRunScreen> {
  StreamSubscription<Map<String, dynamic>>? subscription;
  Map<String, dynamic>? result;
  List<Map<String, String>> toolEvents = [];
  String output = '';
  String? lastEventId;
  String? error;
  String status = 'CREATING';
  bool streaming = false;
  @override
  void initState() { super.initState(); _start(); }
  @override
  void dispose() { subscription?.cancel(); super.dispose(); }
  Future<void> _start() async {
    subscription?.cancel();
    subscription = null;
    await _readCurrent();
    if (!mounted || const {'FINISHED','ERROR','CANCELLED','EXPIRED'}
        .contains(status)) return;
    _connect();
  }
  Future<void> _readCurrent() async {
    final api = widget.controller.client;
    if (api == null) return;
    try {
      final next = await api.cursorRun(widget.agentId, widget.runId);
      if (!mounted || api != widget.controller.client) return;
      setState(() {
        result = next;
        status = _value(next['status'], status);
        if (const {'FINISHED','ERROR','CANCELLED','EXPIRED'}
          .contains(status) && next['result'] != null) {
          output = _value(next['result']);
        }
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }
  void _connect() {
    final api = widget.controller.client;
    if (api == null || subscription != null) return;
    setState(() { streaming = true; error = null; });
    subscription = api.cursorRunEvents(widget.agentId, widget.runId,
      lastEventId: lastEventId).listen((message) {
      if (!mounted || api != widget.controller.client) return;
      final kind = _value(message['event']);
      final eventId = _value(message['id']);
      setState(() {
        if (eventId.isNotEmpty) lastEventId = eventId;
        switch (kind) {
          case 'assistant':
            output += _value(message['text']);
            if (output.length > 16000) output = output.substring(output.length - 16000);
          case 'tool_call':
            toolEvents.add({
              'name': _value(message['name'], 'Tool operation'),
              'status': _value(message['status'], 'unknown'),
            });
            if (toolEvents.length > 80) toolEvents.removeAt(0);
          case 'status':
            status = _value(message['status'], status);
          case 'result':
            status = _value(message['status'], status);
            if (message['text'] != null) output = _value(message['text']);
          case 'error':
            error = _value(message['message'], 'Provider stream unavailable');
            lastEventId = null;
          case 'done':
            streaming = false;
        }
      });
      if (kind == 'done' || kind == 'result') _readCurrent();
    }, onError: (Object e) {
      if (mounted) setState(() {
        streaming = false;
        error = 'Live stream disconnected. Refresh for the official run state.';
      });
      subscription = null;
      _readCurrent();
    }, onDone: () {
      if (mounted) setState(() => streaming = false);
      subscription = null;
      _readCurrent();
    }, cancelOnError: true);
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: OVisual.canvas(context),
    appBar: AppBar(title: const Text('Live agent output'), actions: [
      IconButton(tooltip: 'Reload run and reconnect',
        onPressed: _start, icon: const Icon(CupertinoIcons.refresh)),
    ]),
    body: SafeArea(child: Center(child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 730),
      child: ListView(padding: const EdgeInsets.fromLTRB(19, 16, 19, 32),
        children: [
          const OScreenTitle(eyebrow: 'Cursor / authenticated event stream',
            title: 'Watch the work.',
            subtitle: 'Live assistant text and sanitized tool statuses '
              'from this single Cursor Cloud run. No desktop capture.'),
          const SizedBox(height: 18),
          OSurface(child: Row(children: [
            Icon(streaming ? CupertinoIcons.waveform_path
              : CupertinoIcons.pause_circle,
              color: streaming ? OVisual.primary : OVisual.secondary),
            const SizedBox(width: 10),
            Expanded(child: Text(streaming ? 'Receiving live events'
              : 'Stream paused or complete', style: TextStyle(
                color: OVisual.label(context), fontWeight: FontWeight.w700,
                fontSize: 12))),
            OStatePill(status),
          ])),
          if (error != null) Padding(
            padding: const EdgeInsets.only(top: 11),
            child: OSurface(tint: const Color(0xFFFFF1F1),
              child: Text(error!, style: const TextStyle(
                color: Color(0xFFAA4B51), fontSize: 12)))),
          const OSectionTitle('Assistant output'),
          OSurface(child: SelectableText(output.isEmpty
            ? 'No assistant text received yet. The final result is also '
              'available from Cursor once this run finishes.' : output,
            style: TextStyle(color: OVisual.label(context),
              fontSize: 14, height: 1.55))),
          const OSectionTitle('Tool activity'),
          if (toolEvents.isEmpty) const OEmptyState(
            icon: CupertinoIcons.hammer,
            title: 'No tool events yet',
            message: 'Only provider-reported tool names and statuses appear '
              'here. Raw tool arguments and model reasoning are not forwarded.'),
          for (final e in toolEvents)
            Padding(padding: const EdgeInsets.only(bottom: 8),
              child: OIconTile(icon: CupertinoIcons.hammer,
                title: e['name'] ?? 'Tool', subtitle: e['status'] ?? '')),
          const SizedBox(height: 15),
          OutlinedButton.icon(
            onPressed: _start,
            icon: const Icon(CupertinoIcons.arrow_clockwise),
            label: const Text('Refresh official run status')),
          if (result != null) Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text('Run ID: ' + widget.runId,
              style: TextStyle(color: OVisual.muted(context), fontSize: 11))),
        ]),
    ))),
  );
}


/// Explicitly reviewed creation of a billable provider agent. Launching a
/// cloud agent is separate from controlling a user's existing IDE window.
class CursorCreateDraft {
  const CursorCreateDraft({
    required this.prompt, required this.repoUrl,
    required this.startingRef, required this.mode,
    required this.autoCreatePR,
  });
  final String prompt, repoUrl, startingRef, mode;
  final bool autoCreatePR;
}
class CursorCreateAgentSheet extends StatefulWidget {
  const CursorCreateAgentSheet({super.key});
  @override State<CursorCreateAgentSheet> createState() =>
    _CursorCreateAgentSheetState();
}
class _CursorCreateAgentSheetState extends State<CursorCreateAgentSheet> {
  final repo = TextEditingController();
  final branch = TextEditingController(text: 'main');
  final task = TextEditingController();
  String mode = 'plan';
  bool autoPR = false;
  String? validation;
  @override
  void dispose() {
    repo.dispose(); branch.dispose(); task.dispose(); super.dispose();
  }
  void _submit() {
    final u = Uri.tryParse(repo.text.trim());
    if (u == null || u.scheme != 'https' || u.host.isEmpty ||
        u.userInfo.isNotEmpty || u.query.isNotEmpty || u.fragment.isNotEmpty ||
        !u.pathSegments.where((p) => p.isNotEmpty).isNotEmpty) {
      setState(() => validation = 'Enter an HTTPS URL to a repository.');
      return;
    }
    if (task.text.trim().isEmpty || task.text.length > 4000) {
      setState(() => validation = 'Enter an initial task (up to 4000 characters).');
      return;
    }
    final ref = branch.text.trim();
    if (ref.isNotEmpty &&
        (!RegExp(r'^[A-Za-z0-9._/-]{1,120}$').hasMatch(ref) ||
        ref.contains('..'))) {
      setState(() => validation = 'Enter a valid branch name.');
      return;
    }
    Navigator.pop(context, CursorCreateDraft(
      prompt: task.text.trim(),
      repoUrl: repo.text.trim(),
      startingRef: ref, mode: mode, autoCreatePR: autoPR,
    ));
  }
  @override
  Widget build(BuildContext context) => SafeArea(child: Padding(
    padding: EdgeInsets.fromLTRB(21, 9, 21,
      MediaQuery.viewInsetsOf(context).bottom + 24),
    child: SingleChildScrollView(child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('New cloud agent',
          style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
        const SizedBox(height: 7),
        Text('This creates a real, possibly billable coding agent in your '
          'Cursor account. It uses a new branch instead of pushing '
          'directly to your existing branch.',
          style: TextStyle(fontSize: 12, height: 1.5,
            color: OVisual.muted(context))),
        const SizedBox(height: 16),
        TextField(controller: repo, autocorrect: false,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Repository HTTPS URL',
            hintText: 'https://github.com/owner/project',
            prefixIcon: Icon(CupertinoIcons.folder))),
        const SizedBox(height: 11),
        TextField(controller: branch, autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Starting branch',
            helperText: 'Leave blank for the provider default branch',
            prefixIcon: Icon(CupertinoIcons.arrow_branch))),
        const SizedBox(height: 11),
        TextField(controller: task, minLines: 3, maxLines: 6, maxLength: 4000,
          decoration: const InputDecoration(
            labelText: 'Exact initial task',
            hintText: 'Investigate the issue and suggest a safe fix…',
            alignLabelWithHint: true)),
        const SizedBox(height: 9),
        Text('Execution mode', style: TextStyle(
          color: OVisual.label(context), fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        CupertinoSlidingSegmentedControl<String>(
          groupValue: mode,
          children: const {
            'plan': Padding(padding: EdgeInsets.symmetric(
              horizontal: 12, vertical: 8), child: Text('Plan first')),
            'agent': Padding(padding: EdgeInsets.symmetric(
              horizontal: 12, vertical: 8), child: Text('Implement')),
          },
          onValueChanged: (next) {
            if (next != null) setState(() => mode = next);
          }),
        const SizedBox(height: 8),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Open a pull request when ready'),
          subtitle: const Text('The provider may create a PR after the run '
            'finishes. Direct pushes to your current branch are disabled.'),
          value: autoPR, onChanged: (v) => setState(() => autoPR = v)),
        if (validation != null) Padding(
          padding: const EdgeInsets.only(top: 7),
          child: Text(validation!, style: const TextStyle(
            color: OVisual.rose, fontSize: 12))),
        const SizedBox(height: 11),
        SizedBox(width: double.infinity,
          child: FilledButton.icon(onPressed: _submit,
            icon: const Icon(CupertinoIcons.arrow_right, size: 17),
            label: const Text('Review before creating'))),
      ],
    )),
  ));
}

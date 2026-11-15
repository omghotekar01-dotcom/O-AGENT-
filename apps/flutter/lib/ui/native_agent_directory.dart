import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'ios_components.dart';

import '../core/agent_directory.dart';
import '../core/pilot_native.dart';
import '../theme.dart';

/// Shared, deliberately iOS-styled agent directory for BOTH Android and iOS.
/// The rows are sourced from real signed-worker evidence and disclose when a
/// service can only be opened in its official app or legacy workspace.
class NativeAgentDirectory extends StatefulWidget {
  const NativeAgentDirectory({
    super.key, required this.pilot, required this.onSessions,
    required this.onDevices, required this.onLegacy,
    this.onInbox, this.onChatGpt, this.preview = false,
  });

  final NativePilotController pilot;
  final VoidCallback onSessions, onDevices, onLegacy;
  final VoidCallback? onInbox;
  final VoidCallback? onChatGpt;
  final bool preview;

  @override
  State<NativeAgentDirectory> createState() => _NativeAgentDirectoryState();
}

class _NativeAgentDirectoryState extends State<NativeAgentDirectory> {
  String filter = 'all', query = '';

  bool _includes(AgentDirectoryEntry entry) {
    if (filter == 'ready' && !entry.hasVerifiedSession) return false;
    if (filter == 'other' && entry.route != AgentRoute.legacyWorkspace &&
        entry.route != AgentRoute.remoteDesktop) return false;
    final term = query.trim().toLowerCase();
    return term.isEmpty ||
      (entry.name + ' ' + entry.summary + ' ' + entry.status)
        .toLowerCase().contains(term);
  }

  Future<void> _showInfo(String title, String body, {
    String action = 'OK', VoidCallback? proceed,
  }) async {
    if (!mounted) return;
    await showCupertinoDialog<void>(
      context: context, builder: (dialog) => CupertinoAlertDialog(
        title: Text(title), content: Text(body), actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(dialog).pop(),
            child: const Text('Cancel')),
          CupertinoDialogAction(
            isDefaultAction: true,
            onPressed: () {
              Navigator.of(dialog).pop();
              proceed?.call();
            }, child: Text(action)),
        ]));
  }

  Future<void> _open(AgentDirectoryEntry agent) async {
    if(agent.id=='chatgpt' && widget.onChatGpt!=null){
      widget.onChatGpt!.call();
      return;
    }
    switch (agent.route) {
      case AgentRoute.sessions:
        if (widget.preview) {
          await _showInfo('Connect your private workspace',
            'Sign in to O-AGENT first. Real Codex, Claude SDK and Copilot SDK '
            'sessions will appear only after their trusted workers report them.');
        } else {
          widget.onSessions();
        }
        return;
      case AgentRoute.devices:
        if (widget.preview) {
          await _showInfo('Connect a trusted computer',
            'Sign in to O-AGENT to enroll your PC. A worker is not '
            'the same as unrestricted control of the VS Code window.');
        } else {
          widget.onDevices();
        }
        return;
      case AgentRoute.legacyWorkspace:
      case AgentRoute.remoteDesktop:
        // Real screen control and previous projects are now an integrated
        // destination in this same app. Never open a dead warning-only tile.
        if (widget.preview) {
          await _showInfo('Sign in to your workspace',
            'Connect your private O-AGENT account before opening '
            'your authenticated remote computer.');
        } else {
          widget.onLegacy();
        }
        return;
    }
  }

  IconData _icon(String id) => switch (id) {
    'codex' => CupertinoIcons.square_stack,
    'claude_sdk' => CupertinoIcons.bubble_left_bubble_right,
    'copilot_sdk' => CupertinoIcons.cloud,
    'vscode' => CupertinoIcons.device_laptop,
    'github' => CupertinoIcons.folder,
    'cursor' => CupertinoIcons.square_stack,
    'chatgpt' => CupertinoIcons.chat_bubble_2,
    'claude_web' => CupertinoIcons.chat_bubble,
    'gemini' => CupertinoIcons.star,
    _ => CupertinoIcons.square_grid_2x2,
  };

  Widget _tile(AgentDirectoryEntry agent) =>
    Padding(padding: const EdgeInsets.only(bottom: 9),
      child: KeyedSubtree(
        key: ValueKey('agent-' + agent.id),
        child: OIconTile(
          icon: _icon(agent.id), title: agent.name,
          subtitle: agent.status + '\n' + agent.summary,
          color: agent.hasVerifiedSession
            ? OVisual.mint : OVisual.primary,
          onTap: () => _open(agent))));

  Widget _section(String title, List<AgentDirectoryEntry> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OSectionTitle(title),
        for (final agent in items) _tile(agent),
      ]);
  }

  @override
  Widget build(BuildContext context) {
    final entries = buildAgentDirectory(
      signedIn: !widget.preview && widget.pilot.connected,
      devices: widget.pilot.devices,
      codexSessions: widget.pilot.sessions,
      sdkSessions: widget.pilot.providerSessions,
    ).where(_includes).toList();
    final available = entries.where((e) => e.hasVerifiedSession).length;
    final online = widget.pilot.onlineDevices;
    final active = widget.pilot.runs.where((run) =>
      const {'queued','running','waiting_for_approval','waiting_for_tool'}
        .contains(run['status'])).length;
    final awaiting = widget.pilot.approvals.where((a) =>
      a['actionable'] == true).length;

    return ColoredBox(
      color: const Color(0xFFF5F7F9),
      child: RefreshIndicator(
        onRefresh: widget.preview ? () async {} : widget.pilot.refresh,
        child: ListView(
          key: const ValueKey('native-agent-directory'),
          padding: const EdgeInsets.fromLTRB(18, 14, 18, 36),
          children: [
            const OScreenTitle(
              eyebrow: 'YOUR AI CONTROL CENTER',
              title: 'Your AI work.\nAnywhere.',
              subtitle: 'Actual conversations, live desktop and exact '
                'permission requests from your own devices.'),
            const SizedBox(height: 18),
            Row(children: [
              _MetricCount('Online PCs', online,
                CupertinoIcons.device_laptop),
              const SizedBox(width: 9),
              _MetricCount('Active runs', active,
                CupertinoIcons.waveform_path_ecg),
              const SizedBox(width: 9),
              _MetricCount('Approvals', awaiting,
                CupertinoIcons.checkmark_shield),
            ]),
            const SizedBox(height: 14),
            OSurface(
              tint: OTheme.lavender,
              onTap: widget.onLegacy,
              child: const Row(children: [
                Icon(CupertinoIcons.desktopcomputer,
                  color: OTheme.violet, size: 27),
                SizedBox(width: 13),
                Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Open live PC screen',
                      style: TextStyle(fontSize: 16,
                        fontWeight: FontWeight.w800, color: OTheme.ink)),
                    SizedBox(height: 4),
                    Text('Existing remote projects and AI tools',
                      style: TextStyle(fontSize: 12,
                        color: OTheme.violet)),
                  ])),
                Icon(CupertinoIcons.chevron_right,
                  color: OTheme.violet),
              ])),
            const OSectionTitle('Find an agent'),
            CupertinoSearchTextField(
              backgroundColor: Colors.white,
              style: const TextStyle(color: OTheme.ink),
              itemColor: OTheme.violet,
              placeholder: 'Search Codex, ChatGPT, Claude, GitHub…',
              onChanged: (value) => setState(() => query = value)),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity,
              child: CupertinoSlidingSegmentedControl<String>(
                backgroundColor: const Color(0xFFE8EEF0),
                thumbColor: Colors.white,
                groupValue: filter,
                children: const {
                  'all': Padding(padding: EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),child: Text('All')),
                  'ready': Padding(padding: EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),child: Text('Ready')),
                  'other': Padding(padding: EdgeInsets.symmetric(
                    horizontal: 10, vertical: 7),child: Text('Remote')),
                },
                onValueChanged: (value) {
                  if (value != null) setState(() => filter = value);
                })),
            _section('Coding agents', entries.where((e) =>
              const ['codex','claude_sdk','copilot_sdk'].contains(e.id)).toList()),
            _section('Projects & IDE', entries.where((e) =>
              const ['vscode','github','cursor'].contains(e.id)).toList()),
            _section('AI apps on your shared screen', entries.where((e) =>
              const ['chatgpt','claude_web','gemini'].contains(e.id)).toList()),
            if (entries.isEmpty)
              const Padding(padding: EdgeInsets.all(25),
                child: Center(child: Text(
                  'No matching agents. Connect and synchronize your '
                  'trusted workspace to see eligible sessions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64727C))))),
            if (!widget.preview && available > 0)
              Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: CupertinoButton.filled(
                  onPressed: widget.onSessions,
                  child: const Text('Open real sessions & prompts'))),
            if (awaiting > 0 && widget.onInbox != null)
              Padding(padding: const EdgeInsets.only(top: 10),
                child: OutlinedButton.icon(
                  onPressed: widget.onInbox,
                  icon: const Icon(CupertinoIcons.checkmark_shield),
                  label: Text('Review $awaiting real permission requests'))),
            const Padding(padding: EdgeInsets.fromLTRB(4, 16, 4, 0),
              child: Text(
                'Shared-screen control uses visible PC permission. '
                'Consumer website chats are not copied into O-AGENT.',
                style: TextStyle(fontSize: 12,
                  color: Color(0xFF687B87), height: 1.5))),
          ],
        ),
      ),
    );
  }
}

class _MetricCount extends StatelessWidget {
  const _MetricCount(this.label, this.value, this.icon);
  final String label;
  final int value;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Expanded(
    child: OSurface(padding: const EdgeInsets.all(12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, color: OVisual.primary, size: 20),
        const SizedBox(height: 8),
        Text(value.toString(),style: const TextStyle(
          color: OTheme.ink,fontSize: 25,fontWeight: FontWeight.w800)),
        Text(label,maxLines: 2,
          style: const TextStyle(color: OVisual.secondary,fontSize: 11)),
      ])));
}

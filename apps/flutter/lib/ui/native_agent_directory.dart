import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

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
    this.preview = false,
  });

  final NativePilotController pilot;
  final VoidCallback onSessions, onDevices, onLegacy;
  final bool preview;

  @override
  State<NativeAgentDirectory> createState() => _NativeAgentDirectoryState();
}

class _NativeAgentDirectoryState extends State<NativeAgentDirectory> {
  String filter = 'all', query = '';

  bool _includes(AgentDirectoryEntry entry) {
    if (filter == 'ready' && !entry.hasVerifiedSession) return false;
    if (filter == 'other' && entry.state != AgentState.separateWorkspace &&
        entry.state != AgentState.externalOnly) return false;
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
        await _showInfo('Separate project connector',
          agent.summary + '\n\n'
          'This opens the earlier O-AGENT workspace, which uses a separate '
          'connection. It does not automatically import this private '
          'account or provide arbitrary third-party session control.',
          action: 'Open workspace', proceed: widget.onLegacy);
        return;
      case AgentRoute.officialService:
        final url = agent.officialUrl;
        if (url == null) return;
        await _showInfo('Official service only',
          'This opens ' + agent.name + ' in its official web experience. '
          'O-AGENT cannot read or control your existing consumer chats, '
          'browser permissions or private account sessions through this link.',
          action: 'Open official site', proceed: () async {
            try {
              final uri = Uri.parse(url);
              final opened = await launchUrl(uri,
                mode: LaunchMode.inAppBrowserView);
              if (!opened) throw StateError('Browser unavailable');
            } catch (_) {
              if (!mounted) return;
              await showCupertinoDialog<void>(context: context,
                builder: (dialog) => CupertinoAlertDialog(
                  title: const Text('Cannot open browser'),
                  content: const Text(
                    'Check that a compatible browser is installed.'),
                  actions: [CupertinoDialogAction(
                    onPressed: () => Navigator.of(dialog).pop(),
                    child: const Text('OK'))]));
            }
          });
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

  Color _statusColor(AgentState state) => switch (state) {
    AgentState.sessionReady => const Color(0xFF237C60),
    AgentState.workerEnabled => OTheme.violet,
    AgentState.offline => const Color(0xFF9E5F29),
    AgentState.needsSetup => const Color(0xFF687B87),
    AgentState.separateWorkspace => const Color(0xFF576A7F),
    AgentState.externalOnly => const Color(0xFF687B87),
  };

  Widget _tile(AgentDirectoryEntry agent) => CupertinoListTile(
    key: ValueKey('agent-' + agent.id),
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    leading: Container(
      width: 39, height: 39,
      decoration: BoxDecoration(color: OTheme.lavender,
        borderRadius: BorderRadius.circular(11)),
      alignment: Alignment.center,
      child: Icon(_icon(agent.id), size: 21, color: OTheme.violet),
    ),
    title: Text(agent.name, style: const TextStyle(
      color: OTheme.ink, fontSize: 15, fontWeight: FontWeight.w700)),
    subtitle: Padding(padding: const EdgeInsets.only(top: 5),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(agent.status,
            style: TextStyle(fontSize: 12,
              color: _statusColor(agent.state), fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(agent.summary, maxLines: 3, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Color(0xFF657781))),
        ])),
    trailing: const Icon(CupertinoIcons.chevron_forward,
      size: 15, color: Color(0xFF87969C)),
    onTap: () => _open(agent),
  );

  Widget _section(String title, List<AgentDirectoryEntry> items) {
    if (items.isEmpty) return const SizedBox.shrink();
    return CupertinoListSection.insetGrouped(
      header: Text(title, style: const TextStyle(
        color: OTheme.violet, fontWeight: FontWeight.w800,
        fontSize: 12, letterSpacing: 0.7)),
      backgroundColor: Colors.transparent,
      children: items.map(_tile).toList(),
    );
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

    return ColoredBox(
      color: const Color(0xFFF5F7F9),
      child: RefreshIndicator(
        onRefresh: widget.preview ? () async {} : widget.pilot.refresh,
        child: ListView(
          key: const ValueKey('native-agent-directory'),
          padding: const EdgeInsets.only(bottom: 30),
          children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 24, 20, 0),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('YOUR AI COMMAND CENTER',
                    style: TextStyle(fontSize: 12, letterSpacing: 1,
                      fontWeight: FontWeight.w800, color: OTheme.violet)),
                  const SizedBox(height: 6),
                  const Text('AI Agents', style: TextStyle(fontSize: 34,
                    fontWeight: FontWeight.w800, color: OTheme.ink)),
                  const SizedBox(height: 7),
                  Text(widget.preview
                    ? 'Explore providers. Sign in to see your verified sessions.'
                    : 'Choose an agent or project. Only real provider sessions '
                      'can be continued or approved.',
                    style: const TextStyle(fontSize: 14,
                      color: Color(0xFF64727C), height: 1.4)),
                  const SizedBox(height: 15),
                  if (!widget.preview)
                    Text('$available agent types with a verified live '
                      'session · ' + widget.pilot.onlineDevices.toString() +
                      ' online workers',
                      style: const TextStyle(fontSize: 12,
                        color: Color(0xFF64727C))),
                  const SizedBox(height: 16),
                  CupertinoSearchTextField(
                    placeholder: 'Search agents, sessions, integrations',
                    onChanged: (value) => setState(() => query = value)),
                  const SizedBox(height: 15),
                  SizedBox(width: double.infinity,
                    child: CupertinoSlidingSegmentedControl<String>(
                      groupValue: filter,
                      children: const {
                        'all': Padding(padding: EdgeInsets.symmetric(
                          horizontal: 8), child: Text('All')),
                        'ready': Padding(padding: EdgeInsets.symmetric(
                          horizontal: 8), child: Text('Ready')),
                        'other': Padding(padding: EdgeInsets.symmetric(
                          horizontal: 8), child: Text('More')),
                      },
                      onValueChanged: (value) {
                        if (value != null) setState(() => filter = value);
                      })),
                  const SizedBox(height: 6),
                ])),
            _section('CODING AGENTS', entries.where((e) =>
              const ['codex','claude_sdk','copilot_sdk'].contains(e.id)).toList()),
            _section('PROJECTS & IDE WORKSPACES', entries.where((e) =>
              const ['vscode','github','cursor'].contains(e.id)).toList()),
            _section('OTHER AI SERVICES', entries.where((e) =>
              const ['chatgpt','claude_web','gemini'].contains(e.id)).toList()),
            if (entries.isEmpty)
              const Padding(padding: EdgeInsets.all(25),
                child: Center(child: Text(
                  'No matching agents. Connect and synchronize your '
                  'trusted workspace to see eligible sessions.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Color(0xFF64727C))))),
            if (!widget.preview)
              Padding(padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
                child: CupertinoButton.filled(
                  onPressed: widget.onSessions,
                  child: const Text('Open real sessions & prompts'))),
            const Padding(padding: EdgeInsets.fromLTRB(21, 16, 21, 0),
              child: Text(
                'Connected means verified through the current authorized '
                'worker. Website shortcuts do not grant session access.',
                style: TextStyle(fontSize: 12,
                  color: Color(0xFF687B87), height: 1.5))),
          ],
        ),
      ),
    );
  }
}

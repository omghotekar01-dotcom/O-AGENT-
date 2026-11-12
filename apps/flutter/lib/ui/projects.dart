import 'dart:async';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/controller.dart';
import '../theme.dart';

const muted = Color(0xFF737771);
Map<String, dynamic> asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<Map<String, dynamic>> asItems(Object? value) =>
    value is List ? value.map((item) => asMap(item)).toList() : <Map<String, dynamic>>[];

class ProjectHubScreen extends StatefulWidget {
  const ProjectHubScreen({super.key, required this.controller});
  final ControlController controller;
  @override
  State<ProjectHubScreen> createState() => _ProjectHubState();
}
class _ProjectHubState extends State<ProjectHubScreen> {
  late Future<Map<String, dynamic>> future;
  Timer? timer;
  String filter = 'all';
  @override
  void initState() {
    super.initState();
    future = _load();
    timer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (mounted && widget.controller.connected) _refresh();
    });
  }
  Future<Map<String, dynamic>> _load() =>
      widget.controller.client?.projects() ?? Future.error('Backend disconnected');
  void _refresh() => setState(() => future = _load());
  @override
  void dispose() { timer?.cancel(); super.dispose(); }

  Future<void> _create() async {
    final title = TextEditingController();
    final description = TextEditingController();
    final form = await showDialog<Map<String, String>>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New O-AGENT project'),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: title, maxLength: 120,
            decoration: const InputDecoration(labelText: 'Project name')),
          const SizedBox(height: 10),
          TextField(controller: description, maxLength: 500, minLines: 2, maxLines: 3,
            decoration: const InputDecoration(labelText: 'What is it for?')),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (title.text.trim().isEmpty) return;
            Navigator.pop(ctx, {'title': title.text.trim(), 'description': description.text.trim()});
          }, child: const Text('Create')),
        ],
      ),
    );
    title.dispose(); description.dispose();
    if (form == null || !mounted) return;
    try {
      await widget.controller.client!.createProject(form['title']!, form['description']!);
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: future,
    builder: (context, snap) {
      final all = asItems(snap.data?['projects']);
      final sources = asItems(snap.data?['sources']);
      final errors = asItems(snap.data?['sourceErrors']);
      final shown = all.where((p) => filter == 'all' || p['source'] == filter).toList();
      return RefreshIndicator(
        onRefresh: () async { _refresh(); try { await future; } catch (_) {} },
        child: ListView(padding: const EdgeInsets.fromLTRB(22, 16, 22, 36), children: [
          Row(children: [
            const Expanded(child: Text('UNIFIED WORKSPACE', style: TextStyle(
              color: OTheme.violet, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 2))),
            IconButton(onPressed: _refresh, tooltip: 'Refresh', icon: const Icon(Icons.sync_rounded)),
          ]),
          const SizedBox(height: 9),
          const Text('Everything\nin motion.', style: TextStyle(
            color: OTheme.ink, fontWeight: FontWeight.w700, fontSize: 37,
            height: 1.12, letterSpacing: -1.2)),
          const SizedBox(height: 9),
          const Text('Real projects, cloud tasks and outputs from your connected sources.',
            style: TextStyle(color: muted, fontSize: 13, height: 1.5)),
          const SizedBox(height: 21),
          FilledButton.icon(onPressed: _create, icon: const Icon(Icons.add_rounded),
            label: const Text('New O-AGENT project')),
          const SizedBox(height: 23),
          if (snap.connectionState == ConnectionState.waiting)
            const LinearProgressIndicator(minHeight: 2),
          if (snap.hasError)
            InfoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Cannot read project feed', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 5),
              Text(snap.error.toString(), style: const TextStyle(color: muted, fontSize: 12)),
              TextButton(onPressed: _refresh, child: const Text('Retry')),
            ])),
          if (sources.isNotEmpty) ...[
            const Heading('Connected sources'),
            const SizedBox(height: 10),
            for (final source in sources)
              Padding(padding: const EdgeInsets.only(bottom: 8), child: InfoPanel(
                child: Row(children: [
                  Icon(sourceIcon(source['id']?.toString() ?? ''),
                    size: 22, color: OTheme.violet),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(source['label']?.toString() ?? '', style: const TextStyle(fontWeight: FontWeight.w700)),
                    Text((source['status'] ?? 'unknown').toString().replaceAll('_',' '),
                      style: const TextStyle(color: muted, fontSize: 11)),
                  ])),
                  Icon(source['status'] == 'unsupported' ? Icons.lock_outline : Icons.info_outline,
                    size: 16, color: muted),
                ]),
              )),
          ],
          if (errors.isNotEmpty) InfoPanel(
            background: const Color(0xFFF8ECE3),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Provider sync failed', style: TextStyle(fontWeight: FontWeight.w700)),
              for (final e in errors) Text(
                (e['repo'] ?? '').toString() + ': ' + (e['message'] ?? '').toString(),
                style: const TextStyle(color: muted, fontSize: 12)),
            ]),
          ),
          const SizedBox(height: 19),
          Heading('Projects · ' + all.length.toString()),
          const SizedBox(height: 12),
          SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
            for (final tab in const [
              ('all', 'All'), ('oagent', 'O-AGENT'),
              ('github', 'GitHub'), ('codex_cloud', 'Codex Cloud'),
            ])
              Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(
                label: Text(tab.$2), selected: filter == tab.$1,
                onSelected: (_) => setState(() => filter = tab.$1),
              )),
          ])),
          const SizedBox(height: 13),
          if (shown.isEmpty && !snap.hasError && snap.connectionState != ConnectionState.waiting)
            const InfoPanel(child: Column(children: [
              Icon(Icons.folder_open_rounded, color: OTheme.violet, size: 31),
              SizedBox(height: 12),
              Text('No projects from this source', style: TextStyle(fontWeight: FontWeight.w700)),
              SizedBox(height: 5),
              Text('Create a project or enable an authorized source. O-AGENT never invents cloud activity.',
                textAlign: TextAlign.center, style: TextStyle(color: muted, fontSize: 12, height: 1.5)),
            ])),
          for (final project in shown)
            Padding(padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(17),
                onTap: () => Navigator.push(context, MaterialPageRoute<void>(
                  builder: (_) => ProjectDetailScreen(
                    controller: widget.controller, projectId: project['id'].toString()))),
                child: InfoPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(sourceIcon(project['source']?.toString() ?? ''), size: 19, color: OTheme.violet),
                    const SizedBox(width: 8),
                    Text((project['source'] ?? '').toString().replaceAll('_', ' ').toUpperCase(),
                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1, color: muted)),
                    const Spacer(),
                    StatePill((project['state'] ?? 'unknown').toString()),
                  ]),
                  const SizedBox(height: 11),
                  Text(project['title']?.toString() ?? 'Project',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: OTheme.ink)),
                  if (project['description']?.toString().isNotEmpty == true) ...[
                    const SizedBox(height: 5),
                    Text(project['description'].toString(), maxLines: 2, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12, color: muted, height: 1.5)),
                  ],
                  const SizedBox(height: 13),
                  Row(children: [
                    Expanded(child: Text(project['control'] == 'read_only'
                      ? 'External source · read only' : 'Owned O-AGENT conversation',
                      style: const TextStyle(fontSize: 11, color: muted))),
                    const Icon(Icons.arrow_outward_rounded, size: 18, color: OTheme.ink),
                  ]),
                ])),
              ),
            ),
          const SizedBox(height: 14),
          const Text('Provider integrations are capability-based. GitHub and Codex Cloud views do not expose their live browser screens or permissions.',
            style: TextStyle(color: muted, fontSize: 11, height: 1.5)),
        ]),
      );
    },
  );
}

class ProjectDetailScreen extends StatefulWidget {
  const ProjectDetailScreen({super.key, required this.controller, required this.projectId});
  final ControlController controller;
  final String projectId;
  @override
  State<ProjectDetailScreen> createState() => _ProjectDetailState();
}
class _ProjectDetailState extends State<ProjectDetailScreen> {
  late Future<Map<String, dynamic>> future;
  final prompt = TextEditingController();
  bool sending = false;
  String? error;
  @override
  void initState() { super.initState(); future = _load(); }
  Future<Map<String, dynamic>> _load() =>
      widget.controller.client?.project(widget.projectId) ?? Future.error('Backend disconnected');
  void _refresh() => setState(() => future = _load());
  Future<void> _send() async {
    if (sending || prompt.text.trim().isEmpty) return;
    final message = prompt.text.trim();
    setState(() { sending = true; error = null; });
    try {
      await widget.controller.client!.promptProject(widget.projectId, message);
      prompt.clear();
      if (mounted) _refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }
  Future<void> _requestCodexTask(Map<String, dynamic> project) async {
    final workers = widget.controller.snapshot?.machines.where((m) => m.online).toList() ?? [];
    final id = project['workerId']?.toString();
    if (id == null || !workers.any((m) => m.id == id)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('The Codex laptop connector is offline. Start O-AGENT on the laptop.')));
      return;
    }
    final environment = TextEditingController(text: project['environmentId']?.toString() ?? '');
    final content = TextEditingController();
    final request = await showDialog<Map<String, String>>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Codex Cloud task'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, children: [
            const Text('This creates a NEW task, not a reply to an existing Codex session. You will review and approve the full prompt afterward.',
              style: TextStyle(fontSize: 12, color: muted)),
            const SizedBox(height: 12),
            TextField(controller: environment, maxLength: 120,
              decoration: const InputDecoration(labelText: 'Cloud environment ID')),
            const SizedBox(height: 9),
            TextField(controller: content, maxLength: 2000, maxLines: 5, minLines: 2,
              decoration: const InputDecoration(labelText: 'New task prompt')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (environment.text.trim().isEmpty || content.text.trim().isEmpty) return;
            Navigator.pop(ctx, {
              'environmentId': environment.text.trim(), 'prompt': content.text.trim(),
            });
          }, child: const Text('Request approval')),
        ],
      ),
    );
    environment.dispose();
    content.dispose();
    if (request == null || !mounted) return;
    try {
      await widget.controller.client!.requestCodexTask(
        workerId: id, environmentId: request['environmentId']!,
        prompt: request['prompt']!);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Created approval request. Return to Approvals to authorize the exact task.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  Future<void> _openUrl(Object? raw) async {
    final url = Uri.tryParse(raw?.toString() ?? '');
    if (url == null || url.scheme != 'https' ||
        !const {'github.com','chatgpt.com'}.contains(url.host)) return;
    final ok = await launchUrl(url, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open provider page')));
    }
  }
  @override
  void dispose() { prompt.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Project'), actions: [
      IconButton(onPressed: _refresh, icon: const Icon(Icons.sync_rounded)),
    ]),
    body: FutureBuilder<Map<String, dynamic>>(future: future,
      builder: (ctx, snap) {
        if (!snap.hasData) return Center(child: snap.hasError
          ? Padding(padding: const EdgeInsets.all(23), child: Text(snap.error.toString()))
          : const CircularProgressIndicator());
        final project = asMap(snap.data!['project']);
        final source = project['source']?.toString() ?? '';
        final messages = asItems(asMap(snap.data!['thread'])['messages']);
        final runs = asItems(project['runs']);
        final pulls = asItems(project['pullRequests']);
        return SafeArea(child: Column(children: [
          Expanded(child: ListView(padding: const EdgeInsets.all(22), children: [
            Text(source.toUpperCase().replaceAll('_', ' '),
              style: const TextStyle(fontSize: 10, letterSpacing: 2, fontWeight: FontWeight.w800, color: OTheme.violet)),
            const SizedBox(height: 12),
            Text(project['title']?.toString() ?? 'Project',
              style: const TextStyle(fontSize: 29, fontWeight: FontWeight.w700, letterSpacing: -1)),
            const SizedBox(height: 7),
            Text(project['description']?.toString() ?? '',
              style: const TextStyle(fontSize: 13, color: muted, height: 1.5)),
            const SizedBox(height: 12),
            Row(children: [
              StatePill((project['state'] ?? 'unknown').toString()),
              const SizedBox(width: 12),
              Expanded(child: Text(project['control'] == 'read_only'
                ? 'Read-only provider status' : 'O-AGENT-owned runtime',
                style: const TextStyle(fontSize: 11, color: muted))),
            ]),
            if (project['stale'] == true) const Padding(
              padding: EdgeInsets.only(top: 13),
              child: Text('Task feed is stale. Check the connector.', style: TextStyle(color: Color(0xFFA65B41)))),
            if (source != 'oagent') ...[
              const SizedBox(height: 14),
              OutlinedButton.icon(onPressed: project['url'] == null
                ? null : () => _openUrl(project['url']),
                icon: const Icon(Icons.open_in_new), label: const Text('Open provider page')),
              const SizedBox(height: 10),
              Text(source == 'codex_cloud'
                ? 'Existing cloud tasks are read-only. A NEW Codex task can be submitted through your signed-in laptop after explicit approval.'
                : 'This external source is read-only; browser viewing and provider approvals are not exposed.',
                style: const TextStyle(fontSize: 12, color: muted, height: 1.5)),
              if (source == 'codex_cloud') ...[
                const SizedBox(height: 13),
                FilledButton.icon(onPressed: () => _requestCodexTask(project),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Request new Codex Cloud task')),
              ],
            ],
            if (runs.isNotEmpty) ...[
              const SizedBox(height: 24), const Heading('Workflow runs'),
              const SizedBox(height: 10),
              for (final run in runs)
                Padding(padding: const EdgeInsets.only(bottom: 9),
                  child: InkWell(onTap: () => _openUrl(run['url']), child: InfoPanel(
                    child: Row(children: [
                      Expanded(child: Text(run['title']?.toString() ?? 'Workflow')),
                      StatePill((run['status'] ?? 'unknown').toString()),
                      const Icon(Icons.chevron_right, size: 18),
                    ]),
                  ))),
            ],
            if (pulls.isNotEmpty) ...[
              const SizedBox(height: 24), const Heading('Pull requests'),
              const SizedBox(height: 10),
              for (final pr in pulls)
                Padding(padding: const EdgeInsets.only(bottom: 9),
                  child: InkWell(onTap: () => _openUrl(pr['url']), child: InfoPanel(
                    child: Row(children: [
                      Expanded(child: Text(pr['title']?.toString() ?? 'Pull request')),
                      StatePill((pr['status'] ?? 'unknown').toString()),
                      const Icon(Icons.chevron_right, size: 18),
                    ]),
                  ))),
            ],
            if (source == 'oagent') ...[
              const SizedBox(height: 22), const Heading('Project conversation'),
              const SizedBox(height: 10),
              if (messages.isEmpty)
                const InfoPanel(child: Text(
                  'Send your objective here. O-AGENT will use its configured AI provider. This does not inject a prompt into other applications.',
                  style: TextStyle(fontSize: 12, height: 1.5, color: muted))),
              for (final msg in messages)
                Padding(padding: const EdgeInsets.only(bottom: 10), child: InfoPanel(
                  background: msg['role'] == 'user' ? OTheme.lavender : Colors.white,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(msg['role'] == 'user' ? 'YOU' : 'O-AGENT',
                      style: const TextStyle(color: OTheme.violet, fontSize: 10, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 7),
                    SelectableText(msg['content']?.toString() ?? '',
                      style: const TextStyle(fontSize: 13, height: 1.5)),
                  ]),
                )),
            ],
          ])),
          if (source == 'oagent')
            Container(
              padding: const EdgeInsets.fromLTRB(15, 10, 15, 15),
              decoration: const BoxDecoration(color: OTheme.paper,
                border: Border(top: BorderSide(color: OTheme.hairline))),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                if (error != null) Padding(padding: const EdgeInsets.only(bottom: 8),
                  child: Text(error!, style: const TextStyle(color: Color(0xFF9F463A), fontSize: 12))),
                Row(children: [
                  Expanded(child: TextField(controller: prompt, maxLength: 4000,
                    minLines: 1, maxLines: 3, enabled: !sending,
                    decoration: const InputDecoration(hintText: 'Send to this project', counterText: ''))),
                  const SizedBox(width: 9),
                  IconButton.filled(onPressed: sending ? null : _send,
                    icon: sending ? const SizedBox(height: 17, width: 17,
                      child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.arrow_upward)),
                ]),
              ]),
            ),
        ]));
      }),
  );
}

IconData sourceIcon(String source) => switch (source) {
  'github' => Icons.code_rounded,
  'codex_cloud' => Icons.cloud_outlined,
  'oagent' => Icons.auto_awesome_rounded,
  _ => Icons.extension_rounded,
};
class Heading extends StatelessWidget {
  const Heading(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) =>
      Text(text, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: OTheme.ink));
}
class StatePill extends StatelessWidget {
  const StatePill(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(color: OTheme.lavender, borderRadius: BorderRadius.circular(18)),
    child: Text(text.replaceAll('_', ' '),
      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: OTheme.violet)),
  );
}
class InfoPanel extends StatelessWidget {
  const InfoPanel({super.key, required this.child, this.background = Colors.white});
  final Widget child;
  final Color background;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity, padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(color: background,
      borderRadius: BorderRadius.circular(17),
      border: Border.all(color: OTheme.hairline)),
    child: child,
  );
}

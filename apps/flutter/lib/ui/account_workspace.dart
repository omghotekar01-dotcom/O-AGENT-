import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/controller.dart';
import '../core/api_client.dart';
import '../theme.dart';

/// Personal account workspace. Every operation is authenticated and scoped to
/// this invited account. No member ever receives the owner's machine controls.
class AccountWorkspaceScreen extends StatefulWidget {
  const AccountWorkspaceScreen({super.key, required this.controller});
  final ControlController controller;
  @override
  State<AccountWorkspaceScreen> createState() => _AccountWorkspaceState();
}

class _AccountWorkspaceState extends State<AccountWorkspaceScreen> {
  final message = TextEditingController();
  List<Map<String, dynamic>> providers = [];
  List<Map<String, dynamic>> threads = [];
  List<Map<String, dynamic>> members = [];
  List<Map<String, dynamic>> storedAttachments = [];
  List<Map<String, dynamic>> stagedAttachments = [];
  bool uploading = false;
  Map<String, dynamic> github = {};
  List<Map<String, dynamic>> githubRepos = [];
  String? selectedGithubRepo;
  Map<String, dynamic>? conversation;
  Map<String, dynamic>? invite;
  String selectedProvider = 'openai';
  String? error;
  int tab = 0;
  bool loading = false, sending = false;

  bool get owner => !widget.controller.isMember;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    message.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (loading || widget.controller.client == null) return;
    setState(() => loading = true);
    try {
      final api = widget.controller.client!;
      final response = await api.accountConnections();
      final fetched = (response['providers'] as List? ?? [])
        .map((x) => Map<String, dynamic>.from(x as Map)).toList();
      final recent = await api.accountThreads();
      final files = await api.accountAttachments();
      final git = await api.githubStatus();
      final repositories = git['connected'] == true ? await api.githubRepos() : <Map<String, dynamic>>[];
      final people = owner ? await api.members() : <Map<String, dynamic>>[];
      if (!mounted) return;
      setState(() {
        providers = fetched;
        threads = recent;
        members = people;
        storedAttachments = files;
        github = git;
        githubRepos = repositories;
        if (!providers.any((p) => p['id'] == selectedProvider && p['connected'] == true)) {
          for (final p in providers) {
            if (p['connected'] == true) {
              selectedProvider = p['id'].toString();
              break;
            }
          }
        }
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  Map<String, dynamic> _provider(String id) {
    for (final p in providers) {
      if (p['id'] == id) return p;
    }
    return {'id': id, 'connected': false, 'model': ''};
  }

  Future<void> _openKeyConsole(String provider) async {
    final urls = {
      'openai': 'https://platform.openai.com/api-keys',
      'anthropic': 'https://console.anthropic.com/',
      'gemini': 'https://aistudio.google.com/apikey',
    };
    final target = Uri.parse(urls[provider] ?? urls['openai']!);
    final opened = await launchUrl(target, mode: LaunchMode.externalApplication);
    if (!opened && mounted) setState(() => error = 'Could not open the provider API key page');
  }

  Future<void> _saveProvider(Map<String, dynamic> existing) async {
    final provider = existing['id'].toString();
    final model = TextEditingController(text: existing['model']?.toString() ?? '');
    final key = TextEditingController();
    var showKey = false;
    final form = await showDialog<Map<String, String>>(context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, update) => AlertDialog(
        title: Text('Connect ${existing['label']}'),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Use your own provider API account. The key is sent over HTTPS and encrypted on your O-AGENT backend, never bundled into the app.',
              style: TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 9),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new_rounded, size: 18),
              onPressed: () => _openKeyConsole(provider),
              label: const Text('Get a key from the provider'),
            ),
            const SizedBox(height: 8),
            TextField(controller: model, maxLength: 120,
              decoration: const InputDecoration(labelText: 'Model ID',
                prefixIcon: Icon(Icons.auto_awesome_outlined))),
            const SizedBox(height: 10),
            TextField(controller: key, obscureText: !showKey, autocorrect: false,
              enableSuggestions: false, keyboardType: TextInputType.visiblePassword,
              decoration: InputDecoration(
                labelText: existing['connected'] == true ? 'New API key (optional)' : 'Your API key',
                prefixIcon: const Icon(Icons.key_rounded),
                helperText: existing['connected'] == true ? 'Leave blank to keep the saved encrypted key.' : null,
                suffixIcon: IconButton(
                  onPressed: () => update(() => showKey = !showKey),
                  icon: Icon(showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined)),
              )),
            const SizedBox(height: 10),
            const Text('An API key may incur charges from its provider. A ChatGPT, Claude or Gemini subscription is not always the same as API billing.',
              style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () {
            if (model.text.trim().isEmpty ||
                (existing['connected'] != true && key.text.trim().isEmpty)) return;
            Navigator.pop(ctx, {
              'model': model.text.trim(),
              if (key.text.trim().isNotEmpty) 'apiKey': key.text.trim(),
            });
          }, child: const Text('Save securely')),
        ],
      )));
    // Controllers are disposed after the dialog; credentials are never written
    // to persistent phone storage, logs, or GitHub.
    model.dispose();
    key.dispose();
    if (form == null || !mounted) return;
    try {
      await widget.controller.client!.setAccountConnection(
        provider: provider, model: form['model']!, apiKey: form['apiKey']);
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _verify(String id) async {
    setState(() { loading = true; error = null; });
    try {
      await widget.controller.client!.verifyAccountConnection(id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Real provider connection verified. API usage may be billable.')));
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
      // Avoid _load's busy guard while verifying.
      if (mounted) await _load();
    }
  }

  Future<void> _remove(String id) async {
    final confirmed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect this provider?'),
        content: const Text('The encrypted API key will be erased from this account. Existing private conversations remain available.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ));
    if (confirmed != true || !mounted) return;
    try {
      await widget.controller.client!.deleteAccountConnection(id);
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _connectGithub() async {
    final input = TextEditingController();
    try {
      final secret = await showDialog<String>(context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Connect personal GitHub'),
          content: SingleChildScrollView(child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Use a fine-grained personal access token with '
                'read-only Metadata and Contents access to repositories you choose. '
                'O-AGENT verifies it with GitHub before reporting a connection. '
                'It cannot push code or control GitHub Actions with this integration.',
                style: TextStyle(fontSize: 12, height: 1.5)),
              const SizedBox(height: 12),
              TextField(controller: input, obscureText: true,
                enableSuggestions: false, autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Personal access token',
                  prefixIcon: Icon(Icons.key_outlined))),
            ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, input.text.trim()),
              child: const Text('Verify and connect')),
          ],
        ),
      );
      if (secret == null || secret.isEmpty || !mounted) return;
      setState(() { loading = true; error = null; });
      await widget.controller.client!.connectGithub(secret);
      if (!mounted) return;
      setState(() => loading = false);
      await _load();
    } catch (e) {
      if (mounted) setState(() { error = e.toString(); loading = false; });
    } finally {
      input.dispose();
    }
  }

  Future<void> _disconnectGithub() async {
    try {
      await widget.controller.client!.disconnectGithub();
      if (!mounted) return;
      setState(() { selectedGithubRepo = null; });
      await _load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  void _askAboutRepo(String name) {
    if (stagedAttachments.length >= 3) {
      setState(() => error = 'Remove one attachment before selecting GitHub context.');
      return;
    }
    setState(() {
      selectedGithubRepo = name;
      conversation = null;
      tab = 0;
      message.text = 'Review the README in this repository and suggest specific next steps.';
    });
  }

  Future<void> _pickFile() async {
    if (uploading || stagedAttachments.length >= (selectedGithubRepo == null ? 3 : 2)) return;
    try {
      final file = await FilePicker.pickFile(type: FileType.custom,
        allowedExtensions: ['txt', 'md', 'pdf', 'png', 'jpg', 'jpeg', 'webp', 'docx']);
      if (file == null) return;
      final length = file.lengthSync() ?? await file.length();
      if (length < 1 || length > 1500000) {
        throw const ApiException('Choose a file of 1.5 MB or less.');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 1500000) {
        throw const ApiException('Choose a file of 1.5 MB or less.');
      }
      const types = {
        'txt': 'text/plain', 'md': 'text/markdown', 'pdf': 'application/pdf',
        'png': 'image/png', 'jpg': 'image/jpeg', 'jpeg': 'image/jpeg',
        'webp': 'image/webp',
        'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
      };
      final mime = types[file.extension?.toLowerCase()];
      if (mime == null) throw const ApiException('File type unsupported');
      setState(() { uploading = true; error = null; });
      final saved = await widget.controller.client!.uploadAccountAttachment(
        name: file.name, mimeType: mime, base64: base64Encode(bytes));
      if (!mounted) return;
      setState(() {
        stagedAttachments.add(saved);
        storedAttachments.insert(0, saved);
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> _deleteFile(String id) async {
    try {
      await widget.controller.client!.deleteAccountAttachment(id);
      if (!mounted) return;
      setState(() {
        stagedAttachments.removeWhere((f) => f['id'] == id);
        storedAttachments.removeWhere((f) => f['id'] == id);
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _send() async {
    final prompt = message.text.trim();
    if (sending || prompt.isEmpty) return;
    if (_provider(selectedProvider)['connected'] != true) {
      setState(() => tab = 1);
      return;
    }
    setState(() { sending = true; error = null; });
    try {
      final next = await widget.controller.client!.accountChat(
        provider: selectedProvider, message: prompt,
        attachmentIds: stagedAttachments.map((f) => f['id'].toString()).toList(),
        githubRepository: selectedGithubRepo,
        threadId: conversation?['id']?.toString());
      if (!mounted) return;
      message.clear();
      setState(() { conversation = next; stagedAttachments.clear(); selectedGithubRepo = null; });
      threads = await widget.controller.client!.accountThreads();
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _openThread(String id) async {
    try {
      final next = await widget.controller.client!.accountThread(id);
      if (!mounted) return;
      setState(() {
        conversation = next;
        selectedProvider = next['provider']?.toString() ?? selectedProvider;
        tab = 0;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _invite() async {
    try {
      final result = await widget.controller.client!.createInvitation('Invited mobile user');
      if (mounted) setState(() => invite = result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> _revoke(Map<String, dynamic> person) async {
    final yes = await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: const Text('Revoke member access?'),
      content: Text('Revoke ${person['displayName']}? Their token will stop working, and their stored provider keys and conversations will be deleted from this backend.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Revoke access')),
      ],
    ));
    if (yes != true || !mounted) return;
    try {
      await widget.controller.client!.revokeMember(person['id'].toString());
      await _load();
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My AI workspace'),
        actions: [IconButton(onPressed: _load, icon: const Icon(Icons.sync_rounded),
          tooltip: 'Refresh connections')]),
      body: SafeArea(child: Column(children: [
        Padding(padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
          child: Row(children: [
            Expanded(child: _TabButton(label: 'Chat', selected: tab == 0,
              icon: Icons.chat_bubble_outline, onTap: () => setState(() => tab = 0))),
            const SizedBox(width: 7),
            Expanded(child: _TabButton(label: 'Connections', selected: tab == 1,
              icon: Icons.hub_outlined, onTap: () => setState(() => tab = 1))),
            const SizedBox(width: 7),
            Expanded(child: _TabButton(label: 'Account', selected: tab == 2,
              icon: Icons.person_outline, onTap: () => setState(() => tab = 2))),
          ])),
        if (loading) const LinearProgressIndicator(minHeight: 2),
        if (error != null) Padding(padding: const EdgeInsets.fromLTRB(18, 6, 18, 0),
          child: Card(color: const Color(0xFFFFF0EB), child: Padding(
            padding: const EdgeInsets.all(12), child: Text(error!,
              style: const TextStyle(color: Color(0xFF9B4835), fontSize: 12))))),
        Expanded(child: switch (tab) {
          0 => _chatView(),
          1 => _connectionsView(),
          _ => _accountView(),
        }),
        if (tab == 0) _composer(),
      ])),
    );
  }

  Widget _chatView() => ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
    children: [
      const Text('PRIVATE AI CONVERSATIONS', style: TextStyle(fontSize: 10,
        color: OTheme.violet, fontWeight: FontWeight.w800, letterSpacing: 1.6)),
      const SizedBox(height: 8),
      Text('Work with your own AI.', style: TextStyle(fontSize: 28,
        fontWeight: FontWeight.w800, color: OTheme.ink)),
      const SizedBox(height: 8),
      const Text('Choose a provider you connected. Conversations are separate for each O-AGENT user.',
        style: TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 14),
      SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
        for (final p in providers)
          Padding(padding: const EdgeInsets.only(right: 7), child: ChoiceChip(
            label: Text(p['label']?.toString() ?? p['id'].toString()),
            selected: selectedProvider == p['id'],
            onSelected: (_) => setState(() {
              selectedProvider = p['id'].toString();
              conversation = null;
            }),
          )),
      ])),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Text(_provider(selectedProvider)['connected'] == true
          ? 'Connected model: ${_provider(selectedProvider)['model']}'
          : 'Connect this API provider in the Connections tab first',
          style: const TextStyle(fontSize: 12, color: Colors.grey))),
        TextButton.icon(onPressed: () => setState(() => conversation = null),
          icon: const Icon(Icons.add, size: 17), label: const Text('New chat')),
      ]),
      const SizedBox(height: 12),
      if (conversation == null && threads.isNotEmpty) ...[
        const Text('Recent private conversations', style: TextStyle(
          fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 9),
        for (final t in threads.where((t) => t['provider'] == selectedProvider).take(12))
          Padding(padding: const EdgeInsets.only(bottom: 7),
            child: OutlinedButton.icon(
              icon: const Icon(Icons.history_rounded),
              label: Text(t['title']?.toString() ?? 'Conversation',
                overflow: TextOverflow.ellipsis),
              onPressed: () => _openThread(t['id'].toString()),
            )),
      ],
      if (conversation == null && threads.isEmpty)
        const _Panel(child: Text('No conversations yet. Start by connecting your own provider and sending a message.',
          style: TextStyle(fontSize: 13, height: 1.6))),
      for (final item in (conversation?['messages'] as List? ?? []))
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: _Panel(color: item['role'] == 'user' ? OTheme.lavender : Colors.white,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(item['role'] == 'user' ? 'YOU' : selectedProvider.toUpperCase(),
                style: const TextStyle(color: OTheme.violet, fontSize: 10, fontWeight: FontWeight.w800)),
              const SizedBox(height: 8),
              SelectableText(item['content']?.toString() ?? '',
                style: const TextStyle(fontSize: 13, height: 1.6)),
            ]))),
      if (sending) const _Panel(child: Row(children: [
        SizedBox(width: 15, height: 15, child: CircularProgressIndicator(strokeWidth: 2)),
        SizedBox(width: 10),
        Text('Waiting for real provider response…'),
      ])),
    ]);

  Widget _composer() => Container(padding: const EdgeInsets.fromLTRB(15, 10, 15, 16),
    decoration: const BoxDecoration(color: OTheme.paper,
      border: Border(top: BorderSide(color: OTheme.hairline))),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      if (selectedGithubRepo != null)
        InputChip(label: Text('README: ' + selectedGithubRepo!),
          onDeleted: () => setState(() => selectedGithubRepo = null)),
      if (stagedAttachments.isNotEmpty)
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
          for (final file in stagedAttachments)
            Padding(padding: const EdgeInsets.only(right: 5), child: InputChip(
              label: Text(file['name']?.toString() ?? 'File'),
              onDeleted: () => _deleteFile(file['id'].toString()))),
        ])),
      Row(children: [
        IconButton(
          tooltip: 'Attach image, PDF, text or DOCX (1.5 MB)',
          onPressed: sending || uploading || stagedAttachments.length >= (selectedGithubRepo == null ? 3 : 2)
            ? null : _pickFile,
          icon: uploading ? const SizedBox(width: 19, height: 19,
            child: CircularProgressIndicator(strokeWidth: 2)) :
            const Icon(Icons.attach_file_rounded)),
        Expanded(child: TextField(controller: message, minLines: 1, maxLines: 4,
          maxLength: 4000, enabled: !sending,
          decoration: const InputDecoration(hintText: 'Message your own AI',
            counterText: ''))),
        const SizedBox(width: 8),
        IconButton.filled(onPressed: sending || uploading ? null : _send,
          tooltip: 'Send to selected API provider',
          icon: const Icon(Icons.arrow_upward_rounded)),
      ]),
    ]));

  Widget _connectionsView() => ListView(padding: const EdgeInsets.fromLTRB(18, 14, 18, 20),
    children: [
      const Text('YOUR PROVIDER CREDENTIALS', style: TextStyle(fontSize: 10,
        color: OTheme.violet, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
      const SizedBox(height: 8),
      const Text('Connect your own AI.', style: TextStyle(fontSize: 28,
        fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      const Text('No provider keys are built into this app. Every account stores its own keys encrypted in the O-AGENT backend vault.',
        style: TextStyle(color: Colors.grey, fontSize: 12, height: 1.6)),
      const SizedBox(height: 16),
      for (final p in providers)
        Padding(padding: const EdgeInsets.only(bottom: 10),
          child: _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Container(padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(color: OTheme.lavender,
                  borderRadius: BorderRadius.circular(12)),
                child: Icon(p['id'] == 'gemini' ? Icons.auto_awesome_rounded
                  : p['id'] == 'anthropic' ? Icons.psychology_outlined
                  : Icons.smart_toy_outlined, color: OTheme.violet)),
              const SizedBox(width: 11),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(p['label']?.toString() ?? p['id'].toString(),
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                Text(p['connected'] == true ? '${p['model']} · ${p['status']}'
                  : 'Not connected',
                  style: const TextStyle(color: Colors.grey, fontSize: 11)),
              ])),
              Icon(p['status'] == 'connected' ? Icons.check_circle_rounded
                  : Icons.circle_outlined,
                color: p['status'] == 'connected' ? const Color(0xFF438267) : Colors.grey,
                size: 19),
            ]),
            const SizedBox(height: 11),
            Row(children: [
              Expanded(child: FilledButton.tonal(
                onPressed: () => _saveProvider(p),
                child: Text(p['connected'] == true ? 'Change key or model' : 'Connect API key'))),
              if (p['connected'] == true) ...[
                const SizedBox(width: 7),
                OutlinedButton(onPressed: loading ? null : () => _verify(p['id'].toString()),
                  child: const Text('Test')),
                IconButton(tooltip: 'Remove encrypted key',
                  onPressed: () => _remove(p['id'].toString()),
                  icon: const Icon(Icons.link_off_outlined)),
              ],
            ]),
            if (p['lastError']?.toString().isNotEmpty == true)
              Text(p['lastError'].toString(), style: const TextStyle(
                fontSize: 11, color: Color(0xFF9B4835))),
          ])),
        ),
      const SizedBox(height: 20),
      const Text('GITHUB CODING CONTEXT', style: TextStyle(fontSize: 10,
        color: OTheme.violet, fontWeight: FontWeight.w800, letterSpacing: 1.4)),
      const SizedBox(height: 8),
      const Text('Link your own GitHub repositories',
        style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(github['connected'] == true ?
        'Verified as ' + (github['login']?.toString() ?? 'GitHub user') +
          '. Read-only repository metadata and README context.' :
        'Connect a read-only fine-grained personal access token. '
          'Only your GitHub account is used.',
        style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.5)),
      const SizedBox(height: 12),
      if (github['connected'] == true)
        OutlinedButton.icon(onPressed: _disconnectGithub,
          icon: const Icon(Icons.link_off_outlined),
          label: const Text('Disconnect GitHub'))
      else
        FilledButton.tonalIcon(onPressed: loading ? null : _connectGithub,
          icon: const Icon(Icons.code_rounded), label: const Text('Connect GitHub account')),
      if (github['connected'] == true) ...[
        const SizedBox(height: 12),
        for (final repo in githubRepos)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(repo['fullName']?.toString() ?? ''),
            subtitle: Text(repo['private'] == true ? 'Private repository' : 'Public repository'),
            trailing: TextButton(
              onPressed: () => _askAboutRepo(repo['fullName'].toString()),
              child: const Text('Ask AI')),
          ),
      ],
      const SizedBox(height: 14),
      const _Panel(child: Text('Only OpenAI, Claude/Anthropic and Gemini API-owned conversations are supported here today. This does not import existing ChatGPT/Claude/Gemini website chats or control their browser tabs.',
        style: TextStyle(fontSize: 11, height: 1.6, color: Colors.grey))),
    ]);

  Widget _accountView() => ListView(padding: const EdgeInsets.fromLTRB(18, 16, 18, 24),
    children: [
      const Text('ACCOUNT & PRIVACY', style: TextStyle(fontSize: 10,
        letterSpacing: 1.5, color: OTheme.violet, fontWeight: FontWeight.w800)),
      const SizedBox(height: 8),
      Text(widget.controller.accountDisplayName,
        style: const TextStyle(fontSize: 27, fontWeight: FontWeight.w800)),
      Text(owner ? 'Workspace owner · machine control available in main app'
        : 'Invited member · private AI chats only',
        style: const TextStyle(color: Colors.grey, fontSize: 12)),
      const SizedBox(height: 17),
      _Panel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Connected backend', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 5),
        SelectableText(widget.controller.endpoint ?? '',
          style: const TextStyle(fontSize: 11)),
        const SizedBox(height: 12),
        const Text('Provider keys are encrypted on this backend. Conversation text is stored in its local development database. Do not use a shared or untrusted host.',
          style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.6)),
      ])),
      if (owner) ...[
        const SizedBox(height: 24),
        const Text('Invite another user', style: TextStyle(fontSize: 19,
          fontWeight: FontWeight.w800)),
        const SizedBox(height: 6),
        const Text('Only people with an owner-generated one-time invitation and the private backend HTTPS address can join. Invitation expires after 15 minutes.',
          style: TextStyle(fontSize: 11, color: Colors.grey, height: 1.5)),
        const SizedBox(height: 12),
        FilledButton.icon(onPressed: _invite,
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: const Text('Generate one-time invitation')),
        if (invite != null) ...[
          const SizedBox(height: 10),
          _Panel(color: OTheme.lavender, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Share privately with your invited person',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
              const SizedBox(height: 8),
              SelectableText(invite!['invitationCode']?.toString() ?? '',
                style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => Clipboard.setData(ClipboardData(
                  text: invite!['invitationCode']?.toString() ?? '')),
                icon: const Icon(Icons.copy_outlined),
                label: const Text('Copy invitation code')),
            ])),
        ],
        const SizedBox(height: 20),
        const Text('Invited members', style: TextStyle(fontSize: 19,
          fontWeight: FontWeight.w800)),
        for (final person in members)
          ListTile(contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.person_outline),
            title: Text(person['displayName']?.toString() ?? 'Member'),
            subtitle: Text(person['revoked'] == true ? 'Access revoked' : 'Private chats only'),
            trailing: person['revoked'] == true ? null
              : IconButton(onPressed: () => _revoke(person),
                  icon: const Icon(Icons.person_remove_outlined),
                  tooltip: 'Revoke member'),
          ),
      ],
      const SizedBox(height: 20),
      const Text('My uploaded files', style: TextStyle(fontSize: 19,
        fontWeight: FontWeight.w800)),
      const Text('Files are encrypted on this backend. Remove ones you no longer need.',
        style: TextStyle(fontSize: 11, color: Colors.grey)),
      for (final file in storedAttachments)
        ListTile(contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.insert_drive_file_outlined),
          title: Text(file['name']?.toString() ?? 'File'),
          subtitle: Text(file['size'].toString() + ' bytes'),
          trailing: IconButton(onPressed: () => _deleteFile(file['id'].toString()),
            tooltip: 'Delete file', icon: const Icon(Icons.delete_outline_rounded))),
      const SizedBox(height: 24),
      OutlinedButton.icon(onPressed: () => widget.controller.disconnect(),
        icon: const Icon(Icons.logout_rounded), label: const Text('Disconnect this device')),
    ]);

}
class _TabButton extends StatelessWidget {
  const _TabButton({required this.label, required this.selected,
    required this.icon, required this.onTap});
  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(13), onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 7),
      decoration: BoxDecoration(
        color: selected ? OTheme.lavender : Colors.white,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: selected ? OTheme.violet : OTheme.hairline)),
      child: Column(children: [
        Icon(icon, color: OTheme.violet, size: 19),
        const SizedBox(height: 4),
        Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
          maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
    ),
  );
}
class _Panel extends StatelessWidget {
  const _Panel({required this.child, this.color = Colors.white});
  final Widget child;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(15),
    decoration: BoxDecoration(
      color: color, borderRadius: BorderRadius.circular(17),
      border: Border.all(color: OTheme.hairline)),
    child: child,
  );
}

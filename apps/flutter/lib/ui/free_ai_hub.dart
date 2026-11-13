import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';

/// Convenience links, not account/session integrations. Official consumer web
/// apps manage their own login, limits and chat history. O-AGENT cannot read
/// or act in those tabs without a separately verified provider interface.
class FreeAiHubScreen extends StatefulWidget {
  const FreeAiHubScreen({super.key});

  @override
  State<FreeAiHubScreen> createState() => _FreeAiHubScreenState();
}

class _FreeAiHubScreenState extends State<FreeAiHubScreen> {
  static const _storage = FlutterSecureStorage();
  static const _key = 'oagent.manual_ai_shortcuts.v1';
  static const _sites = <({String title, String url, String description})>[
    (title: 'ChatGPT', url: 'https://chatgpt.com/',
      description: 'Open your real ChatGPT chats and Projects; account sign-in may be required'),
    (title: 'Grok', url: 'https://grok.com/',
      description: 'Consumer Grok chat; limited free access where available'),
    (title: 'Gemini', url: 'https://gemini.google.com/',
      description: 'Google AI web chat; free-tier limits may apply'),
    (title: 'Claude', url: 'https://claude.ai/',
      description: 'Claude web chat; free-tier limits may apply'),
    (title: 'DeepSeek', url: 'https://chat.deepseek.com/',
      description: 'DeepSeek web chat; access and limits depend on provider'),
    (title: 'Perplexity', url: 'https://www.perplexity.ai/',
      description: 'AI-powered web search with a limited free plan'),
    (title: 'Microsoft Copilot', url: 'https://copilot.microsoft.com/',
      description: 'Microsoft web AI assistant; feature limits may apply'),
    (title: 'OpenRouter free models', url: 'https://openrouter.ai/collections/free-models',
      description: 'Developer API model catalog; free models require an account/key'),
  ];
  static const _allowedHosts = <String>{
    'chatgpt.com', 'chat.openai.com', 'grok.com', 'gemini.google.com',
    'claude.ai', 'chat.deepseek.com', 'perplexity.ai',
    'copilot.microsoft.com', 'openrouter.ai',
  };

  final _label = TextEditingController();
  final _address = TextEditingController();
  List<Map<String, String>> _pins = const [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadPins();
  }

  @override
  void dispose() {
    _label.dispose();
    _address.dispose();
    super.dispose();
  }

  Future<void> _loadPins() async {
    try {
      final raw = await _storage.read(key: _key);
      if (!mounted || raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      setState(() {
        _pins = decoded.whereType<Map>().map((v) =>
          {'label': (v['label'] ?? '').toString(),
           'url': (v['url'] ?? '').toString()}).where((v) =>
             v['label']!.isNotEmpty && _validWebLink(v['url']!)).take(12).toList();
      });
    } catch (_) {
      if (mounted) setState(() => _error =
        'Saved shortcuts could not be read from this device.');
    }
  }

  bool _validWebLink(String input) {
    final uri = Uri.tryParse(input);
    if (uri == null || uri.scheme != 'https' ||
        uri.userInfo.isNotEmpty || uri.hasPort || uri.host.isEmpty) return false;
    final host = uri.host.toLowerCase();
    return _allowedHosts.any((known) => host == known ||
        (known == 'perplexity.ai' && host == 'www.perplexity.ai'));
  }

  Future<void> _launch(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !_validWebLink(url)) {
      setState(() => _error = 'Only official HTTPS AI websites can be opened here.');
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
      if (!opened) throw Exception('No compatible browser installed.');
    } catch (_) {
      try {
        final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!opened) throw Exception('No browser available');
      } catch (_) {
        if (mounted) setState(() => _error =
          'Could not open the official web app. Check your browser and try again.');
      }
    }
  }

  Future<void> _savePin() async {
    final name = _label.text.trim();
    final url = _address.text.trim();
    if (name.isEmpty || name.length > 70 || !_validWebLink(url)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Enter a project name and a valid official HTTPS AI link.')));
      return;
    }
    if (_pins.length >= 12) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Maximum 12 shortcuts. Remove an existing one first.')));
      return;
    }
    final updated = <Map<String, String>>[
      ..._pins.where((item) => item['url'] != url),
      {'label': name, 'url': url}
    ];
    try {
      await _storage.write(key: _key, value: jsonEncode(updated));
      if (!mounted) return;
      setState(() { _pins = updated; _error = null; });
      _label.clear();
      _address.clear();
      Navigator.pop(context);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Could not save shortcut in secure device storage.')));
    }
  }

  Future<void> _removePin(String url) async {
    final updated = _pins.where((v) => v['url'] != url).toList();
    try {
      await _storage.write(key: _key, value: jsonEncode(updated));
      if (mounted) setState(() { _pins = updated; _error = null; });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not remove the saved shortcut.');
    }
  }

  void _showPinDialog() {
    _label.clear();
    _address.clear();
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(20, 12, 20,
          MediaQuery.viewInsetsOf(sheet).bottom + 28),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Save a ChatGPT or AI project link',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700)),
            const SizedBox(height: 9),
            const Text('Open a conversation or project in its official app, copy its address, and paste it here. This is a private bookmark, NOT live session sync or remote control.',
              style: TextStyle(fontSize: 12, height: 1.5)),
            const SizedBox(height: 18),
            TextField(controller: _label, maxLength: 70,
              decoration: const InputDecoration(labelText: 'Project name',
                hintText: 'My ChatGPT coding project')),
            const SizedBox(height: 10),
            TextField(controller: _address, keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Official project or chat HTTPS link',
                hintText: 'https://chatgpt.com/...')),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, child: FilledButton(
              onPressed: _savePin, child: const Text('Save shortcut'))),
          ],
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Explore AI apps')),
    body: ListView(padding: const EdgeInsets.fromLTRB(20, 15, 20, 30),
      children: [
        const Text('Your AI apps, one place.',
          style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        const Text('Open official AI web apps inside a browser tab from O-AGENT. These are not O-AGENT-managed agents, synced sessions or guaranteed free API connections.',
          style: TextStyle(fontSize: 13, height: 1.5)),
        if (_error != null) Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Card(color: const Color(0xFFFFEEE9), child: Padding(
            padding: const EdgeInsets.all(13), child: Text(_error!)))),
        const SizedBox(height: 23),
        Row(children: [
          const Expanded(child: Text('My pinned project links',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
          TextButton.icon(onPressed: _showPinDialog,
            icon: const Icon(Icons.add_link), label: const Text('Add link')),
        ]),
        const SizedBox(height: 5),
        if (_pins.isEmpty) const Padding(
          padding: EdgeInsets.symmetric(vertical: 10),
          child: Text('Nothing pinned yet. Add a link to this ChatGPT project to open it quickly from O-AGENT. Links do not update or import chat messages.',
            style: TextStyle(fontSize: 12, height: 1.5))),
        for (final pin in _pins) Card(
          child: ListTile(
            title: Text(pin['label'] ?? ''),
            subtitle: Text('Manual shortcut · not synchronized\n' + (pin['url'] ?? ''),
              maxLines: 2, overflow: TextOverflow.ellipsis),
            isThreeLine: true,
            onTap: () => _launch(pin['url'] ?? ''),
            trailing: IconButton(
              tooltip: 'Remove shortcut', icon: const Icon(Icons.delete_outline),
              onPressed: () => _removePin(pin['url'] ?? '')),
          )),
        const SizedBox(height: 23),
        const Text('Official AI services',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
        const SizedBox(height: 7),
        const Text('Consumer free plans have provider-defined quotas. Some accounts and features require payment.',
          style: TextStyle(fontSize: 12)),
        const SizedBox(height: 12),
        for (final site in _sites) Card(
          child: ListTile(
            leading: const Icon(Icons.open_in_browser),
            title: Text(site.title),
            subtitle: Text(site.description,
              style: const TextStyle(fontSize: 12, height: 1.4)),
            trailing: const Icon(Icons.open_in_new, size: 20),
            onTap: () => _launch(site.url),
          )),
      ]),
  );
}

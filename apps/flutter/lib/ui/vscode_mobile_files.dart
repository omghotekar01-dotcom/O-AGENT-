import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';

/// Live file access to one trusted VS Code folder. No files are cached on disk.
class VsCodeFilesScreen extends StatefulWidget {
  const VsCodeFilesScreen({super.key, required this.controller,
    required this.workerId, required this.workspace});

  final ControlController controller;
  final String workerId;
  final String workspace;

  @override
  State<VsCodeFilesScreen> createState() => _VsCodeFilesState();
}

class _VsCodeFilesState extends State<VsCodeFilesScreen> {
  List<Map<String, dynamic>> _entries = [];
  String _folder = '';
  String? _error;
  bool _busy = false;
  bool _truncated = false;

  @override
  void initState() {
    super.initState();
    _load('');
  }

  Future<Map<String, dynamic>> _request(String operation, String path, {
    String? content, String? expectedHash, String? newPath,
  }) async {
    final api = widget.controller.client!;
    final created = await api.vscodeFileRequest(
      workerId: widget.workerId, op: operation, path: path,
      content: content, expectedHash: expectedHash, newPath: newPath,
    );
    final id = created['id']?.toString();
    if (id == null || id.isEmpty) {
      throw StateError('The backend did not issue a file request.');
    }
    for (var attempt = 0; attempt < 48; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1200));
      final response = await api.vscodeFileResult(id);
      if (response['state'] == 'failed') {
        throw StateError(response['error']?.toString() ?? 'Workspace request failed');
      }
      if (response['state'] == 'completed') {
        return Map<String, dynamic>.from(response['result'] as Map);
      }
    }
    throw StateError('VS Code has not responded. Check the connected companion and retry.');
  }

  Future<void> _load(String path) async {
    if (_busy || !mounted) return;
    setState(() { _busy = true; _error = null; });
    try {
      final result = await _request('list', path);
      if (!mounted) return;
      setState(() {
        _entries = (result['entries'] as List? ?? [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e)).toList();
        _folder = path;
        _truncated = result['truncated'] == true;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _parent() {
    final slash = _folder.lastIndexOf('/');
    _load(slash < 0 ? '' : _folder.substring(0, slash));
  }

  bool _validName(String name) =>
    name.isNotEmpty && !name.startsWith('.') &&
    RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,119}$').hasMatch(name);

  Future<bool> _confirm(String title, String message, String label) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: Text(message)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          child: Text(label)),
      ],
    )) == true;
  }

  Future<void> _create() async {
    if (_busy) return;
    String entered = '';
    final name = await showDialog<String>(context: context, builder: (ctx) =>
      AlertDialog(
        title: const Text('New text file'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_folder.isEmpty ? 'Project root' : _folder),
          const SizedBox(height: 12),
          TextField(autofocus: true, onChanged: (value) => entered = value,
            decoration: const InputDecoration(labelText: 'Filename',
              hintText: 'notes.md'),
            onSubmitted: (value) => Navigator.pop(ctx, value)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, entered),
            child: const Text('Continue')),
        ],
      ),
    );
    if (!mounted || name == null) return;
    final clean = name.trim();
    if (!_validName(clean)) {
      setState(() => _error = 'Use a filename such as notes.md, without slashes, spaces or hidden names.');
      return;
    }
    final path = [_folder, clean].where((v) => v.isNotEmpty).join('/');
    if (!await _confirm('Create this file on your laptop?',
      'Create an empty text file at $path?\n\n'
      'Requires an active 30-minute file permission in VS Code.',
      'Create file') || !mounted) return;
    setState(() => _busy = true);
    try {
      await _request('create', path, content: '');
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('File created on your laptop.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load(_folder);
  }

  Future<void> _open(Map<String, dynamic> entry) async {
    final path = entry['path']?.toString() ?? '';
    if (entry['type'] == 'directory') {
      await _load(path);
      return;
    }
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final result = await _request('read', path);
      if (!mounted) return;
      await Navigator.push<void>(context, MaterialPageRoute(
        builder: (_) => _SourceEditor(
          path: path,
          original: result['content']?.toString() ?? '',
          initialHash: result['hash']?.toString() ?? '',
          readOnly: result['readOnly'] == true,
          language: result['language']?.toString() ?? 'text',
          onSave: (content, hash) => _request('write', path,
            content: content, expectedHash: hash),
          onRename: (newPath, hash) => _request('rename', path,
            newPath: newPath, expectedHash: hash),
          onDelete: (hash) => _request('delete', path,
            expectedHash: hash),
        ),
      ));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (mounted) await _load(_folder);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Project files'), actions: [
      IconButton(tooltip: 'Create text file', onPressed: _busy ? null : _create,
        icon: const Icon(Icons.note_add_outlined)),
      IconButton(tooltip: 'Refresh', onPressed: _busy ? null : () => _load(_folder),
        icon: const Icon(Icons.refresh)),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.workspace, maxLines: 2, overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          const SizedBox(height: 5),
          const Text('Real files from your trusted VS Code folder. Hidden files, linked directories and binaries are excluded.',
            style: TextStyle(fontSize: 12)),
          const SizedBox(height: 12),
          Row(children: [
            IconButton(tooltip: 'Parent folder',
              onPressed: _busy || _folder.isEmpty ? null : _parent,
              icon: const Icon(Icons.arrow_upward)),
            Expanded(child: Text(_folder.isEmpty ? '/ (project root)' : '/$_folder',
              maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600))),
          ]),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error))),
          if (_truncated) const Text('Only the first 150 entries are shown. Open a subfolder.',
            style: TextStyle(fontSize: 11)),
        ])),
      if (_busy) const LinearProgressIndicator(),
      Expanded(child: ListView.builder(
        itemCount: _entries.length,
        itemBuilder: (ctx, index) {
          final entry = _entries[index];
          final folder = entry['type'] == 'directory';
          return ListTile(
            leading: Icon(folder ? Icons.folder_outlined : Icons.description_outlined),
            title: Text(entry['name']?.toString() ?? ''),
            subtitle: Text(folder ? 'Folder' : 'View and edit text'),
            trailing: const Icon(Icons.chevron_right),
            enabled: !_busy,
            onTap: () => _open(entry),
          );
        },
      )),
      if (_entries.isEmpty && !_busy) const Padding(
        padding: EdgeInsets.all(16),
        child: Text('No accessible files found in this folder.')),
    ]),
  );
}

class _SourceEditor extends StatefulWidget {
  const _SourceEditor({required this.path, required this.original,
    required this.initialHash, required this.language, required this.readOnly,
    required this.onSave, required this.onRename, required this.onDelete});

  final String path, original, initialHash, language;
  final bool readOnly;
  final Future<Map<String, dynamic>> Function(String, String) onSave;
  final Future<Map<String, dynamic>> Function(String, String) onRename;
  final Future<Map<String, dynamic>> Function(String) onDelete;

  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  late final TextEditingController _text;
  late String _saved, _hash;
  bool _editing = false, _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _saved = widget.original;
    _hash = widget.initialHash;
    _text = TextEditingController(text: _saved);
  }
  @override
  void dispose() { _text.dispose(); super.dispose(); }

  String _diff() {
    final before = _saved.split('\n'), after = _text.text.split('\n');
    final changed = <String>[];
    for (var i = 0; i < before.length || i < after.length; i++) {
      final previous = i < before.length ? before[i] : null;
      final next = i < after.length ? after[i] : null;
      if (previous == next) continue;
      if (previous != null) changed.add('- ${i+1}: $previous');
      if (next != null) changed.add('+ ${i+1}: $next');
      if (changed.length > 28) {
        changed.add('... Additional changes not displayed');
        break;
      }
    }
    return changed.join('\n');
  }

  Future<bool> _confirm(String title, String message, String action) async {
    return await showDialog<bool>(context: context, builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(child: SelectableText(message,
        style: const TextStyle(fontSize: 12))),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true),
          child: Text(action)),
      ],
    )) == true;
  }

  Future<void> _save() async {
    if (_saving || widget.readOnly || _text.text == _saved) return;
    final confirmed = await _confirm('Save changes on your laptop?',
      'File: ${widget.path}\n\n${_diff()}\n\n'
      'Requires your temporary VS Code editing permission. '
      'The save is rejected if the source has changed.',
      'Save on laptop');
    if (!confirmed || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = await widget.onSave(_text.text, _hash);
      if (!mounted) return;
      if (result['saved'] != true) throw StateError('VS Code did not confirm save');
      setState(() {
        _saved = _text.text;
        _hash = result['hash']?.toString() ?? _hash;
        _editing = false;
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved in your actual VS Code project.')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _fileAction(String action) async {
    if (_saving || widget.readOnly) return;
    if (_text.text != _saved) {
      setState(() => _error = 'Save or discard phone edits before renaming or deleting.');
      return;
    }
    final filename = widget.path.split('/').last;
    String? renamed;
    if (action == 'rename') {
      String input = filename;
      renamed = await showDialog<String>(context: context, builder: (ctx) =>
        AlertDialog(
          title: const Text('Rename file'),
          content: TextField(autofocus: true, onChanged: (value) => input = value,
            decoration: InputDecoration(labelText: 'New filename', hintText: filename),
            onSubmitted: (value) => Navigator.pop(ctx, value)),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, input),
              child: const Text('Continue')),
          ],
        ),
      );
      if (!mounted || renamed == null) return;
      renamed = renamed.trim();
      if (renamed == filename ||
          renamed.startsWith('.') ||
          !RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]{0,119}$').hasMatch(renamed)) {
        setState(() => _error = 'Choose a different allowed filename without spaces or slashes.');
        return;
      }
    }
    final folder = widget.path.contains('/')
      ? widget.path.substring(0, widget.path.lastIndexOf('/') + 1) : '';
    final nextPath = renamed == null ? null : '$folder$renamed';
    final approved = await _confirm(
      action == 'rename' ? 'Rename this laptop file?' : 'Move file to Trash?',
      action == 'rename'
        ? 'Current: ${widget.path}\nNew: $nextPath\n\nA version check prevents overwriting changed files.'
        : 'File: ${widget.path}\n\nThe local VS Code user must confirm the Trash operation too. '
          'This action may not be undoable.',
      action == 'rename' ? 'Rename on laptop' : 'Move to Trash');
    if (!approved || !mounted) return;
    setState(() => _saving = true);
    try {
      final result = action == 'rename'
        ? await widget.onRename(nextPath!, _hash)
        : await widget.onDelete(_hash);
      final success = action == 'rename' ? result['renamed'] == true : result['deleted'] == true;
      if (!success) throw StateError('VS Code did not confirm the file operation.');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.path.split('/').last), actions: [
      PopupMenuButton<String>(tooltip: 'File actions',
        enabled: !widget.readOnly && !_saving,
        onSelected: _fileAction,
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'rename', child: Text('Rename file')),
          PopupMenuItem(value: 'delete', child: Text('Move to Trash')),
        ]),
      IconButton(tooltip: 'Toggle editing',
        onPressed: widget.readOnly ? null : () => setState(() => _editing = !_editing),
        icon: Icon(_editing ? Icons.visibility : Icons.edit_outlined)),
    ]),
    body: Column(children: [
      Padding(padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.path, style: const TextStyle(fontSize: 12,
            fontWeight: FontWeight.w600)),
          const SizedBox(height: 5),
          Text(widget.readOnly
            ? 'Read-only: save your pending local VS Code changes first.'
            : 'Language: ${widget.language} · Requires 30-minute local edit permission.',
            style: const TextStyle(fontSize: 12)),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 8),
            child: Text(_error!, style: TextStyle(
              color: Theme.of(context).colorScheme.error))),
          if (_saving) const LinearProgressIndicator(),
        ])),
      Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12),
        child: TextField(controller: _text,
          readOnly: !_editing || widget.readOnly,
          expands: true, minLines: null, maxLines: null, maxLength: 48000,
          style: const TextStyle(fontFamily: 'monospace', fontSize: 13, height: 1.5),
          textAlignVertical: TextAlignVertical.top,
          decoration: const InputDecoration(border: OutlineInputBorder(),
            hintText: 'Source text')))),
      SafeArea(top: false, child: Padding(padding: const EdgeInsets.all(12),
        child: Row(children: [
          Expanded(child: OutlinedButton(
            onPressed: widget.readOnly || _saving ? null :
              () => setState(() => _editing = !_editing),
            child: Text(_editing ? 'View mode' : 'Edit text'))),
          const SizedBox(width: 12),
          Expanded(child: FilledButton.icon(
            onPressed: widget.readOnly || _saving || !_editing ? null : _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Review & save'))),
        ]))),
    ]),
  );
}

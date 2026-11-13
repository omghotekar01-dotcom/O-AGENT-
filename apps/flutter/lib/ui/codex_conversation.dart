import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../theme.dart';

/// A real, opt-in Codex saved-history preview. Reads ONLY authenticated
/// app-server user/assistant message items. This is not a browser/IDE mirror.
class CodexConversationPanel extends StatefulWidget {
  const CodexConversationPanel({
    super.key, required this.controller, required this.projectId,
    required this.sessionId,
  });
  final ControlController controller;
  final String projectId, sessionId;
  @override State<CodexConversationPanel> createState() =>
    _CodexConversationPanelState();
}

class _CodexConversationPanelState extends State<CodexConversationPanel> {
  Timer? poller;
  String? historyTaskId, failure;
  Map<String,dynamic>? history;
  bool loading = false, sending = false;

  @override void initState() {
    super.initState();
    for (final t in widget.controller.snapshot?.tasks ?? []) {
      if (t.kind == 'codex_cli_history' &&
          t.parameters?['sessionId'] == widget.sessionId) {
        historyTaskId = t.id;
        break;
      }
    }
    _refresh();
    poller = Timer.periodic(const Duration(seconds: 3), (_) => _refresh());
  }
  @override void dispose() { poller?.cancel(); super.dispose(); }

  Future<void> _refresh() async {
    if (!mounted || loading || historyTaskId == null) return;
    final api = widget.controller.client;
    if (api == null) return;
    loading = true;
    try {
      final latest = await api.taskDetail(historyTaskId!);
      if (mounted && widget.controller.client == api) {
        setState(() { history = latest; failure = null; });
      }
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    } finally { loading = false; }
  }

  Future<void> _load() async {
    if (sending) return;
    final api = widget.controller.client;
    if (api == null) {
      setState(() => failure = 'Connect to your laptop workspace first.');
      return;
    }
    setState(() { sending = true; failure = null; });
    try {
      final task = await api.loadCodexConversation(
        projectId: widget.projectId, sessionId: widget.sessionId);
      if (!mounted || widget.controller.client != api) return;
      setState(() { historyTaskId = task['id']?.toString(); history = task; });
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => failure = e.toString());
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  List<Map<String,dynamic>> get messages {
    final result = history?['result'];
    if (result is! Map || result['messages'] is! List) return [];
    return (result['messages'] as List).whereType<Map>().map(
      (x) => Map<String,dynamic>.from(x)).where((item) =>
      (item['role'] == 'user' || item['role'] == 'assistant') &&
      item['text'] is String).toList(growable:false);
  }

  @override Widget build(BuildContext context) {
    final state = history?['status']?.toString();
    final error = history?['error']?.toString();
    final result = history?['result'];
    final items = messages;
    final fetching = sending || const {'queued','running'}.contains(state);
    final message = error?.isNotEmpty == true ? error : failure;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        const Expanded(child: Text('Your saved conversation',
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800,
            color: OTheme.ink))),
        TextButton.icon(onPressed: fetching ? null : _load,
          icon: const Icon(Icons.sync_rounded, size: 17),
          label: Text(historyTaskId == null ? 'Load chat' : 'Refresh chat')),
      ]),
      const SizedBox(height: 6),
      const Text('Real messages saved by Codex on your laptop. You can read '
        'them even if another Codex window is still using this conversation.',
        style: TextStyle(color: Color(0xFF656575),fontSize:12,height:1.5)),
      const SizedBox(height: 12),
      if (historyTaskId == null && !fetching) Container(
        width:double.infinity, padding:const EdgeInsets.all(19),
        decoration: BoxDecoration(color:Colors.white,
          borderRadius:BorderRadius.circular(21),
          border:Border.all(color:OTheme.hairline)),
        child: Column(crossAxisAlignment:CrossAxisAlignment.start,children: [
          const Text('Read your actual previous messages',
            style:TextStyle(fontWeight:FontWeight.w800,fontSize:14)),
          const SizedBox(height:7),
          const Text('No extra API key or paid model is needed. '
            'Only the user and assistant text is loaded—not raw tools, '
            'private reasoning or an active ChatGPT website window.',
            style:TextStyle(color:Color(0xFF656575),fontSize:12,height:1.5)),
          const SizedBox(height:12),
          FilledButton.icon(onPressed:_load,
            icon:const Icon(Icons.forum_outlined,size:17),
            label:const Text('Load saved messages')),
        ]),
      ),
      if (fetching) Padding(padding:const EdgeInsets.symmetric(vertical:12),
        child:Row(children:[
          const SizedBox(height:18,width:18,
            child:CircularProgressIndicator(strokeWidth:2)),
          const SizedBox(width:11),
          Expanded(child:Text('Reading saved messages from your laptop…',
            style:TextStyle(color:Colors.grey.shade700,fontSize:12))),
        ])),
      if (message != null && message.isNotEmpty) Padding(
        padding:const EdgeInsets.only(top:10),
        child:Container(width:double.infinity,
          padding:const EdgeInsets.all(15),
          decoration:BoxDecoration(color:const Color(0xFFFFEFEA),
            borderRadius:BorderRadius.circular(16)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            const Text('Could not load this conversation',
              style:TextStyle(fontWeight:FontWeight.w800,
                color:Color(0xFF9F463A))),
            const SizedBox(height:6),
            Text(message.replaceFirst(RegExp(r'^CODEX_[A-Z_]+:\s*'), ''),
              style:const TextStyle(color:Color(0xFF884639),
                fontSize:12,height:1.5)),
            const SizedBox(height:8),
            TextButton(onPressed:fetching?null:_load,
              child:const Text('Try again')),
          ]))),
      if (state=='completed' && items.isEmpty) const Padding(
        padding:EdgeInsets.symmetric(vertical:14),
        child:Text('Codex returned no stored user/assistant text for this '
          'conversation. You may be viewing a project record without '
          'saved turns, or this CLI version cannot reconstruct them.',
          style:TextStyle(color:Color(0xFF656575),fontSize:12,height:1.5))),
      for (final item in items) Padding(
        padding:const EdgeInsets.only(bottom:11),
        child:Align(
          alignment:item['role']=='user'?Alignment.centerRight:
            Alignment.centerLeft,
          child:ConstrainedBox(
            constraints:const BoxConstraints(maxWidth:550),
            child:Container(
              padding:const EdgeInsets.symmetric(horizontal:15,vertical:13),
              decoration:BoxDecoration(
                color:item['role']=='user'?OTheme.lavender:Colors.white,
                border:Border.all(color:OTheme.hairline),
                borderRadius:BorderRadius.circular(17)),
              child:Column(crossAxisAlignment:CrossAxisAlignment.start,
                children:[
                  Text(item['role']=='user'?'YOU':'CODEX',
                    style:const TextStyle(color:OTheme.violet,
                      fontWeight:FontWeight.w800,fontSize:10,
                      letterSpacing:0.9)),
                  const SizedBox(height:7),
                  SelectableText(item['text'] as String,
                    style:const TextStyle(color:OTheme.ink,
                      fontSize:13,height:1.5)),
                ]),
            ),
          ),
        ),
      ),
      if (result is Map && result['truncated']==true)
        const Padding(padding:EdgeInsets.only(bottom:12),
          child:Text('Showing only the newest saved messages. '
            'Older content was shortened to protect phone performance.',
            style:TextStyle(fontSize:12,color:Color(0xFF656575)))),
      if (historyTaskId!=null) const Text(
        'History is a saved snapshot, not a live mirror. '
        'Preview text is retained in your private O-AGENT backend task history; '
        'do not use an untrusted host.',
        style:TextStyle(fontSize:11,height:1.5,color:Color(0xFF777786))),
    ]);
  }
}

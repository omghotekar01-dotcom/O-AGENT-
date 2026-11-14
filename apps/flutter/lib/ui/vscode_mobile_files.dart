import 'dart:async';
import 'package:flutter/material.dart';
import '../core/controller.dart';

/// Text-only browsing of the explicitly enrolled, trusted VS Code workspace.
/// Every request goes to a real editor companion; there is no synthetic tree.
class VsCodeFilesScreen extends StatefulWidget {
  const VsCodeFilesScreen({super.key,required this.controller,
    required this.workerId,required this.workspace});
  final ControlController controller;
  final String workerId;
  final String workspace;

  @override
  State<VsCodeFilesScreen> createState() => _VsCodeFilesState();
}

class _VsCodeFilesState extends State<VsCodeFilesScreen> {
  List<Map<String,dynamic>> _entries = [];
  String _folder = '';
  String? _error;
  bool _busy = false;
  bool _truncated = false;

  @override
  void initState() { super.initState(); _load(''); }

  Future<Map<String,dynamic>> _perform(String op, String path, {
    String? content,String? expectedHash,
  }) async {
    final api = widget.controller.client!;
    final job = await api.vscodeFileRequest(workerId:widget.workerId,
      op:op,path:path,content:content,expectedHash:expectedHash);
    final id = job['id']?.toString();
    if(id==null || id.isEmpty) throw StateError('No file request identifier returned');
    for(var i=0;i<46;i++){
      await Future<void>.delayed(const Duration(milliseconds:1200));
      final result = await api.vscodeFileResult(id);
      switch(result['state']) {
        case 'completed':
          return Map<String,dynamic>.from(result['result'] as Map);
        case 'failed':
          throw StateError(result['error']?.toString() ?? 'VS Code operation failed');
      }
    }
    throw StateError('VS Code did not respond. Check the companion status and retry.');
  }

  Future<void> _load(String folder) async {
    if(_busy) return;
    setState(() { _busy=true;_error=null; });
    try {
      final response = await _perform('list',folder);
      if(!mounted) return;
      final items = (response['entries'] as List? ?? [])
        .whereType<Map>()
        .map((x)=>Map<String,dynamic>.from(x)).toList();
      setState(() {
        _entries=items;
        _folder=folder;
        _truncated=response['truncated']==true;
      });
    } catch(error) {
      if(mounted)setState(()=>_error=error.toString());
    } finally {
      if(mounted)setState(()=>_busy=false);
    }
  }

  void _parent() {
    final idx=_folder.lastIndexOf('/');
    _load(idx<0?'':_folder.substring(0,idx));
  }

  Future<void> _open(Map<String,dynamic> entry) async {
    final path=entry['path']?.toString()??'';
    if(entry['type']=='directory') { await _load(path);return; }
    if(_busy)return;
    setState(()=>_busy=true);
    try {
      final file=await _perform('read',path);
      if(!mounted)return;
      await Navigator.push<void>(context,MaterialPageRoute(
        builder:(_) => _MobileSourceEditor(
          path:path,original:file['content']?.toString()??'',
          initialHash:file['hash']?.toString()??'',
          readOnly:file['readOnly']==true,
          language:file['language']?.toString()??'text',
          onSave:(content,hash)=>_perform('write',path,
            content:content,expectedHash:hash),
        ),
      ));
      if(mounted) _load(_folder);
    } catch(error) {
      if(mounted)setState(()=>_error=error.toString());
    } finally {
      if(mounted)setState(()=>_busy=false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar:AppBar(title:const Text('Project files'),actions:[
      IconButton(tooltip:'Refresh folder',onPressed:_busy?null:()=>_load(_folder),
        icon:const Icon(Icons.refresh)),
    ]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.fromLTRB(16,8,16,8),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.workspace,style:const TextStyle(fontSize:12,
            fontWeight:FontWeight.w600)),
          const SizedBox(height:6),
          const Text('Real folders from your enrolled VS Code workspace. '
            'Protected files, linked folders and binary files are not accessible.',
            style:TextStyle(fontSize:12)),
          const SizedBox(height:10),
          Row(children:[
            IconButton(tooltip:'Parent folder',
              onPressed:_busy||_folder.isEmpty?null:_parent,
              icon:const Icon(Icons.arrow_upward)),
            Expanded(child:Text(_folder.isEmpty?'/ (workspace root)':'/$_folder',
              maxLines:2,overflow:TextOverflow.ellipsis,
              style:const TextStyle(fontWeight:FontWeight.w600))),
          ]),
          if(_error!=null)Padding(padding:const EdgeInsets.only(top:9),
            child:Text(_error!,style:TextStyle(color:Theme.of(context).colorScheme.error))),
          if(_truncated)const Text('Showing first 150 entries. Open a subfolder to continue.',
            style:TextStyle(fontSize:11)),
        ])),
      if(_busy) const LinearProgressIndicator(),
      Expanded(child:ListView.builder(
        itemCount:_entries.length,
        itemBuilder:(ctx,i){
          final item=_entries[i];
          final folder=item['type']=='directory';
          return ListTile(
            leading:Icon(folder?Icons.folder_outlined:Icons.description_outlined),
            title:Text(item['name']?.toString()??''),
            subtitle:Text(folder?'Folder':'Open text preview / editor'),
            trailing:const Icon(Icons.chevron_right),
            enabled:!_busy,onTap:()=>_open(item),
          );
        })),
      if(_entries.isEmpty&&!_busy)
        const Padding(padding:EdgeInsets.all(16),
          child:Text('No accessible files found in this folder.')),
    ]),
  );
}

class _MobileSourceEditor extends StatefulWidget {
  const _MobileSourceEditor({required this.path,required this.original,
    required this.initialHash,required this.readOnly,required this.language,
    required this.onSave});
  final String path,original,initialHash,language;
  final bool readOnly;
  final Future<Map<String,dynamic>> Function(String,String) onSave;
  @override State<_MobileSourceEditor> createState()=>_MobileSourceEditorState();
}
class _MobileSourceEditorState extends State<_MobileSourceEditor> {
  late final TextEditingController _text;
  late String _saved,_hash;
  bool _editing=false,_saving=false;
  String? _error;

  @override
  void initState(){
    super.initState();
    _saved=widget.original;
    _hash=widget.initialHash;
    _text=TextEditingController(text:_saved);
  }
  @override void dispose(){_text.dispose();super.dispose();}
  String _preview(){
    final before=_saved.split('\n'),after=_text.text.split('\n');
    final lines=<String>[];
    for(var i=0;i<before.length||i<after.length;i++){
      final a=i<before.length?before[i]:null;
      final b=i<after.length?after[i]:null;
      if(a==b)continue;
      if(a!=null)lines.add('- ${i+1}: $a');
      if(b!=null)lines.add('+ ${i+1}: $b');
      if(lines.length>28){lines.add('... More changes not displayed');break;}
    }
    return lines.join('\n');
  }
  Future<void> _save() async{
    if(_saving||_text.text==_saved)return;
    final changes=_preview();
    final ok=await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('Save changes to laptop?'),
      content:SingleChildScrollView(child:Column(
        mainAxisSize:MainAxisSize.min,crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          Text('Workspace file: ${widget.path}'),
          const SizedBox(height:10),
          const Text('This updates the real VS Code file. The local VS Code '
            'user must have enabled 30-minute mobile editing. '
            'The save fails if the file has changed since you opened it.',
            style:TextStyle(fontSize:12)),
          const SizedBox(height:12),
          SelectableText(changes,
            style:const TextStyle(fontFamily:'monospace',fontSize:11)),
        ])),
      actions:[
        TextButton(onPressed:()=>Navigator.pop(ctx,false),
          child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(ctx,true),
          child:const Text('Save to laptop')),
      ]));
    if(ok!=true||!mounted)return;
    setState(()=>_saving=true);
    try {
      final response=await widget.onSave(_text.text,_hash);
      if(!mounted)return;
      setState(() {
        _saved=_text.text;
        _hash=response['hash']?.toString()??_hash;
        _editing=false;_error=null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content:Text('Saved in the real VS Code workspace.')));
    } catch(error) {
      if(mounted)setState(()=>_error=error.toString());
    } finally {
      if(mounted)setState(()=>_saving=false);
    }
  }

  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.path.split('/').last),
      actions:[
        IconButton(tooltip:'Read or edit',onPressed:widget.readOnly?null:()=>
          setState(()=>_editing=!_editing),
          icon:Icon(_editing?Icons.visibility:Icons.edit_outlined)),
      ]),
    body:Column(children:[
      Padding(padding:const EdgeInsets.all(12),
        child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(widget.path,style:const TextStyle(fontSize:12,
            fontWeight:FontWeight.w600)),
          const SizedBox(height:4),
          Text(widget.readOnly?
            'Read only: the local editor has unsaved changes. Save locally first.'
            :'Language: ${widget.language} · Editing requires local permission.',
            style:const TextStyle(fontSize:12)),
          if(_error!=null)Padding(padding:const EdgeInsets.only(top:8),
            child:Text(_error!,style:TextStyle(
              color:Theme.of(context).colorScheme.error))),
          if(_saving)const LinearProgressIndicator(),
        ])),
      Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:12),
        child:TextField(controller:_text,readOnly:!_editing||widget.readOnly,
          expands:true,minLines:null,maxLines:null,maxLength:48000,
          style:const TextStyle(fontFamily:'monospace',fontSize:13,height:1.5),
          textAlignVertical:TextAlignVertical.top,
          decoration:const InputDecoration(border:OutlineInputBorder(),
            hintText:'Source text')))),
      SafeArea(top:false,child:Padding(padding:const EdgeInsets.all(12),
        child:Row(children:[
          Expanded(child:OutlinedButton(
            onPressed:widget.readOnly||_saving?null:()=>
              setState(()=>_editing=!_editing),
            child:Text(_editing?'View mode':'Edit text'))),
          const SizedBox(width:12),
          Expanded(child:FilledButton.icon(
            onPressed:widget.readOnly||_saving||!_editing?null:_save,
            icon:const Icon(Icons.save_outlined),
            label:const Text('Review & save')),
        ]))),
    ]),
  );
}

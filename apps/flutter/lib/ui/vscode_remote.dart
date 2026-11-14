import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import 'ios_components.dart';
import 'vscode_mobile_files.dart';

Map<String,dynamic> vsMap(Object? value) =>
  value is Map ? Map<String,dynamic>.from(value) : <String,dynamic>{};
List<Map<String,dynamic>> vsList(Object? value) =>
  value is List ? value.whereType<Map>().map(vsMap).toList() : [];
String vsText(Object? v) => v?.toString() ?? '';

/// Owner may request an approved file open, but VS Code requires a second
/// explicit local modal. It never edits files or reads arbitrary IDE chats.
class VsCodeRemoteScreen extends StatefulWidget {
  const VsCodeRemoteScreen({super.key,required this.controller,this.taskId});
  final ControlController controller;
  final String? taskId;
  @override State<VsCodeRemoteScreen> createState()=>_VsCodeRemoteState();
}
class _VsCodeRemoteState extends State<VsCodeRemoteScreen> {
  final path = TextEditingController();
  Timer? timer;
  List<Map<String,dynamic>> machines = [];
  List<Map<String,dynamic>> workspaces = [];
  Map<String,dynamic>? task;
  String? workerId,taskId,error;
  bool busy=false;
  @override void initState(){
    super.initState();taskId=widget.taskId;_load();
    timer=Timer.periodic(const Duration(seconds:5),(_)=>_load());
  }
  @override void dispose(){timer?.cancel();path.dispose();super.dispose();}
  Future<void> _load() async{
    if(busy||!mounted) return;
    try{
      final api=widget.controller.client!;
      final remote=await api.remoteAgentOverview();
      final workspaceFeed=await api.vscodeWorkspaces();
      final details=taskId==null?null:await api.taskDetail(taskId!);
      if(!mounted||api!=widget.controller.client)return;
      setState((){
        workspaces=vsList(workspaceFeed['items']);
        machines=vsList(remote['machines']).where((m)=>
          m['status']=='online' && m['capabilities'] is List &&
          (m['capabilities'] as List).contains('vscode_open_file')).toList();
        if(!machines.any((m)=>m['id']==workerId)){
          workerId=machines.isNotEmpty?vsText(machines.first['id']):null;
        }
        if(details!=null)task=details;
        error=null;
      });
    }catch(e){if(mounted)setState(()=>error=e.toString());}
  }
  Future<bool> _confirm(String title,String description,String action) async =>
    await showDialog<bool>(context:context,builder:(ctx)=>AlertDialog(
      title:Text(title),content:SingleChildScrollView(
        child:SelectableText(description)),actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('Back')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:Text(action)),
        ]))==true;
  Future<void> _request() async{
    final name=path.text.trim();
    if(workerId==null||name.isEmpty||busy)return;
    if(name.startsWith('/') || name.contains('..') ||
        RegExp(r'^[A-Za-z]:').hasMatch(name)){
      setState(()=>error='Enter a relative path inside the VS Code workspace.');
      return;
    }
    if(!await _confirm('Ask VS Code to open a file?',
      'Machine: '+workerId!+'\nRelative file: '+name+
      '\n\nOwner approval will be required before delivery, and the '
      'person at VS Code must also accept a local dialog. No file contents '
      'are sent to the phone.', 'Create request')||!mounted)return;
    setState(()=>busy=true);
    try{
      final result=await widget.controller.client!.requestVscodeOpen(
        workerId:workerId!,relativePath:name);
      if(mounted)setState((){
        task=result;taskId=vsText(result['id']);
      });
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
  }
  Future<void> _decide(bool approve) async{
    if(taskId==null||busy)return;
    final p=vsMap(task?['parameters']);
    if(!await _confirm('Approve exact VS Code request?',
      'Target: '+vsText(p['relativePath'])+
      '\n\nThe VS Code user must separately confirm this action.',
      approve?'Approve once':'Reject')||!mounted)return;
    setState(()=>busy=true);
    try{await widget.controller.client!.decide(taskId!,approve:approve);}
    catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>busy=false);}
    await _load();
  }
  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:OVisual.canvas(context),
    appBar:AppBar(title:const Text('VS Code companion'),actions:[
      IconButton(onPressed:_load,icon:const Icon(CupertinoIcons.refresh)),
    ]),
    body:SafeArea(child:Center(child:ConstrainedBox(
      constraints:const BoxConstraints(maxWidth:720),
      child:ListView(padding:const EdgeInsets.fromLTRB(19,14,19,34),
        children:[
          const OScreenTitle(eyebrow:'Connected workspace',
            title:'VS Code projects',
            subtitle:'Browse project files, review changes, and make '
              'approved edits in the exact folder you enrolled.'),
          if(error!=null)Padding(padding:const EdgeInsets.only(top:12),
            child:OSurface(child:Text(error!,
              style:const TextStyle(color:OVisual.rose)))),
          const OSectionTitle('Project browser'),
          const OSurface(child:Text(
            'Choose a connected folder. View allowed source files, '
            'create or rename files, edit text and request a move to Trash. '
            'Changes require time-limited permission in VS Code.',
            style:TextStyle(fontSize:12))),
          for(final workspace in workspaces) Padding(
            padding:const EdgeInsets.only(bottom:10),
            child:FilledButton.icon(
              onPressed:()=>Navigator.push(context,MaterialPageRoute<void>(
                builder:(_)=>VsCodeFilesScreen(
                  controller:widget.controller,
                  workerId:vsText(workspace['workerId']),
                  workspace:vsText(workspace['workspace']),
                ))),
              icon:const Icon(Icons.folder_open),
              label:Text('Open files in ${vsText(workspace['workspace']).split(RegExp(r'[\\/]')).last}'),
            )),
          const OSectionTitle('Recent file changes'),
          if(workspaces.isEmpty) const OSurface(child:Text(
            'No opted-in VS Code file feed is online yet. Install and start '
            'the O-AGENT VS Code companion in a trusted project to see Git '
            'changes and unsaved file names. No file contents are uploaded.')),
          for(final workspace in workspaces) Padding(
            padding:const EdgeInsets.only(bottom:10),
            child:OSurface(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
              Text(vsText(workspace['workspace']),
                style:const TextStyle(fontSize:13,fontWeight:FontWeight.w700)),
              const SizedBox(height:5),
              Text('Live filenames · '+
                vsText(workspace['trackedAt']),
                style:const TextStyle(fontSize:11)),
              const SizedBox(height:10),
              if(vsList(workspace['changed']).isEmpty)
                const Text('No Git or unsaved changes detected.',
                  style:TextStyle(fontSize:12)),
              for(final file in vsList(workspace['changed']).take(50))
                Padding(padding:const EdgeInsets.only(bottom:7),
                  child:Row(children:[
                    const Icon(Icons.description_outlined,size:17),
                    const SizedBox(width:8),
                    Expanded(child:Text(vsText(file['path']),
                      style:const TextStyle(fontSize:12))),
                    const SizedBox(width:8),
                    Text(vsText(file['status']),
                      style:const TextStyle(fontSize:11)),
                  ])),
              if(vsList(workspace['changed']).length>50)
                const Text('Showing 50 changed paths. Open VS Code for more.',
                  style:TextStyle(fontSize:11)),
            ]))),
          ExpansionTile(
            title:const Text('Advanced: open file in laptop editor',
              style:TextStyle(fontWeight:FontWeight.w700)),
            subtitle:const Text('Only needed when you already know its relative path',
              style:TextStyle(fontSize:12)),
            children:[
          if(taskId==null)OSurface(child:Column(
            crossAxisAlignment:CrossAxisAlignment.start,children:[
              if(machines.isEmpty)const Text('No active VS Code companion. '
                'Install the O-AGENT extension and choose Start.'),
              if(machines.isNotEmpty)DropdownButtonFormField<String>(
                initialValue:machines.any((m)=>m['id']==workerId)?workerId:null,
                decoration:const InputDecoration(labelText:'Online VS Code worker'),
                items:machines.map((m)=>DropdownMenuItem(
                  value:vsText(m['id']),
                  child:Text(vsText(m['name'])))).toList(),
                onChanged:(v)=>setState(()=>workerId=v)),
              const SizedBox(height:11),
              TextField(controller:path,decoration:const InputDecoration(
                labelText:'File path relative to workspace',
                hintText:'lib/main.dart')),
              const SizedBox(height:13),
              SizedBox(width:double.infinity,child:FilledButton.icon(
                onPressed:busy||workerId==null?null:_request,
                icon:const Icon(CupertinoIcons.folder_open),
                label:const Text('Review file open request'))),
            ]))else OSurface(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                Row(children:[
                  const Expanded(child:Text('Actual task state',
                    style:TextStyle(fontWeight:FontWeight.w700))),
                  OStatePill(vsText(task?['status'])),
                ]),
                const SizedBox(height:10),
                TextButton.icon(
                  onPressed:()=>setState(() {task=null;taskId=null;error=null;}),
                  icon:const Icon(Icons.add),
                  label:const Text('New file-open request')),
                const SizedBox(height:8),
                SelectableText(vsText(vsMap(task?['parameters'])['relativePath'])),
                const SizedBox(height:10),
                if(task?['status']=='waiting_for_approval')
                  Row(children:[
                    Expanded(child:OutlinedButton(onPressed:busy?null:()=>_decide(false),
                      child:const Text('Reject'))),
                    const SizedBox(width:9),
                    Expanded(child:FilledButton(onPressed:busy?null:()=>_decide(true),
                      child:const Text('Approve'))),
                  ]),
                if(task?['result']!=null)SelectableText(
                  vsMap(task?['result']).toString()),
                if(task?['error']!=null)Text(vsText(task?['error']),
                  style:const TextStyle(color:OVisual.rose)),
              ])),
            ],
          ),
          ExpansionTile(
            title:const Text('First time connecting VS Code?',
              style:TextStyle(fontWeight:FontWeight.w700)),
            subtitle:const Text('Four steps to connect a trusted project',
              style:TextStyle(fontSize:12)),
            children:[const Padding(
              padding:EdgeInsets.all(15),
              child:Text('1. Start O-AGENT on your laptop.\n'
                '2. Open the exact project folder in VS Code.\n'
                '3. Install the O-AGENT Workspace Companion VSIX and '
                'configure the local backend once.\n'
                '4. Run O-AGENT: Start Remote Workspace Companion from '
                'Ctrl+Shift+P and select Enable.\n\n'
                'For edits, enable O-AGENT: Enable Mobile File Editing '
                '(30 minutes) in the VS Code Command Palette.',
                style:TextStyle(fontSize:13,height:1.6))),
            ]),
          const OSectionTitle('Safety boundary'),
          const OIconTile(icon:CupertinoIcons.shield_lefthalf_fill,
            title:'Workspace access you control',
            subtitle:'Each change needs phone confirmation and a separate '
              '30-minute permission in VS Code. Renames reject overwrites; '
              'deleting requests the laptop Trash and local confirmation. '
              'Copilot Chat is not exposed by this extension.'),
        ],
      ),
    ))),
  );
}

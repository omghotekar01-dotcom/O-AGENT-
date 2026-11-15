import 'package:flutter/material.dart';

import '../core/pilot_native.dart';
import 'native_pilot.dart' show NativeRunDetail;

/// A real SDK-owned session backed by completed, tenant-scoped O-AGENT runs.
/// No arbitrary Claude/Copilot website messages are ever invented here.
class NativeProviderSessionDetail extends StatefulWidget {
  const NativeProviderSessionDetail({
    super.key,
    required this.pilot,
    required this.session,
    required this.canContinue,
    required this.onRequested,
  });
  final NativePilotController pilot;
  final Map<String,dynamic> session;
  final bool canContinue;
  final VoidCallback onRequested;
  @override
  State<NativeProviderSessionDetail> createState() =>
      _NativeProviderSessionDetailState();
}

class _NativeProviderSessionDetailState extends State<NativeProviderSessionDetail> {
  final prompt=TextEditingController();
  List<Map<String,dynamic>> history=[];
  String permissionMode='read_only';
  String? error;
  bool loading=false,submitting=false;
  @override
  void initState(){
    super.initState();
    Future.microtask(_refresh);
  }
  @override
  void dispose(){
    prompt.dispose();
    super.dispose();
  }
  String get kind=>widget.session['kind']?.toString()??'';
  String get provider=>pilotCapabilityLabel(kind);
  String get deviceId=>widget.session['deviceId']?.toString()??'';
  String get sessionId=>widget.session['sessionId']?.toString()??'';
  String _display(dynamic v,[String empty='Not reported'])=>
      v == null || v.toString().isEmpty ? empty : v.toString();
  Widget _panel(Widget content)=>Card(
    elevation:0,
    margin:const EdgeInsets.only(bottom:12),
    shape:RoundedRectangleBorder(
      side:const BorderSide(color:Color(0xFFDCE5E8)),
      borderRadius:BorderRadius.circular(16)),
    child:Padding(padding:const EdgeInsets.all(16),child:content));
  Future<void> _refresh() async{
    if(loading)return;
    if(mounted)setState(()=>loading=true);
    try{
      final events=await widget.pilot.providerHistory(
        kind:kind,deviceId:deviceId,sessionId:sessionId);
      if(mounted)setState((){
        history=events;
        error=null;
      });
    }catch(e){
      if(mounted)setState(()=>error=pilotFriendlyError(e));
    }finally{
      if(mounted)setState(()=>loading=false);
    }
  }
  Future<void> _send() async{
    if(submitting||!widget.canContinue)return;
    final message=prompt.text.trim();
    if(message.isEmpty){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('Write your next prompt first.')));
      return;
    }
    // Sending a read-only message is the owner's explicit authorization.
    // Write requests and tool actions retain separate server approvals.
    final device=widget.pilot.devices
      .where((d)=>d['id']==deviceId).firstOrNull;
    if(device==null||!pilotDeviceOnline(device)){
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content:Text('This laptop is offline. No instructions were submitted.')));
      return;
    }
    setState(()=>submitting=true);
    try{
      final created=await widget.pilot.requestTurn(
        device:device,kind:kind,sessionId:sessionId,
        mode:permissionMode,prompt:message);
      if(!mounted)return;
      prompt.clear();
      final id=created['runId']?.toString()??'';
      if(RegExp(r'^[0-9a-f-]{36}'+r'$').hasMatch(id)){
        await Navigator.push(context,MaterialPageRoute<void>(
          builder:(_)=>NativeRunDetail(c:widget.pilot,id:id)));
      }else{
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content:Text('Request saved. Open Sessions to inspect activity.')));
      }
    }catch(e){
      if(mounted)ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content:Text(pilotFriendlyError(e))));
    }finally{
      if(mounted)setState(()=>submitting=false);
    }
  }
  @override Widget build(BuildContext context){
    final isConnected=widget.pilot.connected;
    return Scaffold(
      appBar:AppBar(
        title:Text(provider),
        actions:[IconButton(
          tooltip:'Refresh real SDK run history',
          onPressed:loading?null:_refresh,
          icon:const Icon(Icons.refresh))],
      ),
      body:SafeArea(child:RefreshIndicator(
        onRefresh:_refresh,
        child:ListView(padding:const EdgeInsets.all(18),children:[
          Text(_display(widget.session['lastPrompt'],'Saved SDK conversation'),
            style:const TextStyle(fontSize:23,fontWeight:FontWeight.w800)),
          const SizedBox(height:7),
          const Text('A genuine SDK session from this enrolled worker. '
            'This is not an external Claude/Copilot website takeover.',
            style:TextStyle(color:Color(0xFF607078),height:1.4)),
          const SizedBox(height:16),
          _panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text('Worker: '+_display(widget.session['deviceName']),
              style:const TextStyle(fontWeight:FontWeight.w700)),
            const SizedBox(height:5),
            SelectableText('Project: '+_display(widget.session['cwd']),
              style:const TextStyle(fontSize:12)),
            const SizedBox(height:5),
            Text('Most recent run: '+_display(widget.session['updatedAt']),
              style:const TextStyle(fontSize:12,color:Color(0xFF607078))),
          ])),
          const Text('REAL CONVERSATION HISTORY',
            style:TextStyle(fontWeight:FontWeight.w800,fontSize:12)),
          const SizedBox(height:12),
          if(loading&&history.isEmpty)const Center(
            child:Padding(padding:EdgeInsets.all(24),
              child:CircularProgressIndicator())),
          if(error!=null)Text(error!,
            style:const TextStyle(color:Colors.red)),
          if(!loading&&history.isEmpty)
            _panel(const Text('No completed turns were available for this '
              'session. Results only appear after the worker confirms them.')),
          for(final turn in history)...[
            _panel(Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              const Text('YOU',style:TextStyle(
                fontWeight:FontWeight.w800,fontSize:12)),
              const SizedBox(height:7),
              SelectableText(_display(turn['prompt'])),
              const Divider(height:25),
              const Text('AGENT RESULT',style:TextStyle(
                fontWeight:FontWeight.w800,fontSize:12)),
              const SizedBox(height:7),
              SelectableText(_display(turn['response'],
                'No textual response was returned')),
            ])),
          ],
          const SizedBox(height:18),
          const Text('CONTINUE THIS SESSION',style:TextStyle(
            fontWeight:FontWeight.w800,fontSize:12)),
          const SizedBox(height:10),
          if(!widget.canContinue || !isConnected)
            _panel(const Text('Continuation requires an online signed '
              'worker with this exact provider adapter enabled. '
              'Your saved history remains readable.'))
          else _panel(Column(crossAxisAlignment:CrossAxisAlignment.stretch,
            children:[
              DropdownButtonFormField<String>(
                initialValue:permissionMode,
                decoration:const InputDecoration(
                  labelText:'Permission mode',border:OutlineInputBorder()),
                items:const [
                  DropdownMenuItem(value:'read_only',
                    child:Text('Read only')),
                  DropdownMenuItem(value:'workspace_write',
                    child:Text('Project edits — separately approved')),
                ],
                onChanged:submitting?null:(v)=>
                  setState(()=>permissionMode=v??'read_only'),
              ),
              const SizedBox(height:12),
              TextField(controller:prompt,minLines:3,maxLines:6,maxLength:4000,
                decoration:const InputDecoration(
                  labelText:'Your next instructions',
                  hintText:'Continue the existing coding task…',
                  border:OutlineInputBorder())),
              FilledButton.icon(
                onPressed:submitting?null:_send,
                icon:const Icon(Icons.send_outlined),
                label:Text(submitting?'Submitting request…':
                  'Request next supervised turn')),
              const SizedBox(height:8),
              const Text('Submitting alone never executes a command. '
                'You must separately approve the exact request in Inbox.',
                style:TextStyle(fontSize:12,color:Color(0xFF607078),
                  height:1.4)),
            ])),
        ]),
      )),
    );
  }
}

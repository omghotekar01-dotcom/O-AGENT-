import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'native_agent_directory.dart';
import '../core/controller.dart';
import '../core/pilot_native.dart';
import '../core/agent_directory.dart';
import 'native_sdk_sessions.dart';
import '../theme.dart';
import 'unified_remote_workspace.dart';

const _ink=OTheme.ink, _muted=Color(0xFF66757D), _line=Color(0xFFDCE6E9);
String _val(dynamic x,[String missing='—']) => x==null||x.toString().isEmpty?
  missing:x.toString();
String _codexStatus(dynamic status) => switch(status?.toString()) {
  'available' => 'Saved Codex conversations detected',
  'no_saved_threads' => 'Codex available; no saved threads in this project',
  'missing_cli' => 'Codex CLI not detected on this laptop',
  'rpc_unavailable' => 'Codex app-server could not list saved threads',
  'scan_timeout' => 'Codex session discovery timed out',
  'disabled' => 'Codex discovery disabled for this worker',
  'unavailable' => 'Codex session discovery unavailable',
  _ => 'Checking locally installed Codex sessions',
};
String _date(dynamic x){
  final d=DateTime.tryParse(x?.toString()??'')?.toLocal();
  if(d==null)return 'Not reported';
  String pad(int x)=>x.toString().padLeft(2,'0');
  return pad(d.day)+'/'+pad(d.month)+' '+pad(d.hour)+':'+pad(d.minute);
}
String _name(String value)=>value.replaceAll('_',' ');
void _toast(BuildContext context,String text){
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text(text)));
}
class NativePilotShell extends StatefulWidget{
  const NativePilotShell({super.key,required this.legacy,this.pilot});
  final ControlController legacy;
  final NativePilotController? pilot;
  @override State<NativePilotShell> createState()=>_NativePilotShellState();
}
class _NativePilotShellState extends State<NativePilotShell>{
  late final NativePilotController c=widget.pilot??NativePilotController();
  final endpoint=TextEditingController();
  int tab=0;
  bool rememberDevice=false;
  @override void initState(){
    super.initState();c.addListener(_changed);
    Future.microtask(c.restore);
  }
  void _changed(){
    if(c.origin!=null&&endpoint.text.isEmpty)endpoint.text=c.origin.toString();
    if(mounted)setState((){});
  }
  // Retain the old provider gateway behind one integrated remote tab.
  void _legacy() => setState(() => tab = 2);
  void _nativeDevices() => Navigator.of(context).push(
    CupertinoPageRoute<void>(builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('Trusted computers')),
      body: _Devices(c: c))));
  void _browseAgents() => Navigator.of(context).push(CupertinoPageRoute<void>(
    builder: (_) => Scaffold(
      appBar: AppBar(title: const Text('AI agent directory')),
      body: NativeAgentDirectory(
        pilot: c, preview: true,
        onSessions: () {}, onDevices: () {}, onLegacy: _legacy),
    )));
  @override void dispose(){
    c.removeListener(_changed);endpoint.dispose();
    if(widget.pilot==null)c.dispose();
    super.dispose();
  }
  Future<void> _login() async{
    await c.signIn(endpoint.text, rememberDevice: rememberDevice);
    if(mounted&&c.error!=null)_toast(context,c.error!);
  }
  Future<void> _checkConnection() async {
    await c.testConnection(endpoint.text);
  }
  @override Widget build(BuildContext context){
    if(!c.connected)return Scaffold(body:SafeArea(child:Center(
      child:ConstrainedBox(constraints:const BoxConstraints(maxWidth:540),
        child:ListView(padding:const EdgeInsets.all(22),children:[
          const SizedBox(height:16),
          const Row(children:[
            CircleAvatar(backgroundColor:_ink,child:Text('O',
              style:TextStyle(color:Colors.white,fontWeight:FontWeight.w900))),
            SizedBox(width:12),Text('O-AGENT',style:TextStyle(fontSize:21,
              fontWeight:FontWeight.w900)),Spacer(),
            Text('NATIVE',style:TextStyle(color:OTheme.violet,
              fontSize:11,fontWeight:FontWeight.w800)),
          ]),
          const SizedBox(height:50),
          const Text('YOUR AI AGENTS. ON YOUR PHONE.',
            style:TextStyle(color:OTheme.violet,fontWeight:FontWeight.w800,
              fontSize:12,letterSpacing:0.7)),
          const SizedBox(height:12),
          const Text('Your agents.\nOne command center.',
            style:TextStyle(fontSize:34,fontWeight:FontWeight.w900,
              color:_ink,height:1.14)),
          const SizedBox(height:16),
          const Text('Browse your AI tools, resume verified coding sessions, '
            'send follow-up prompts and review real permissions from one app.',
            style:TextStyle(height:1.5,color:_muted,fontSize:15)),
          const SizedBox(height:26),
          _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
            children:[
              const Text('YOUR PRIVATE CONTROL PLANE',
                style:TextStyle(color:OTheme.violet,fontSize:12,
                  fontWeight:FontWeight.w800)),
              const SizedBox(height:14),
              TextField(controller:endpoint,keyboardType:TextInputType.url,
                autocorrect:false,
                onChanged:(_)=>c.clearLoginFeedback(),
                decoration:const InputDecoration(
                  border:OutlineInputBorder(),prefixIcon:Icon(Icons.lock_outline),
                  labelText:'Private HTTPS address',
                  hintText:'https://your-device.ts.net:8443/')),
              const SizedBox(height:10),
              OutlinedButton.icon(
                onPressed:c.busy?null:_checkConnection,
                icon:const Icon(Icons.network_check),
                label:const Text('Test private connection')),
              if(c.connectionStatus!=null)...[
                const SizedBox(height:10),
                Text(c.connectionStatus!,style:const TextStyle(
                  fontSize:12,color:OTheme.violet)),
              ],
              const SizedBox(height:12),
              Row(children: [
                const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Remember this phone',
                      style: TextStyle(fontWeight: FontWeight.w700)),
                    Text('Encrypted session in Android Keystore / iOS Keychain',
                      style: TextStyle(fontSize: 12, color: _muted)),
                  ])),
                CupertinoSwitch(
                  value: rememberDevice,
                  onChanged: c.busy ? null :
                    (v) => setState(() => rememberDevice = v)),
              ]),
              const SizedBox(height:12),
              FilledButton.icon(onPressed:c.busy?null:_login,
                icon:c.busy?const SizedBox(width:18,height:18,
                  child:CircularProgressIndicator(strokeWidth:2,
                    color:Colors.white)):const Icon(Icons.login),
                label:Text(c.busy?'Connecting securely…':'Sign in to native app')),
              if(c.error!=null)...[
                const SizedBox(height:10),
                Text(c.error!,style:const TextStyle(color:Colors.red)),
              ],
              const SizedBox(height:13),
              const Text('If the connection test fails, check Tailscale '
                'on your phone and start START-O-AGENT.cmd on your PC. '
                'Keycloak then opens the secure Android sign-in window. '
                'Your command center stays native.',
                style:TextStyle(fontSize:12,height:1.5,color:_muted)),
            ])),
          const SizedBox(height:16),
          OutlinedButton.icon(onPressed: _browseAgents,
            icon: const Icon(Icons.apps_outlined),
            label: const Text('Browse AI agents and integrations')),
          const SizedBox(height:22),
          const _Feature(Icons.laptop_mac,'Trusted computer',
            'Verified workers and enrolled project folders'),
          const _Feature(Icons.forum_outlined,'Real agent activity',
            'Continue supported SDK sessions with prompts'),
          const _Feature(Icons.shield_outlined,'Exact approvals',
            'Review commands before a worker executes them'),
          const SizedBox(height:12),
          const Text('Real screen and project controls appear in the '
            'Remote tab after secure sign-in.',
            style:TextStyle(color:_muted,fontSize:12,height:1.4)),
        ]),
      ))));
    return Scaffold(
      appBar: CupertinoNavigationBar(
        transitionBetweenRoutes: false,
        backgroundColor: const Color(0xFFF7F9FB),
        border: const Border(bottom: BorderSide(color: _line, width: 0.5)),
        middle: const Text('O-AGENT',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800,
            color: _ink)),
        trailing: CupertinoButton(
          padding: EdgeInsets.zero,
          onPressed: c.syncing ? null : c.refresh,
          child: const Icon(CupertinoIcons.refresh, color: OTheme.violet)),
      ),
      body: SafeArea(child: Column(children: [
        if (c.error != null) MaterialBanner(
          content: Text(c.error!, maxLines: 3),
          actions: [TextButton(onPressed: c.refresh,
            child: const Text('RETRY'))]),
        Expanded(child: IndexedStack(index: tab, children: [
          NativeAgentDirectory(pilot: c, onLegacy: _legacy,
            onSessions: () => setState(() => tab = 1),
            onDevices: _nativeDevices,
            onInbox: () => setState(() => tab = 3)),
          _Work(c: c, navigate: (i) => setState(() => tab = i)),
          UnifiedRemoteWorkspace(legacy: widget.legacy,
            onDevices: _nativeDevices),
          _Inbox(c: c),
          _More(c: c, legacy: _legacy,
            agents: () => setState(() => tab = 0),
            devices: _nativeDevices),
        ])),
      ])),
      bottomNavigationBar: CupertinoTabBar(
        currentIndex: tab,
        onTap: (i) => setState(() => tab = i),
        activeColor: OTheme.violet,
        inactiveColor: const Color(0xFF788792),
        backgroundColor: const Color(0xFFFAFBFC),
        border: const Border(top: BorderSide(color: _line, width: 0.5)),
        items: const [
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.square_grid_2x2), label: 'Agents'),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.chat_bubble_2), label: 'Sessions'),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.desktopcomputer), label: 'Remote'),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.tray_full), label: 'Inbox'),
          BottomNavigationBarItem(
            icon: Icon(CupertinoIcons.settings), label: 'Settings'),
        ],
      ),
    );
  }
}
class _Panel extends StatelessWidget{
  const _Panel({required this.child});
  final Widget child;
  @override Widget build(BuildContext context)=>Material(
    color:Colors.white,
    shape:RoundedRectangleBorder(
      borderRadius:BorderRadius.circular(17),
      side:const BorderSide(color:_line)),
    child:Padding(padding:const EdgeInsets.all(17),
      child:SizedBox(width:double.infinity,child:child)));
}
class _Feature extends StatelessWidget{
  const _Feature(this.icon,this.title,this.detail);
  final IconData icon;final String title,detail;
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.only(bottom:16),child:Row(children:[
      Container(padding:const EdgeInsets.all(10),decoration:BoxDecoration(
        color:OTheme.lavender,borderRadius:BorderRadius.circular(10)),
        child:Icon(icon,color:OTheme.violet)),
      const SizedBox(width:12),Expanded(child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text(title,style:const TextStyle(fontWeight:FontWeight.w800)),
          Text(detail,style:const TextStyle(color:_muted,fontSize:12)),
        ])),
    ]));
}
class _Heading extends StatelessWidget{
  const _Heading(this.title,this.detail);
  final String title,detail;
  @override Widget build(BuildContext context)=>Padding(
    padding:const EdgeInsets.only(bottom:17),child:Column(
      crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text(title,style:const TextStyle(fontSize:26,fontWeight:FontWeight.w900)),
        const SizedBox(height:4),
        Text(detail,style:const TextStyle(color:_muted,height:1.4)),
      ]));
}
class _Blank extends StatelessWidget{
  const _Blank(this.title,this.detail,{this.icon=Icons.inbox_outlined});
  final String title,detail;final IconData icon;
  @override Widget build(BuildContext context)=>_Panel(child:Column(children:[
    Icon(icon,size:35,color:OTheme.violet),
    const SizedBox(height:12),Text(title,textAlign:TextAlign.center,
      style:const TextStyle(fontWeight:FontWeight.w800)),
    const SizedBox(height:7),Text(detail,textAlign:TextAlign.center,
      style:const TextStyle(color:_muted,height:1.5)),
  ]));
}
Widget _pill(String text,{bool online=false})=>Container(
  padding:const EdgeInsets.symmetric(horizontal:9,vertical:5),
  decoration:BoxDecoration(color:online?OTheme.sage:OTheme.lavender,
    borderRadius:BorderRadius.circular(30)),
  child:Text(_name(text),style:TextStyle(
    fontSize:11,fontWeight:FontWeight.w800,
    color:online?const Color(0xFF467862):OTheme.violet)));
class _Work extends StatefulWidget{
  const _Work({required this.c,required this.navigate});
  final NativePilotController c;final ValueChanged<int> navigate;
  @override State<_Work> createState()=>_WorkState();
}
class _WorkState extends State<_Work>{
  final prompt=TextEditingController();
  String? machineId,operation,savedSessionId;
  String mode='read_only';bool sending=false;
  @override void dispose(){prompt.dispose();super.dispose();}
  void _useSavedSession(Map<String,dynamic> saved){
    setState((){
      machineId=saved['deviceId']?.toString();
      operation='codex_cli_turn';
      savedSessionId=saved['sessionId']?.toString();
    });
  }
  Future<void> _submit(Map<String,dynamic> machine,String kind)async{
    if(sending)return;
    if(kind=='codex_cli_turn'&&savedSessionId==null){
      final candidate=widget.c.sessions.where((x)=>
        x['deviceId']==machine['id']).firstOrNull;
      if(candidate==null){
        _toast(context,'No verified Codex conversation on this worker.');return;
      }
      savedSessionId=candidate['sessionId']?.toString();
    }
    final text=kind=='workspace_inventory'
      ?'Inspect enrolled workspace files':prompt.text.trim();
    if(text.isEmpty){_toast(context,'Enter a prompt first.');return;}
    // The owner's Send tap authorizes a read-only agent request.
    // Separate sensitive tool and write approvals remain server-enforced.
    setState(()=>sending=true);
    try{
      final created=await widget.c.requestTurn(
        device:machine,kind:kind,mode:mode,prompt:text,
        sessionId:kind=='codex_cli_turn' ?savedSessionId:null);
      if(!mounted)return;
      prompt.clear();
      final id=created['runId']?.toString()??'';
      if(RegExp(r'^[0-9a-f-]{36}
    }catch(e){if(mounted)_toast(context,pilotFriendlyError(e));}
    finally{if(mounted)setState(()=>sending=false);}
  }
  @override Widget build(BuildContext context){
    final online=widget.c.devices.where(pilotDeviceOnline).toList();
    final selected=online.where((m)=>m['id']==machineId).firstOrNull ??
      (online.isEmpty?null:online.first);
    final available=((selected?['capabilities'] as List?)??[])
      .map((x)=>x.toString()).where((x)=>const [
        'workspace_inventory','codex_cli_turn','claude_agent_turn',
        'copilot_sdk_turn'].contains(x)).toList();
    // A provider conversation is preferred over diagnostic inventory.
    final kind=preferredAgentOperation(available,selected:operation);
    final savedForDevice=widget.c.sessions
      .where((x)=>x['deviceId']==selected?['id']).toList();
    final chosenSaved=savedForDevice.where(
      (x)=>x['sessionId']==savedSessionId).firstOrNull;
    return RefreshIndicator(onRefresh:widget.c.refresh,
      child:ListView(padding:const EdgeInsets.all(18),children:[
        const _Heading('AI sessions & prompts',
          'Resume verified agent sessions, inspect output, and send follow-ups.'),
        const Text('YOUR REAL SAVED CODEX THREADS',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:9),
        if(widget.c.sessions.isEmpty)
          const _Blank('No saved Codex sessions synchronized yet',
            'Keep your laptop worker online. The app lists existing CLI and '
            'VS Code Codex threads found inside the enrolled project, '
            'without copying IDs or opening a website.')
        else for(final saved in widget.c.sessions.take(20))...[
          _Panel(child:InkWell(
            onTap:()=>Navigator.push(context,MaterialPageRoute<void>(
              builder:(_)=>NativeSavedSessionDetail(
                saved:saved,
                c:widget.c,navigate:widget.navigate,
                canContinue:online.any((m)=>m['id']==saved['deviceId'] &&
                  ((m['capabilities'] as List?)?.contains('codex_cli_turn')??false)),
                onContinue:()=>_useSavedSession(saved)))),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                const Icon(Icons.forum_outlined,color:OTheme.violet),
                const SizedBox(width:9),
                Expanded(child:Text(_val(saved['title']),
                  style:const TextStyle(fontWeight:FontWeight.w800))),
                const Icon(Icons.chevron_right,color:OTheme.violet),
              ]),
              const SizedBox(height:8),
              Text(_val(saved['preview'],'Open saved thread'),
                maxLines:3,overflow:TextOverflow.ellipsis,
                style:const TextStyle(color:_muted)),
              const SizedBox(height:6),
              Text('Saved thread · '+_name(_val(saved['sourceKind']))+
                ' · '+_date(saved['updatedAt']),
                style:const TextStyle(color:_muted,fontSize:11)),
            ]))),
          const SizedBox(height:9),
        ],
        const SizedBox(height:20),
        const Text('CLAUDE & COPILOT SDK CONVERSATIONS',
          style:TextStyle(color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:9),
        if(widget.c.providerSessions.isEmpty)
          const _Blank('No SDK-owned conversations yet',
            'Completed Claude and GitHub Copilot SDK sessions from your '
            'trusted workers appear here. These are not external website tabs.')
        else for(final provider in widget.c.providerSessions.take(20))...[
          _Panel(child:InkWell(
            onTap:()=>Navigator.push(context,MaterialPageRoute<void>(
              builder:(_)=>NativeProviderSessionDetail(
                pilot:widget.c,session:provider,
                canContinue:online.any((machine)=>
                  machine['id']==provider['deviceId'] &&
                  ((machine['capabilities'] as List?)?.contains(provider['kind'])??false)),
                onRequested:()=>widget.navigate(3)))),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                const Icon(Icons.smart_toy_outlined,color:OTheme.violet),
                const SizedBox(width:10),
                Expanded(child:Text(
                  pilotCapabilityLabel(_val(provider['kind'])),
                  style:const TextStyle(fontWeight:FontWeight.w800))),
                const Icon(Icons.chevron_right,color:OTheme.violet),
              ]),
              const SizedBox(height:7),
              Text(_val(provider['lastPrompt'],
                'Completed SDK conversation'),
                maxLines:2,overflow:TextOverflow.ellipsis),
              const SizedBox(height:5),
              Text(_val(provider['deviceName'])+' · '+
                _date(provider['updatedAt']),
                style:const TextStyle(fontSize:12,color:_muted)),
            ]))),
          const SizedBox(height:9),
        ],
        const SizedBox(height:20),
        if(online.isEmpty)...[
          const _Blank('Your worker is offline',
            'Open START-O-AGENT.cmd on your laptop and keep it running.',
            icon:Icons.laptop_chromebook),const SizedBox(height:20),
        ]else _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            const Text('START AN AGENT TURN',style:TextStyle(
              color:OTheme.violet,fontWeight:FontWeight.w800)),
            const SizedBox(height:6),
            const Text('Choose your real agent and conversation. '
              'Workspace inventory is only a read-only diagnostic.',
              style:TextStyle(color:_muted,fontSize:12)),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(
              key:ValueKey('worker-'+_val(selected?['id'])),
              initialValue:selected?['id']?.toString(),
              decoration:const InputDecoration(labelText:'Enrolled laptop',
                border:OutlineInputBorder()),
              items:[for(final d in online)DropdownMenuItem<String>(
                value:d['id']?.toString(),child:Text(_val(d['name'])) )],
              onChanged:(v)=>setState((){
                machineId=v;operation=null;savedSessionId=null;
              })),
            const SizedBox(height:9),
            Text('Trusted project: '+_val(selected?['workspace_root']),
              style:const TextStyle(color:_muted,fontSize:12)),
            const SizedBox(height:12),
            if(kind!=null)DropdownButtonFormField<String>(
              key:ValueKey('kind-'+kind),initialValue:kind,
              decoration:const InputDecoration(labelText:'Provider operation',
                border:OutlineInputBorder()),
              items:[for(final k in available)DropdownMenuItem<String>(
                value:k,child:Text(pilotCapabilityLabel(k)))],
              onChanged:(v)=>setState((){
                operation=v;
                if(v!='codex_cli_turn')savedSessionId=null;
              }))
            else const Text('No compatible provider enabled on this worker.',
              style:TextStyle(color:_muted)),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(initialValue:mode,
              decoration:const InputDecoration(labelText:'Permission mode',
                border:OutlineInputBorder()),
              items:const [
                DropdownMenuItem(value:'read_only',
                  child:Text('Read only')),
                DropdownMenuItem(value:'workspace_write',
                  child:Text('Project edits (separate tool approvals)')),
              ],onChanged:(v)=>setState(()=>mode=v??'read_only')),
            if(kind=='codex_cli_turn')...[
              const SizedBox(height:12),
              if(savedForDevice.isEmpty)
                const Text('No verified saved Codex threads on this worker yet. '
                  'Check local Codex login and keep the worker online.',
                  style:TextStyle(color:Colors.red,height:1.45))
              else DropdownButtonFormField<String>(
                key:ValueKey('codex-'+_val(selected?['id'])+'-'+_val(savedSessionId)),
                initialValue:chosenSaved?['sessionId']?.toString() ??
                  savedForDevice.first['sessionId']?.toString(),
                decoration:const InputDecoration(
                  border:OutlineInputBorder(),
                  labelText:'Real saved Codex conversation'),
                items:[for(final x in savedForDevice)
                  DropdownMenuItem<String>(value:x['sessionId']?.toString(),
                    child:Text(_val(x['title']),
                      overflow:TextOverflow.ellipsis))],
                onChanged:(v)=>setState(()=>savedSessionId=v)),
            ],
            const SizedBox(height:12),
            TextField(controller:prompt,minLines:3,maxLines:5,maxLength:4000,
              decoration:InputDecoration(border:const OutlineInputBorder(),
                labelText:'Your next prompt',
                hintText:kind=='workspace_inventory'
                  ?'Read-only inventory does not require a prompt'
                  :'Continue the task; explain what changed.')),
            FilledButton.icon(
              onPressed:sending||kind==null||
                (kind=='codex_cli_turn'&&savedForDevice.isEmpty)
                ?null:()=>_submit(selected!,kind),
              icon:const Icon(Icons.send_outlined),
              label:Text(sending?'Sending to agent…':'Send to agent')),
            const SizedBox(height:9),
            const Text('Only real provider capabilities advertised by your '
              'enrolled worker are shown. No automatic approvals.',
              style:TextStyle(color:_muted,fontSize:12,height:1.4)),
          ])),
        const SizedBox(height:24),
        const Text('SAVED RUN HISTORY',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:12),
        if(widget.c.runs.isEmpty)
          const _Blank('No recorded runs','Real agent sessions appear after the first request.')
        else for(final run in widget.c.runs)...[
          _RunTile(c:widget.c,run:run),const SizedBox(height:10)],
      ]));
  }
}

).hasMatch(id)){
        Navigator.push(context,CupertinoPageRoute<void>(
          builder:(_)=>NativeRunDetail(c:widget.c,id:id)));
      }else{
        _toast(context,'Agent request saved. Refresh the run history.');
      }
    }catch(e){if(mounted)_toast(context,pilotFriendlyError(e));}
    finally{if(mounted)setState(()=>sending=false);}
  }
  @override Widget build(BuildContext context){
    final online=widget.c.devices.where(pilotDeviceOnline).toList();
    final selected=online.where((m)=>m['id']==machineId).firstOrNull ??
      (online.isEmpty?null:online.first);
    final available=((selected?['capabilities'] as List?)??[])
      .map((x)=>x.toString()).where((x)=>const [
        'workspace_inventory','codex_cli_turn','claude_agent_turn',
        'copilot_sdk_turn'].contains(x)).toList();
    // A provider conversation is preferred over diagnostic inventory.
    final kind=preferredAgentOperation(available,selected:operation);
    final savedForDevice=widget.c.sessions
      .where((x)=>x['deviceId']==selected?['id']).toList();
    final chosenSaved=savedForDevice.where(
      (x)=>x['sessionId']==savedSessionId).firstOrNull;
    return RefreshIndicator(onRefresh:widget.c.refresh,
      child:ListView(padding:const EdgeInsets.all(18),children:[
        const _Heading('AI sessions & prompts',
          'Resume verified agent sessions, inspect output, and send follow-ups.'),
        const Text('YOUR REAL SAVED CODEX THREADS',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:9),
        if(widget.c.sessions.isEmpty)
          const _Blank('No saved Codex sessions synchronized yet',
            'Keep your laptop worker online. The app lists existing CLI and '
            'VS Code Codex threads found inside the enrolled project, '
            'without copying IDs or opening a website.')
        else for(final saved in widget.c.sessions.take(20))...[
          _Panel(child:InkWell(
            onTap:()=>Navigator.push(context,MaterialPageRoute<void>(
              builder:(_)=>NativeSavedSessionDetail(
                saved:saved,
                c:widget.c,navigate:widget.navigate,
                canContinue:online.any((m)=>m['id']==saved['deviceId'] &&
                  ((m['capabilities'] as List?)?.contains('codex_cli_turn')??false)),
                onContinue:()=>_useSavedSession(saved)))),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                const Icon(Icons.forum_outlined,color:OTheme.violet),
                const SizedBox(width:9),
                Expanded(child:Text(_val(saved['title']),
                  style:const TextStyle(fontWeight:FontWeight.w800))),
                const Icon(Icons.chevron_right,color:OTheme.violet),
              ]),
              const SizedBox(height:8),
              Text(_val(saved['preview'],'Open saved thread'),
                maxLines:3,overflow:TextOverflow.ellipsis,
                style:const TextStyle(color:_muted)),
              const SizedBox(height:6),
              Text('Saved thread · '+_name(_val(saved['sourceKind']))+
                ' · '+_date(saved['updatedAt']),
                style:const TextStyle(color:_muted,fontSize:11)),
            ]))),
          const SizedBox(height:9),
        ],
        const SizedBox(height:20),
        const Text('CLAUDE & COPILOT SDK CONVERSATIONS',
          style:TextStyle(color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:9),
        if(widget.c.providerSessions.isEmpty)
          const _Blank('No SDK-owned conversations yet',
            'Completed Claude and GitHub Copilot SDK sessions from your '
            'trusted workers appear here. These are not external website tabs.')
        else for(final provider in widget.c.providerSessions.take(20))...[
          _Panel(child:InkWell(
            onTap:()=>Navigator.push(context,MaterialPageRoute<void>(
              builder:(_)=>NativeProviderSessionDetail(
                pilot:widget.c,session:provider,
                canContinue:online.any((machine)=>
                  machine['id']==provider['deviceId'] &&
                  ((machine['capabilities'] as List?)?.contains(provider['kind'])??false)),
                onRequested:()=>widget.navigate(3)))),
            child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              Row(children:[
                const Icon(Icons.smart_toy_outlined,color:OTheme.violet),
                const SizedBox(width:10),
                Expanded(child:Text(
                  pilotCapabilityLabel(_val(provider['kind'])),
                  style:const TextStyle(fontWeight:FontWeight.w800))),
                const Icon(Icons.chevron_right,color:OTheme.violet),
              ]),
              const SizedBox(height:7),
              Text(_val(provider['lastPrompt'],
                'Completed SDK conversation'),
                maxLines:2,overflow:TextOverflow.ellipsis),
              const SizedBox(height:5),
              Text(_val(provider['deviceName'])+' · '+
                _date(provider['updatedAt']),
                style:const TextStyle(fontSize:12,color:_muted)),
            ]))),
          const SizedBox(height:9),
        ],
        const SizedBox(height:20),
        if(online.isEmpty)...[
          const _Blank('Your worker is offline',
            'Open START-O-AGENT.cmd on your laptop and keep it running.',
            icon:Icons.laptop_chromebook),const SizedBox(height:20),
        ]else _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            const Text('SUPPORTED AI AGENT TURN',style:TextStyle(
              color:OTheme.violet,fontWeight:FontWeight.w800)),
            const SizedBox(height:6),
            const Text('Choose your real agent and conversation. '
              'Workspace inventory is only a read-only diagnostic.',
              style:TextStyle(color:_muted,fontSize:12)),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(
              key:ValueKey('worker-'+_val(selected?['id'])),
              initialValue:selected?['id']?.toString(),
              decoration:const InputDecoration(labelText:'Enrolled laptop',
                border:OutlineInputBorder()),
              items:[for(final d in online)DropdownMenuItem<String>(
                value:d['id']?.toString(),child:Text(_val(d['name'])) )],
              onChanged:(v)=>setState((){
                machineId=v;operation=null;savedSessionId=null;
              })),
            const SizedBox(height:9),
            Text('Trusted project: '+_val(selected?['workspace_root']),
              style:const TextStyle(color:_muted,fontSize:12)),
            const SizedBox(height:12),
            if(kind!=null)DropdownButtonFormField<String>(
              key:ValueKey('kind-'+kind),initialValue:kind,
              decoration:const InputDecoration(labelText:'Provider operation',
                border:OutlineInputBorder()),
              items:[for(final k in available)DropdownMenuItem<String>(
                value:k,child:Text(pilotCapabilityLabel(k)))],
              onChanged:(v)=>setState((){
                operation=v;
                if(v!='codex_cli_turn')savedSessionId=null;
              }))
            else const Text('No compatible provider enabled on this worker.',
              style:TextStyle(color:_muted)),
            const SizedBox(height:12),
            DropdownButtonFormField<String>(initialValue:mode,
              decoration:const InputDecoration(labelText:'Permission mode',
                border:OutlineInputBorder()),
              items:const [
                DropdownMenuItem(value:'read_only',
                  child:Text('Read only')),
                DropdownMenuItem(value:'workspace_write',
                  child:Text('Project edits (separate tool approvals)')),
              ],onChanged:(v)=>setState(()=>mode=v??'read_only')),
            if(kind=='codex_cli_turn')...[
              const SizedBox(height:12),
              if(savedForDevice.isEmpty)
                const Text('No verified saved Codex threads on this worker yet. '
                  'Check local Codex login and keep the worker online.',
                  style:TextStyle(color:Colors.red,height:1.45))
              else DropdownButtonFormField<String>(
                key:ValueKey('codex-'+_val(selected?['id'])+'-'+_val(savedSessionId)),
                initialValue:chosenSaved?['sessionId']?.toString() ??
                  savedForDevice.first['sessionId']?.toString(),
                decoration:const InputDecoration(
                  border:OutlineInputBorder(),
                  labelText:'Real saved Codex conversation'),
                items:[for(final x in savedForDevice)
                  DropdownMenuItem<String>(value:x['sessionId']?.toString(),
                    child:Text(_val(x['title']),
                      overflow:TextOverflow.ellipsis))],
                onChanged:(v)=>setState(()=>savedSessionId=v)),
            ],
            const SizedBox(height:12),
            TextField(controller:prompt,minLines:3,maxLines:5,maxLength:4000,
              decoration:InputDecoration(border:const OutlineInputBorder(),
                labelText:'Your next prompt',
                hintText:kind=='workspace_inventory'
                  ?'Read-only inventory does not require a prompt'
                  :'Continue the task; explain what changed.')),
            FilledButton.icon(
              onPressed:sending||kind==null||
                (kind=='codex_cli_turn'&&savedForDevice.isEmpty)
                ?null:()=>_submit(selected!,kind),
              icon:const Icon(Icons.send_outlined),
              label:Text(sending?'Requesting…':'Review and request approval')),
            const SizedBox(height:9),
            const Text('Only real provider capabilities advertised by your '
              'enrolled worker are shown. No automatic approvals.',
              style:TextStyle(color:_muted,fontSize:12,height:1.4)),
          ])),
        const SizedBox(height:24),
        const Text('SAVED RUN HISTORY',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:12),
        if(widget.c.runs.isEmpty)
          const _Blank('No recorded runs','Real agent sessions appear after the first request.')
        else for(final run in widget.c.runs)...[
          _RunTile(c:widget.c,run:run),const SizedBox(height:10)],
      ]));
  }
}

class NativeSavedSessionDetail extends StatefulWidget {
  const NativeSavedSessionDetail({super.key,required this.saved,
    required this.canContinue,required this.onContinue,
    required this.c,required this.navigate});
  final Map<String,dynamic> saved;
  final bool canContinue;
  final VoidCallback onContinue;
  final NativePilotController c;
  final ValueChanged<int> navigate;
  @override State<NativeSavedSessionDetail> createState() =>
    _NativeSavedSessionDetailState();
}
class _NativeSavedSessionDetailState extends State<NativeSavedSessionDetail> {
  final composer=TextEditingController();
  @override void initState(){
    super.initState();
    widget.c.addListener(_onUpdated);
  }
  void _onUpdated(){
    if(mounted)setState((){});
  }
  String mode='read_only';
  bool sending=false;
  @override void dispose(){
    widget.c.removeListener(_onUpdated);
    composer.dispose();
    super.dispose();
  }
  Future<void> _send() async {
    if(sending||!widget.canContinue)return;
    final message=composer.text.trim();
    if(message.isEmpty){
      _toast(context,'Write the next prompt to continue this saved session.');
      return;
    }
    final device=widget.c.devices.where((d)=>
      d['id']==widget.saved['deviceId']).firstOrNull;
    if(device==null || !pilotDeviceOnline(device)){
      _toast(context,'Your laptop worker is offline. Your prompt has not been sent.');
      return;
    }
    // The owner's Send tap is read-only authorization.
    setState(()=>sending=true);
    try {
      final created=await widget.c.requestTurn(
        device:device,kind:'codex_cli_turn',mode:mode,prompt:message,
        sessionId:widget.saved['sessionId']?.toString());
      if(!mounted)return;
      composer.clear();
      final id=created['runId']?.toString()??'';
      if(RegExp(r'^[0-9a-f-]{36}
    }catch(error){
      if(mounted)_toast(context,pilotFriendlyError(error));
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  }
  @override Widget build(BuildContext context){
    final latest=widget.c.sessions.where((x)=>
      x['deviceId']==widget.saved['deviceId'] &&
      x['sessionId']==widget.saved['sessionId']).firstOrNull ??widget.saved;
    final messages=(latest['messages'] as List?)??[];
    return Scaffold(
      appBar:AppBar(title:const Text('Codex conversation')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
        _Heading(_val(latest['title']),
          'Real stored CLI/VS Code conversation history, not live screen control.'),
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Worker: '+_val(widget.saved['deviceName']),
            style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:6),
          SelectableText('Enrolled folder: '+_val(widget.saved['cwd']),
            style:const TextStyle(fontSize:12,color:_muted)),
          Text('Last activity: '+_date(latest['updatedAt']),
            style:const TextStyle(fontSize:12,color:_muted)),
          Text('Last synchronized: '+_date(latest['syncedAt']),
            style:const TextStyle(fontSize:12,color:_muted)),
        ])),
        const SizedBox(height:20),
        const Text('SAVED CONVERSATION',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:10),
        if(messages.isEmpty)
          const _Blank('No readable messages in this saved snapshot',
            'Codex provided metadata only. Recent messages appear here '
            'when the installed provider version exposes them.')
        else for(final message in messages)...[
          _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(message is Map && message['role']=='user'?'YOU':'CODEX',
              style:const TextStyle(color:OTheme.violet,
                fontWeight:FontWeight.w800,fontSize:12)),
            const SizedBox(height:7),
            SelectableText(message is Map
              ?_val(message['text']):'Unsupported saved message',
              style:const TextStyle(height:1.5)),
          ])),
          const SizedBox(height:10),
        ],
        const SizedBox(height:13),
        if(widget.canContinue) _Panel(child:Column(
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            const Text('NEXT INSTRUCTION',style:TextStyle(
              color:OTheme.violet,fontWeight:FontWeight.w800)),
            const SizedBox(height:7),
            const Text('Continue this saved thread on your enrolled laptop. '
              'Actual actions still require separate approval.',
              style:TextStyle(color:_muted,fontSize:12,height:1.4)),
            const SizedBox(height:12),
            TextField(controller:composer,minLines:3,maxLines:6,maxLength:4000,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),
                hintText:'Continue this task and show the changes…',
                labelText:'Write the next prompt')),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(initialValue:mode,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Permissions'),
              items:const [
                DropdownMenuItem(value:'read_only',
                  child:Text('Read-only (no workspace edits)')),
                DropdownMenuItem(value:'workspace_write',
                  child:Text('Allow project edits with approvals')),
              ],
              onChanged:sending?null:(v)=>setState(()=>mode=v??'read_only')),
            const SizedBox(height:14),
            FilledButton.icon(
              onPressed:sending?null:_send,
              icon:const Icon(Icons.send_outlined),
              label:Text(sending?'Creating request…':'Review prompt & request approval')),
          ]))
        else const _Blank('Read only for now',
          'The saved history is available, but this worker is offline '
          'or has not enabled supervised Codex continuation.'),
        const SizedBox(height:12),
        OutlinedButton.icon(
          onPressed:widget.canContinue?(){
            widget.onContinue();
            Navigator.pop(context);
          }:null,
          icon:const Icon(Icons.work_outline),
          label:const Text('Use the detailed Work controls')),
      ])),
    );
  }
}

).hasMatch(id)){
        Navigator.push(context,CupertinoPageRoute<void>(
          builder:(_)=>NativeRunDetail(c:widget.c,id:id)));
      }else{
        _toast(context,'Agent request saved. Check activity.');
      }
    }catch(error){
      if(mounted)_toast(context,pilotFriendlyError(error));
    }finally{
      if(mounted)setState(()=>sending=false);
    }
  }
  @override Widget build(BuildContext context){
    final latest=widget.c.sessions.where((x)=>
      x['deviceId']==widget.saved['deviceId'] &&
      x['sessionId']==widget.saved['sessionId']).firstOrNull ??widget.saved;
    final messages=(latest['messages'] as List?)??[];
    return Scaffold(
      appBar:AppBar(title:const Text('Codex conversation')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
        _Heading(_val(latest['title']),
          'Real stored CLI/VS Code conversation history, not live screen control.'),
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Worker: '+_val(widget.saved['deviceName']),
            style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:6),
          SelectableText('Enrolled folder: '+_val(widget.saved['cwd']),
            style:const TextStyle(fontSize:12,color:_muted)),
          Text('Last activity: '+_date(latest['updatedAt']),
            style:const TextStyle(fontSize:12,color:_muted)),
          Text('Last synchronized: '+_date(latest['syncedAt']),
            style:const TextStyle(fontSize:12,color:_muted)),
        ])),
        const SizedBox(height:20),
        const Text('SAVED CONVERSATION',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:10),
        if(messages.isEmpty)
          const _Blank('No readable messages in this saved snapshot',
            'Codex provided metadata only. Recent messages appear here '
            'when the installed provider version exposes them.')
        else for(final message in messages)...[
          _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(message is Map && message['role']=='user'?'YOU':'CODEX',
              style:const TextStyle(color:OTheme.violet,
                fontWeight:FontWeight.w800,fontSize:12)),
            const SizedBox(height:7),
            SelectableText(message is Map
              ?_val(message['text']):'Unsupported saved message',
              style:const TextStyle(height:1.5)),
          ])),
          const SizedBox(height:10),
        ],
        const SizedBox(height:13),
        if(widget.canContinue) _Panel(child:Column(
          crossAxisAlignment:CrossAxisAlignment.stretch,children:[
            const Text('NEXT INSTRUCTION',style:TextStyle(
              color:OTheme.violet,fontWeight:FontWeight.w800)),
            const SizedBox(height:7),
            const Text('Continue this saved thread on your enrolled laptop. '
              'Actual actions still require separate approval.',
              style:TextStyle(color:_muted,fontSize:12,height:1.4)),
            const SizedBox(height:12),
            TextField(controller:composer,minLines:3,maxLines:6,maxLength:4000,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),
                hintText:'Continue this task and show the changes…',
                labelText:'Write the next prompt')),
            const SizedBox(height:10),
            DropdownButtonFormField<String>(initialValue:mode,
              decoration:const InputDecoration(
                border:OutlineInputBorder(),labelText:'Permissions'),
              items:const [
                DropdownMenuItem(value:'read_only',
                  child:Text('Read-only (no workspace edits)')),
                DropdownMenuItem(value:'workspace_write',
                  child:Text('Allow project edits with approvals')),
              ],
              onChanged:sending?null:(v)=>setState(()=>mode=v??'read_only')),
            const SizedBox(height:14),
            FilledButton.icon(
              onPressed:sending?null:_send,
              icon:const Icon(Icons.send_outlined),
              label:Text(sending?'Creating request…':'Review prompt & request approval')),
          ]))
        else const _Blank('Read only for now',
          'The saved history is available, but this worker is offline '
          'or has not enabled supervised Codex continuation.'),
        const SizedBox(height:12),
        OutlinedButton.icon(
          onPressed:widget.canContinue?(){
            widget.onContinue();
            Navigator.pop(context);
          }:null,
          icon:const Icon(Icons.work_outline),
          label:const Text('Use the detailed Work controls')),
      ])),
    );
  }
}

class _RunTile extends StatelessWidget{
  const _RunTile({required this.c,required this.run});
  final NativePilotController c;final Map<String,dynamic> run;
  @override Widget build(BuildContext context)=>InkWell(
    onTap:()=>Navigator.push(context,MaterialPageRoute<void>(
      builder:(_)=>NativeRunDetail(c:c,id:_val(run['id'])))),
    borderRadius:BorderRadius.circular(14),
    child:_Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
      children:[
        Row(children:[
          Expanded(child:Text(pilotCapabilityLabel(_val(run['kind'])),
            style:const TextStyle(fontWeight:FontWeight.w800))),
          _pill(_val(run['status'])),
        ]),
        const SizedBox(height:9),
        Text('Updated '+_date(run['updated_at']),
          style:const TextStyle(color:_muted,fontSize:12)),
        if(run['error']!=null)Text(_val(run['error']),
          style:const TextStyle(color:Colors.red)),
        const SizedBox(height:9),
        const Row(mainAxisAlignment:MainAxisAlignment.end,children:[
          Text('Inspect activity',style:TextStyle(color:OTheme.violet,
            fontWeight:FontWeight.w700)),
          Icon(Icons.chevron_right,color:OTheme.violet),
        ]),
      ])));
}

class NativeRunDetail extends StatefulWidget{
  const NativeRunDetail({super.key,required this.c,required this.id});
  final NativePilotController c;final String id;
  @override State<NativeRunDetail> createState()=>_NativeRunDetailState();
}
class _NativeRunDetailState extends State<NativeRunDetail>{
  Map<String,dynamic>? run;List<Map<String,dynamic>> events=[];
  String? error;Timer? timer;
  @override void initState(){
    super.initState();Future.microtask(_reload);
    timer=Timer.periodic(const Duration(seconds:5),(_)=>_reload());
  }
  Future<void> _reload() async{
    try{
      final detail=await widget.c.runDetail(widget.id);
      final activity=await widget.c.runEvents(widget.id);
      if(mounted)setState((){
        run=detail;events=activity;error=null;
      });
    }catch(e){if(mounted)setState(()=>error=pilotFriendlyError(e));}
  }
  Future<void> _supervise({required bool acknowledge}) async {
    final approved=await showCupertinoDialog<bool>(context:context,builder:(dialog)=>
      CupertinoAlertDialog(
        title:Text(acknowledge?'Acknowledge interrupted execution?'
          :'Cancel this queued request?'),
        content:Text(acknowledge
          ?'The worker may have made changes before its connection broke. '
            'This marks the interrupted run failed WITHOUT replaying it. '
            'Inspect your project before starting new work.'
          :'This cancels a run that has not started. It cannot undo a run '
            'that the worker has already executed.'),
        actions:[
          CupertinoDialogAction(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Keep current state')),
          CupertinoDialogAction(isDefaultAction:true,onPressed:()=>Navigator.pop(dialog,true),
            child:Text(acknowledge?'Mark failed; do not replay':'Cancel request')),
        ]));
    if(approved!=true||!mounted)return;
    try{
      if(acknowledge){
        await widget.c.acknowledgeInterruptedRun(widget.id);
      }else{
        await widget.c.cancelRun(widget.id);
      }
      await _reload();
      if(mounted)_toast(context,acknowledge
        ?'Interrupted run acknowledged. No action was replayed.'
        :'Pending run cancelled.');
    }catch(e){if(mounted)_toast(context,pilotFriendlyError(e));}
  }
  @override void dispose(){timer?.cancel();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Native agent activity'),
      actions:[IconButton(onPressed:_reload,icon:const Icon(Icons.refresh))]),
    body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
      if(error!=null)Text(error!,style:const TextStyle(color:Colors.red)),
      if(run==null)const Center(child:CircularProgressIndicator())
      else...[
        _Heading(pilotCapabilityLabel(_val(run!['kind'])),
          'Actual worker and provider activity, from your backend.'),
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            _pill(_val(run!['status'])),
            const SizedBox(height:12),
            const Text('YOUR PROMPT',style:TextStyle(color:OTheme.violet,
              fontWeight:FontWeight.w800)),
            const SizedBox(height:5),
            SelectableText(_val(run!['prompt'])),
            const SizedBox(height:11),
            Text('Folder: '+_val(run!['cwd']),
              style:const TextStyle(color:_muted)),
            Text('Native session: '+_val(run!['session_id'],'New'),
              style:const TextStyle(color:_muted)),
            if(run!['error']!=null)Text(_val(run!['error']),
              style:const TextStyle(color:Colors.red)),
            if(['waiting_for_approval','queued'].contains(run!['status']))...[
              const SizedBox(height:12),
              OutlinedButton.icon(
                onPressed:()=>_supervise(acknowledge:false),
                icon:const Icon(Icons.cancel_outlined),
                label:const Text('Cancel pending work')),
            ],
            if(run!['status']=='needs_recovery')...[
              const SizedBox(height:12),
              OutlinedButton.icon(
                onPressed:()=>_supervise(acknowledge:true),
                icon:const Icon(Icons.warning_amber_outlined),
                label:const Text('Review interrupted run (no replay)')),
            ],
          ])),
        const SizedBox(height:20),
        const Text('LIVE EVENT HISTORY',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:10),
        if(events.isEmpty)const _Blank('Waiting for live updates',
          'Worker events will appear after an approved action starts.')
        else for(final ev in events)...[
          _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              Text(_name(_val(ev['kind'])),
                style:const TextStyle(fontWeight:FontWeight.w800)),
              const SizedBox(height:6),
              SelectableText(_val(ev['text'])),
            ])),
          const SizedBox(height:8),
        ],
        if(run!['result']!=null)...[
          const SizedBox(height:18),
          const Text('CONFIRMED RESULT',style:TextStyle(
            color:OTheme.violet,fontWeight:FontWeight.w800)),
          const SizedBox(height:10),
          _Panel(child:SelectableText(
            const JsonEncoder.withIndent('  ').convert(run!['result']),
            style:const TextStyle(fontSize:12,fontFamily:'monospace'))),
        ],
      ],
    ])));
}

class _Inbox extends StatelessWidget{
  const _Inbox({required this.c});
  final NativePilotController c;
  Future<void> _review(BuildContext ctx,Map<String,dynamic> item,bool approve) async{
    final details='Worker: '+_val(item['device_id'])+
      '\nRun: '+_val(item['run_id'])+
      '\nKind: '+_val(item['kind'])+
      '\nExpires: '+_date(item['expires_at'])+
      '\nFingerprint: '+_val(item['action_hash'])+
      '\n\nExact request:\n'+_val(item['description']);
    final ok=await showCupertinoDialog<bool>(context:ctx,builder:(d)=>CupertinoAlertDialog(
      title:Text(approve?'Approve exact request?':'Deny this request?'),
      content:SingleChildScrollView(child:SelectableText(details)),actions:[
        CupertinoDialogAction(onPressed:()=>Navigator.pop(d,false),
          child:const Text('Cancel')),
        CupertinoDialogAction(isDefaultAction:true,onPressed:()=>Navigator.pop(d,true),
          child:Text(approve?'Approve once':'Deny')),
      ]));
    if(ok!=true||!ctx.mounted)return;
    try{await c.decide(item,approve);
      if(ctx.mounted)_toast(ctx,approve?'Approved once.':'Denied.');
    }catch(e){if(ctx.mounted)_toast(ctx,pilotFriendlyError(e));}
  }
  @override Widget build(BuildContext context)=>RefreshIndicator(
    onRefresh:c.refresh,child:ListView(padding:const EdgeInsets.all(18),children:[
      const _Heading('Approval inbox',
        'Only you can decide what your worker executes.'),
      if(c.approvals.isEmpty)const _Blank('All caught up',
        'No server-verified action requests are waiting.')
      else for(final p in c.approvals)...[
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Row(children:[
              Expanded(child:Text(p['kind']=='tool'
                ?'Tool permission':'Agent run approval',
                style:const TextStyle(fontWeight:FontWeight.w800))),
              _pill(p['actionable']==true?'pending':'unavailable'),
            ]),
            const SizedBox(height:12),
            SelectableText(_val(p['description']),
              style:const TextStyle(height:1.5)),
            const SizedBox(height:8),
            Text('Worker: '+_val(p['device_id'])+
              '\nExpires: '+_date(p['expires_at']),
              style:const TextStyle(color:_muted,fontSize:12)),
            if(p['actionable']!=true)Text(
              _val(p['unavailableReason'],'Worker unavailable'),
              style:const TextStyle(color:Colors.red)),
            const SizedBox(height:12),
            Row(children:[
              Expanded(child:OutlinedButton(onPressed:()=>_review(context,p,false),
                child:const Text('Deny'))),
              const SizedBox(width:8),
              Expanded(child:FilledButton(
                onPressed:p['actionable']==true
                  ?()=>_review(context,p,true):null,
                child:const Text('Review & approve'))),
            ]),
          ])),
        const SizedBox(height:10),
      ],
    ]));
}
class _Devices extends StatelessWidget{
  const _Devices({required this.c});
  final NativePilotController c;
  Future<void> _revoke(BuildContext context,Map<String,dynamic> device) async {
    final confirmed = await showCupertinoDialog<bool>(context:context,builder:(dialog)=>
      CupertinoAlertDialog(title:const Text('Revoke this trusted worker?'),
        content:SelectableText('Device: '+_val(device['name'])+
          '\nID: '+_val(device['id'])+
          '\n\nThis permanently removes its authorization. '
          'Reconnect using a fresh owner-approved enrollment.'),
        actions:[
          CupertinoDialogAction(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          CupertinoDialogAction(isDestructiveAction:true,onPressed:()=>Navigator.pop(dialog,true),
            child:const Text('Revoke device')),
        ]));
    if(confirmed!=true||!context.mounted)return;
    try{await c.revokeDevice(device);
      if(context.mounted)_toast(context,'Trusted worker revoked.');
    }catch(e){if(context.mounted)_toast(context,pilotFriendlyError(e));}
  }
  @override Widget build(BuildContext context)=>RefreshIndicator(
    onRefresh:c.refresh,child:ListView(padding:const EdgeInsets.all(18),children:[
      const _Heading('Trusted devices',
        'Signed workers, verified heartbeats and enrolled folders.'),
      if(c.me['role']=='owner') _NativeEnrollPanel(c:c),
      if(c.me['role']=='owner') const SizedBox(height:12),
      if(c.devices.isEmpty)const _Blank('No enrolled workers',
        'Run START-O-AGENT.cmd on your laptop and approve '
        'its fingerprint in your signed-in account.',
        icon:Icons.computer_outlined)
      else for(final d in c.devices)...[
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Row(children:[
              const Icon(Icons.laptop_mac,color:OTheme.violet),
              const SizedBox(width:9),
              Expanded(child:Text(_val(d['name']),
                style:const TextStyle(fontWeight:FontWeight.w800))),
              _pill(pilotDeviceOnline(d)?'online':'offline',
                online:pilotDeviceOnline(d)),
            ]),
            const SizedBox(height:12),
            Text('Project: '+_val(d['workspace_root']),
              style:const TextStyle(color:_muted)),
            Text('Last heartbeat: '+_date(d['last_seen_at']),
              style:const TextStyle(color:_muted,fontSize:12)),
            const SizedBox(height:7),
            Text(_codexStatus(d['codex_session_health']),
              style:const TextStyle(color:_muted,fontSize:12,height:1.4)),
            Text('Codex checked: '+_date(d['codex_last_checked_at']),
              style:const TextStyle(color:_muted,fontSize:11)),
            const SizedBox(height:9),
            Text(((d['capabilities'] as List?)??[]).map((x)=>
              pilotCapabilityLabel(x.toString())).join(' · '),
              style:const TextStyle(color:OTheme.violet,fontSize:12)),
            if(c.me['role']=='owner' && d['revoked_at']==null)...[
              const SizedBox(height:10),
              OutlinedButton.icon(
                onPressed:()=>_revoke(context,d),
                icon:const Icon(Icons.gpp_bad_outlined),
                label:const Text('Review device revocation')),
            ],
          ])),
        const SizedBox(height:10),
      ],
    ]));
}
class _NativeEnrollPanel extends StatefulWidget {
  const _NativeEnrollPanel({required this.c});
  final NativePilotController c;
  @override State<_NativeEnrollPanel> createState() => _NativeEnrollPanelState();
}
class _NativeEnrollPanelState extends State<_NativeEnrollPanel> {
  final field=TextEditingController();
  bool loading=false;
  @override void dispose() { field.dispose(); super.dispose(); }
  Future<void> _inspect() async {
    if(loading||field.text.trim().isEmpty)return;
    setState(()=>loading=true);
    try {
      final inspected=await widget.c.inspectPairing(field.text);
      if(!mounted)return;
      final fingerprint=_val(inspected['fingerprint']);
      if(inspected['approved']==true){
        _toast(context,'This worker has already been enrolled.');
        return;
      }
      final accepted=await showCupertinoDialog<bool>(context:context,builder:(d)=>
        CupertinoAlertDialog(
          title:const Text('Verify laptop identity'),
          content:SingleChildScrollView(child:Column(
            mainAxisSize:MainAxisSize.min,
            crossAxisAlignment:CrossAxisAlignment.start,
            children:[
              const Text('Do not approve unless this fingerprint matches '
                'the one visible on your OWN computer.'),
              const SizedBox(height:14),
              Text('Device: '+_val(inspected['name']),style:const TextStyle(
                fontWeight:FontWeight.w800)),
              const SizedBox(height:10),
              SelectableText(fingerprint,style:const TextStyle(
                fontSize:16,fontWeight:FontWeight.w800)),
              const SizedBox(height:10),
              Text('Expires: '+_date(inspected['expiresAt'])),
            ])),
          actions:[
            CupertinoDialogAction(onPressed:()=>Navigator.pop(d,false),
              child:const Text('Not my device')),
            CupertinoDialogAction(isDefaultAction:true,onPressed:()=>Navigator.pop(d,true),
              child:const Text('Fingerprint matches · Approve')),
          ],
        ));
      if(accepted!=true||!mounted)return;
      await widget.c.approvePairing(field.text,fingerprint);
      field.clear();
      if(mounted)_toast(context,'Trusted worker enrollment approved.');
    }catch(e){
      if(mounted)_toast(context,pilotFriendlyError(e));
    }finally{if(mounted)setState(()=>loading=false);}
  }
  @override Widget build(BuildContext context)=>_Panel(
    child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      const Text('ENROLL A NEW LAPTOP',
        style:TextStyle(fontWeight:FontWeight.w800,color:OTheme.violet)),
      const SizedBox(height:9),
      const Text('On your computer, open START-O-AGENT.cmd. '
        'Paste its private pairing link here. Review the exact '
        'device fingerprint before approving—without a website.',
        style:TextStyle(color:_muted,height:1.5,fontSize:12)),
      const SizedBox(height:12),
      TextField(controller:field,obscureText:true,
        enableSuggestions:false,autocorrect:false,
        decoration:const InputDecoration(
          border:OutlineInputBorder(),
          labelText:'Private one-time pairing link',
          prefixIcon:Icon(Icons.link))),
      const SizedBox(height:12),
      FilledButton.icon(onPressed:loading?null:_inspect,
        icon:const Icon(Icons.verified_user_outlined),
        label:Text(loading?'Checking device…':'Inspect & approve laptop')),
    ]));
}

class _More extends StatelessWidget {
  const _More({required this.c, required this.legacy,
    required this.agents, required this.devices});
  final NativePilotController c;
  final VoidCallback legacy, agents, devices;

  Future<void> _signOut(BuildContext context) async {
    final ok = await showCupertinoDialog<bool>(
      context: context, builder: (d) => CupertinoAlertDialog(
        title: const Text('Sign out of this phone?'),
        content: const Text(
          'Only the encrypted phone session will be cleared. '
          'Your laptop and server data remain intact.'),
        actions: [
          CupertinoDialogAction(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel')),
          CupertinoDialogAction(
            isDestructiveAction: true,
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Sign out')),
        ]));
    if (ok == true) await c.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final agentsList = buildAgentDirectory(
      signedIn: c.connected, devices: c.devices,
      codexSessions: c.sessions, sdkSessions: c.providerSessions);
    final eligible = agentsList.where((e) => e.hasVerifiedSession).length;
    return ColoredBox(color: const Color(0xFFF5F7F9),
      child: ListView(padding: const EdgeInsets.only(bottom: 26),
        children: [
          const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 0),
            child: _Heading('Settings & connections',
              'Your account, authorized providers and private workspace.')),
          CupertinoListSection.insetGrouped(
            decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line)),
            backgroundColor: const Color(0xFFF5F7F9),
            header: const Text('YOUR PRIVATE ACCOUNT'),
            children: [
              CupertinoListTile(
                backgroundColor: Colors.white,
                leading: const Icon(CupertinoIcons.lock, color: OTheme.violet),
                title: const Text('Private O-AGENT server'),
                subtitle: Text(c.origin?.host ?? 'Not connected'),
                trailing: const Icon(CupertinoIcons.checkmark_shield,
                  color: Color(0xFF287D65))),
              CupertinoListTile(
                backgroundColor: Colors.white,
                leading: const Icon(CupertinoIcons.person_crop_circle,
                  color: OTheme.violet),
                title: const Text('Signed-in workspace role'),
                subtitle: Text(_val(c.me['role'], 'Not authorized'))),
              CupertinoListTile(
                backgroundColor: Colors.white,
                leading: const Icon(CupertinoIcons.refresh,
                  color: OTheme.violet),
                title: const Text('Refresh private connection'),
                subtitle: const Text('Read real server state and agent health'),
                onTap: c.syncing ? null : c.refresh,
                trailing: const Icon(CupertinoIcons.chevron_forward)),
            ],
          ),
          CupertinoListSection.insetGrouped(
            decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line)),
            backgroundColor: const Color(0xFFF5F7F9),
            header: const Text('AGENTS & PROJECT CONNECTIONS'),
            children: [
              CupertinoListTile(
                backgroundColor: Colors.white,
                leading: const Icon(CupertinoIcons.square_grid_2x2,
                  color: OTheme.violet),
                title: const Text('AI agent directory'),
                subtitle: Text('$eligible adapter types with '
                  'a verified resume-eligible session'),
                trailing: const Icon(CupertinoIcons.chevron_forward),
                onTap: agents),
              CupertinoListTile(
                backgroundColor: Colors.white,
                leading: const Icon(CupertinoIcons.folder,
                  color: OTheme.violet),
                title: const Text('Remote projects and live desktop'),
                subtitle: const Text('Live screen, GitHub, Cursor, VS Code & projects'),
                trailing: const Icon(CupertinoIcons.chevron_forward),
                onTap: legacy),
              CupertinoListTile(
                backgroundColor: Colors.white,
                leading: const Icon(CupertinoIcons.device_laptop,
                  color: OTheme.violet),
                title: const Text('Trusted computers'),
                subtitle: Text(c.onlineDevices.toString() +
                  ' online · manage pairing and revocation'),
                trailing: const Icon(CupertinoIcons.chevron_forward),
                onTap: devices),
            ],
          ),
          CupertinoListSection.insetGrouped(
            decoration: BoxDecoration(color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _line)),
            backgroundColor: const Color(0xFFF5F7F9),
            header: const Text('SECURITY'),
            children: [
              CupertinoListTile(
                backgroundColor: Colors.white,
                leading: const Icon(CupertinoIcons.square_arrow_right,
                  color: Color(0xFFB3474E)),
                title: const Text('Sign out of this phone'),
                subtitle: const Text('Clear encrypted mobile session only'),
                trailing: const Icon(CupertinoIcons.chevron_forward),
                onTap: () => _signOut(context)),
            ],
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            child: Text(
              'Provider authorizations remain separate. This release does '
              'not import ChatGPT or Claude website conversations, or '
              'allow arbitrary VS Code window control. In-app provider '
              'credential setup is still an outstanding product milestone.',
              style: TextStyle(fontSize: 12, height: 1.5,
                color: Color(0xFF6A7983))),
          ),
        ]));
  }
}

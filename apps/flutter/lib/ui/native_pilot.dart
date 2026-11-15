import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../core/pilot_native.dart';
import '../theme.dart';
import 'studio.dart';

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
  void _legacy()=>Navigator.of(context).push(MaterialPageRoute<void>(
    builder:(_)=>StudioShell(controller:widget.legacy)));
  @override void dispose(){
    c.removeListener(_changed);endpoint.dispose();
    if(widget.pilot==null)c.dispose();
    super.dispose();
  }
  Future<void> _login() async{
    await c.signIn(endpoint.text, rememberDevice: rememberDevice);
    if(mounted&&c.error!=null)_toast(context,c.error!);
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
          const Text('YOUR AI WORK. ON YOUR PHONE.',
            style:TextStyle(color:OTheme.violet,fontWeight:FontWeight.w800,
              fontSize:12,letterSpacing:0.7)),
          const SizedBox(height:12),
          const Text('Stay in control.\nWherever you are.',
            style:TextStyle(fontSize:34,fontWeight:FontWeight.w900,
              color:_ink,height:1.14)),
          const SizedBox(height:16),
          const Text('Connect real laptops, manage supported coding sessions, '
            'submit prompts and approve exact actions—all inside O-AGENT.',
            style:TextStyle(height:1.5,color:_muted,fontSize:15)),
          const SizedBox(height:26),
          _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
            children:[
              const Text('YOUR PRIVATE CONTROL PLANE',
                style:TextStyle(color:OTheme.violet,fontSize:12,
                  fontWeight:FontWeight.w800)),
              const SizedBox(height:14),
              TextField(controller:endpoint,keyboardType:TextInputType.url,
                autocorrect:false,decoration:const InputDecoration(
                  border:OutlineInputBorder(),prefixIcon:Icon(Icons.lock_outline),
                  labelText:'Private HTTPS address',
                  hintText:'https://your-device.ts.net:8443/')),
              const SizedBox(height:12),
              CheckboxListTile(
                value: rememberDevice,
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                title: const Text('Remember this phone'),
                subtitle: const Text('Save only the encrypted refresh session '
                  'in Android Keystore or iOS Keychain.'),
                onChanged: c.busy ? null
                  : (v) => setState(() => rememberDevice = v ?? false),
              ),
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
              const Text('Keycloak opens the secure system sign-in window '
                'for authentication, then returns you to this app. '
                'Your command center stays native.',
                style:TextStyle(fontSize:12,height:1.5,color:_muted)),
            ])),
          const SizedBox(height:22),
          const _Feature(Icons.laptop_mac,'Trusted computer',
            'Verified workers and enrolled project folders'),
          const _Feature(Icons.forum_outlined,'Real agent activity',
            'Continue supported SDK sessions with prompts'),
          const _Feature(Icons.shield_outlined,'Exact approvals',
            'Review commands before a worker executes them'),
          const SizedBox(height:18),
          OutlinedButton.icon(onPressed:_legacy,
            icon:const Icon(Icons.layers_outlined),
            label:const Text('Earlier native project workspace')),
          const SizedBox(height:8),
          const Text('The previous native features remain accessible. '
            'They use a separate legacy connection.',
            style:TextStyle(color:_muted,fontSize:12,height:1.4)),
        ]),
      ))));
    return Scaffold(
      appBar:AppBar(title:const Row(children:[
        CircleAvatar(radius:15,backgroundColor:_ink,
          child:Text('O',style:TextStyle(color:Colors.white,
            fontWeight:FontWeight.w900))),
        SizedBox(width:10),Text('O-AGENT',
          style:TextStyle(fontWeight:FontWeight.w800)),
      ]),actions:[
        const Icon(Icons.shield_outlined,color:OTheme.violet,size:17),
        const SizedBox(width:4),
        const Text('PRIVATE',style:TextStyle(color:OTheme.violet,
          fontSize:10,fontWeight:FontWeight.w800)),
        IconButton(onPressed:c.syncing?null:c.refresh,
          tooltip:'Refresh real server state',icon:const Icon(Icons.refresh)),
      ]),
      body:SafeArea(child:Column(children:[
        if(c.error!=null)MaterialBanner(
          content:Text(c.error!,maxLines:3),
          actions:[TextButton(onPressed:c.refresh,child:const Text('RETRY'))]),
        Expanded(child:IndexedStack(index:tab,children:[
          _Home(c:c,navigate:(i)=>setState(()=>tab=i)),
          _Work(c:c,navigate:(i)=>setState(()=>tab=i)),
          _Inbox(c:c),
          _Devices(c:c),
          _More(c:c,legacy:_legacy),
        ])),
      ])),
      bottomNavigationBar:NavigationBar(selectedIndex:tab,
        onDestinationSelected:(i)=>setState(()=>tab=i),
        labelBehavior:NavigationDestinationLabelBehavior.alwaysShow,
        destinations:[
          const NavigationDestination(icon:Icon(Icons.home_outlined),label:'Home'),
          const NavigationDestination(icon:Icon(Icons.work_outline),label:'Work'),
          NavigationDestination(icon:Badge(
              isLabelVisible:c.approvals.isNotEmpty,
              label:Text(c.approvals.length.toString()),
              child:const Icon(Icons.approval_outlined)),label:'Inbox'),
          const NavigationDestination(icon:Icon(Icons.devices_outlined),label:'Devices'),
          const NavigationDestination(icon:Icon(Icons.settings_outlined),label:'More'),
        ]),
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
class _Number extends StatelessWidget{
  const _Number(this.name,this.value,this.icon);
  final String name,value;final IconData icon;
  @override Widget build(BuildContext context)=>Expanded(child:_Panel(
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Icon(icon,color:OTheme.violet,size:20),
      const SizedBox(height:10),
      Text(value,style:const TextStyle(fontSize:27,fontWeight:FontWeight.w800)),
      Text(name,style:const TextStyle(color:_muted,fontSize:11)),
    ])));
}
class _Home extends StatelessWidget{
  const _Home({required this.c,required this.navigate});
  final NativePilotController c;final ValueChanged<int> navigate;
  @override Widget build(BuildContext context)=>RefreshIndicator(
    onRefresh:c.refresh,child:ListView(padding:const EdgeInsets.all(18),children:[
      const _Heading('Mission control','Real work from your verified control plane.'),
      _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        const Text('SECURE WORKSPACE',style:TextStyle(color:OTheme.violet,
          fontSize:12,fontWeight:FontWeight.w800)),
        const SizedBox(height:8),
        Text(c.origin?.host??'',style:const TextStyle(
          fontSize:17,fontWeight:FontWeight.w800)),
        const SizedBox(height:5),
        Text('Signed in · '+_val(c.me['role']),
          style:const TextStyle(color:_muted)),
      ])),
      const SizedBox(height:12),Row(children:[
        _Number('Online workers',c.onlineDevices.toString(),Icons.laptop_mac),
        const SizedBox(width:10),
        _Number('Active runs',c.activeRuns.toString(),Icons.bolt),
      ]),
      const SizedBox(height:10),Row(children:[
        _Number('Approvals',c.approvals.length.toString(),
          Icons.verified_user_outlined),
        const SizedBox(width:10),
        _Number('Saved Codex',c.sessions.length.toString(),Icons.forum_outlined),
      ]),
      const SizedBox(height:16),
      FilledButton.icon(onPressed:()=>navigate(1),
        icon:const Icon(Icons.play_arrow),
        label:const Text('Continue work on my laptop')),
      const SizedBox(height:8),
      OutlinedButton.icon(onPressed:()=>navigate(2),
        icon:const Icon(Icons.approval_outlined),
        label:Text('Review approvals ('+c.approvals.length.toString()+')')),
      const SizedBox(height:22),
      const Text('RECENT AGENT ACTIVITY',style:TextStyle(
        color:OTheme.violet,fontWeight:FontWeight.w800)),
      const SizedBox(height:12),
      if(c.runs.isEmpty)const _Blank('No real runs yet',
        'Try a read-only workspace inventory. No demo activity is fabricated.')
      else for(final r in c.runs.take(5))...[
        _RunTile(c:c,run:r),const SizedBox(height:10)],
    ]));
}

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
    final details='Worker: '+_val(machine['name'])+
      '\nProvider: '+pilotCapabilityLabel(kind)+
      '\nMode: '+_name(mode)+
      '\nExact folder: '+(kind=='codex_cli_turn'
        ?_val(widget.c.sessions.where((x)=>x['sessionId']==savedSessionId &&
            x['deviceId']==machine['id']).firstOrNull?['cwd'])
        :_val(machine['workspace_root']))+
      '\nSaved session: '+_val(savedSessionId,'New if supported')+
      '\n\nPrompt:\n'+text+
      '\n\nThis REQUESTS approval; nothing executes automatically.';
    final confirmed=await showDialog<bool>(context:context,builder:(dialog)=>
      AlertDialog(title:const Text('Review your next turn'),
        content:SingleChildScrollView(child:SelectableText(details)),actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(dialog,true),
            child:const Text('Request approval')),
        ]));
    if(confirmed!=true||!mounted)return;
    setState(()=>sending=true);
    try{
      await widget.c.requestTurn(device:machine,kind:kind,mode:mode,
        prompt:text,sessionId:kind=='codex_cli_turn'
          ?savedSessionId:null);
      if(!mounted)return;
      prompt.clear();widget.navigate(2);
      _toast(context,'Supervised request created. Approve it separately.');
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
    final kind=available.contains(operation)?operation:
      (available.isNotEmpty?available.first:null);
    final savedForDevice=widget.c.sessions
      .where((x)=>x['deviceId']==selected?['id']).toList();
    final chosenSaved=savedForDevice.where(
      (x)=>x['sessionId']==savedSessionId).firstOrNull;
    return RefreshIndicator(onRefresh:widget.c.refresh,
      child:ListView(padding:const EdgeInsets.all(18),children:[
        const _Heading('Projects & agent runs',
          'Existing Codex threads on your PC, prompts and verified agent results.'),
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
        if(online.isEmpty)...[
          const _Blank('Your worker is offline',
            'Open CONNECT-O-AGENT-WORKER.cmd on the laptop and keep it running.',
            icon:Icons.laptop_chromebook),const SizedBox(height:20),
        ]else _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.stretch,
          children:[
            const Text('NEW SUPERVISED TURN',style:TextStyle(
              color:OTheme.violet,fontWeight:FontWeight.w800)),
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

class NativeSavedSessionDetail extends StatelessWidget {
  const NativeSavedSessionDetail({super.key,required this.saved,
    required this.canContinue,required this.onContinue});
  final Map<String,dynamic> saved;
  final bool canContinue;
  final VoidCallback onContinue;
  @override Widget build(BuildContext context){
    final messages=(saved['messages'] as List?)??[];
    return Scaffold(
      appBar:AppBar(title:const Text('Saved Codex conversation')),
      body:SafeArea(child:ListView(padding:const EdgeInsets.all(18),children:[
        _Heading(_val(saved['title']),
          'Real persisted CLI / VS Code conversation snapshot, not a live IDE takeover.'),
        _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
          Text('Worker: '+_val(saved['deviceName']),
            style:const TextStyle(fontWeight:FontWeight.w800)),
          const SizedBox(height:6),
          SelectableText('Folder: '+_val(saved['cwd']),
            style:const TextStyle(fontSize:12,color:_muted)),
          Text('Last activity: '+_date(saved['updatedAt']),
            style:const TextStyle(fontSize:12,color:_muted)),
          Text('Last synchronized: '+_date(saved['syncedAt']),
            style:const TextStyle(fontSize:12,color:_muted)),
        ])),
        const SizedBox(height:20),
        const Text('PERSISTED CONVERSATION',style:TextStyle(
          color:OTheme.violet,fontWeight:FontWeight.w800)),
        const SizedBox(height:10),
        if(messages.isEmpty)
          const _Blank('No readable text in the saved snapshot',
            'The Codex app-server returned metadata only for this thread. '
            'Recent text is shown only where the provider makes it available.')
        else for(final message in messages)...[
          _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(message is Map && message['role']=='user'
              ?'YOU':'CODEX',
              style:const TextStyle(color:OTheme.violet,
                fontWeight:FontWeight.w800,fontSize:12)),
            const SizedBox(height:7),
            SelectableText(message is Map
              ?_val(message['text']):'Unsupported message',
              style:const TextStyle(height:1.5)),
          ])),
          const SizedBox(height:10),
        ],
        const SizedBox(height:10),
        FilledButton.icon(
          onPressed:canContinue?(){
            onContinue();
            Navigator.pop(context);
          }:null,
          icon:const Icon(Icons.play_arrow),
          label:const Text('Select this thread to continue')),
        if(!canContinue)const Text(
          'This thread is readable, but Codex execution is disabled or '
          'the worker is offline. The worker must explicitly enable Codex turns.',
          style:TextStyle(color:_muted,fontSize:12,height:1.5)),
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
    final approved=await showDialog<bool>(context:context,builder:(dialog)=>
      AlertDialog(
        title:Text(acknowledge?'Acknowledge interrupted execution?'
          :'Cancel this queued request?'),
        content:Text(acknowledge
          ?'The worker may have made changes before its connection broke. '
            'This marks the interrupted run failed WITHOUT replaying it. '
            'Inspect your project before starting new work.'
          :'This cancels a run that has not started. It cannot undo a run '
            'that the worker has already executed.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Keep current state')),
          FilledButton(onPressed:()=>Navigator.pop(dialog,true),
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
    final ok=await showDialog<bool>(context:ctx,builder:(d)=>AlertDialog(
      title:Text(approve?'Approve exact request?':'Deny this request?'),
      content:SingleChildScrollView(child:SelectableText(details)),actions:[
        TextButton(onPressed:()=>Navigator.pop(d,false),
          child:const Text('Cancel')),
        FilledButton(onPressed:()=>Navigator.pop(d,true),
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
    final confirmed = await showDialog<bool>(context:context,builder:(dialog)=>
      AlertDialog(title:const Text('Revoke this trusted worker?'),
        content:SelectableText('Device: '+_val(device['name'])+
          '\nID: '+_val(device['id'])+
          '\n\nThis permanently removes its authorization. '
          'Reconnect using a fresh owner-approved enrollment.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(dialog,false),
            child:const Text('Cancel')),
          FilledButton(onPressed:()=>Navigator.pop(dialog,true),
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
        'Run CONNECT-O-AGENT-WORKER.cmd on your laptop and approve '
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
      final accepted=await showDialog<bool>(context:context,builder:(d)=>
        AlertDialog(
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
            TextButton(onPressed:()=>Navigator.pop(d,false),
              child:const Text('Not my device')),
            FilledButton(onPressed:()=>Navigator.pop(d,true),
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
      const Text('On your computer, open CONNECT-O-AGENT-WORKER.cmd. '
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

class _More extends StatelessWidget{
  const _More({required this.c,required this.legacy});
  final NativePilotController c;final VoidCallback legacy;
  @override Widget build(BuildContext context)=>ListView(
    padding:const EdgeInsets.all(18),children:[
      const _Heading('Accounts & connections',
        'Everything stays inside this native control app.'),
      _Panel(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
        children:[
          const Text('PRIVATE BACKEND',style:TextStyle(
            color:OTheme.violet,fontWeight:FontWeight.w800)),
          const SizedBox(height:8),
          SelectableText(c.origin?.toString()??'Not connected'),
          const SizedBox(height:8),
          Text('Role: '+_val(c.me['role']),
            style:const TextStyle(color:_muted)),
          const SizedBox(height:15),
          OutlinedButton.icon(onPressed:c.refresh,
            icon:const Icon(Icons.sync),label:const Text('Verify connection')),
          const SizedBox(height:8),
          OutlinedButton.icon(onPressed:legacy,
            icon:const Icon(Icons.layers_outlined),
            label:const Text('Earlier native projects and Codex')),
          const SizedBox(height:8),
          TextButton.icon(onPressed:()async{
            final ok=await showDialog<bool>(context:context,builder:(d)=>
              AlertDialog(title:const Text('Sign out of this phone?'),
                content:const Text('Only the encrypted phone session will '
                  'be cleared. Your laptop and server data remain intact.'),
                actions:[
                  TextButton(onPressed:()=>Navigator.pop(d,false),
                    child:const Text('Cancel')),
                  FilledButton(onPressed:()=>Navigator.pop(d,true),
                    child:const Text('Sign out')),
                ]));
            if(ok==true)await c.signOut();
          },icon:const Icon(Icons.logout),label:const Text('Sign out')),
        ])),
      const SizedBox(height:16),
      const _Panel(child:Text('Only supported and authenticated provider '
        'adapters show as runnable. Takeover of arbitrary ChatGPT.com '
        'browser tabs, screen streaming and unimplemented IDE sessions '
        'is not advertised as working.',
        style:TextStyle(color:_muted,height:1.5))),
    ]);
}

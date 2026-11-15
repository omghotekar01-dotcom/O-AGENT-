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
  @override Widget build(BuildContext context)=>Container(width:double.infinity,
    padding:const EdgeInsets.all(17),decoration:BoxDecoration(
      color:Colors.white,border:Border.all(color:_line),
      borderRadius:BorderRadius.circular(17)),child:child);
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
        _Number('Run history',c.runs.length.toString(),Icons.history),
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
  final prompt=TextEditingController(),session=TextEditingController();
  String? machineId,operation;
  String mode='read_only';bool sending=false;
  @override void dispose(){prompt.dispose();session.dispose();super.dispose();}
  Future<void> _submit(Map<String,dynamic> machine,String kind)async{
    if(sending)return;
    final text=kind=='workspace_inventory'
      ?'Inspect enrolled workspace files':prompt.text.trim();
    if(text.isEmpty){_toast(context,'Enter a prompt first.');return;}
    final details='Worker: '+_val(machine['name'])+
      '\nProvider: '+pilotCapabilityLabel(kind)+
      '\nMode: '+_name(mode)+
      '\nExact folder: '+_val(machine['workspace_root'])+
      '\nSaved session: '+_val(session.text.trim(),'New if supported')+
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
        prompt:text,sessionId:session.text.trim().isEmpty
          ?null:session.text.trim());
      if(!mounted)return;
      prompt.clear();session.clear();widget.navigate(2);
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
    return RefreshIndicator(onRefresh:widget.c.refresh,
      child:ListView(padding:const EdgeInsets.all(18),children:[
        const _Heading('Projects & agent runs',
          'Select your laptop, prompt a supported agent, and view live results.'),
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
              onChanged:(v)=>setState((){machineId=v;operation=null;})),
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
              onChanged:(v)=>setState(()=>operation=v))
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
              TextField(controller:session,decoration:const InputDecoration(
                labelText:'Existing verified Codex session ID',
                border:OutlineInputBorder())),
            ],
            const SizedBox(height:12),
            TextField(controller:prompt,minLines:3,maxLines:5,maxLength:4000,
              decoration:InputDecoration(border:const OutlineInputBorder(),
                labelText:'Your next prompt',
                hintText:kind=='workspace_inventory'
                  ?'Read-only inventory does not require a prompt'
                  :'Continue the task; explain what changed.')),
            FilledButton.icon(
              onPressed:sending||kind==null?null:()=>_submit(selected!,kind),
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

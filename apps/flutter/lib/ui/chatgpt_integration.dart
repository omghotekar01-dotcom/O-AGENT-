import 'dart:convert';
import 'dart:typed_data';
import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/chatgpt_history.dart';
import '../core/controller.dart';
import '../core/pilot_native.dart';
import 'remote_fullscreen.dart';
import 'native_openai_api_chat.dart';

const _ink=Color(0xFF1A2940),_muted=Color(0xFF6A7B8C);
const _blue=Color(0xFF4862D9),_canvas=Color(0xFFF6F8FC);

/// Explicit user export only. Does not synchronize or take over ChatGPT.
List<ChatGptConversation> decodeChatGptFile(Uint8List bytes) {
  if(bytes.length>90*1024*1024)throw const FormatException('Export ZIP too large');
  var data=bytes;
  if(bytes.length>4&&bytes[0]==0x50&&bytes[1]==0x4B){
    final archive=ZipDecoder().decodeBytes(bytes,verify:true);
    final files=archive.files.where((f)=>
      f.isFile&&f.name.split('/').last=='conversations.json').toList();
    if(files.isEmpty)throw const FormatException('No conversations.json in export');
    final f=files.first;
    if(f.size>80*1024*1024)throw const FormatException('Too much export data');
    final extracted=f.readBytes();
    if(extracted==null)throw const FormatException('Unreadable export');
    data=Uint8List.fromList(extracted);
  }
  if(data.length>80*1024*1024)throw const FormatException('Too much conversation data');
  return parseChatGptExport(utf8.decode(data));
}

/// Three truthful modes: live PC, local read-only snapshot, and authorized
/// account/MCP connection. ChatGPT consumer password/cookies NEVER requested.
class ChatGptIntegrationScreen extends StatefulWidget {
  const ChatGptIntegrationScreen({
    super.key,required this.computer,required this.pilot});
  final ControlController computer;
  final NativePilotController pilot;
  @override
  State<ChatGptIntegrationScreen> createState()=>_ChatGptIntegrationState();
}
class _ChatGptIntegrationState extends State<ChatGptIntegrationScreen> {
  final _url=TextEditingController();
  final _token=TextEditingController();
  final _search=TextEditingController();
  int page=0;
  bool loading=false,connecting=false,remember=true;
  String? error;
  List<ChatGptConversation> chats=const [];
  @override void initState(){
    super.initState();
    widget.computer.addListener(_changed);
    Future.microtask(()=>widget.computer.reconnectSavedSession());
  }
  void _changed(){if(mounted)setState((){});}
  @override void dispose(){
    widget.computer.removeListener(_changed);
    _url.dispose();_token.dispose();_search.dispose();super.dispose();
  }

  Future<void> _import()async{
    if(loading)return;
    setState((){loading=true;error=null;});
    try{
      final file=await FilePicker.pickFile(type:FileType.custom,
        allowedExtensions:['zip','json']);
      if(file==null)return;
      final size=file.lengthSync() ?? await file.length();
      if(size==null||size<2||size>60*1024*1024){
        throw const FormatException('Export is empty or exceeds 60 MB');
      }
      final data=await file.readAsBytes();
      final list=await compute(decodeChatGptFile,Uint8List.fromList(data));
      if(mounted)setState((){chats=list;page=1;});
    }catch(_){
      if(mounted)setState(()=>error='Cannot read this export. Select the '
        'official ChatGPT data ZIP or conversations.json (under 90 MB).');
    }finally{if(mounted)setState(()=>loading=false);}
  }
  Future<void> _connect()async{
    if(connecting)return;
    final u=Uri.tryParse(_url.text.trim());
    if(u==null||u.scheme!='https'||u.host.isEmpty||u.userInfo.isNotEmpty||
        u.hasQuery||u.hasFragment||(u.path.isNotEmpty&&u.path!='/')){
      setState(()=>error='Enter your private HTTPS remote gateway origin.');
      return;
    }
    if(_token.text.trim().length<24){
      setState(()=>error='Enter the separately authorized Windows gateway '
        'owner token. Never enter a ChatGPT password here.');
      return;
    }
    setState((){connecting=true;error=null;});
    final ok=await widget.computer.connect(u.origin,_token.text.trim(),
      remember:remember);
    if(!mounted)return;
    setState((){
      connecting=false;
      if(ok){_token.clear();page=0;}
      else{error='Could not authenticate the old screen gateway. '
        'Check its HTTPS Tailscale route and local configuration.';}
    });
  }
  void _live(){
    if(!widget.computer.connected){
      setState(()=>page=2);return;
    }
    Navigator.push(context,MaterialPageRoute<void>(
      builder:(_)=>RemoteFullscreenScreen(controller:widget.computer)));
  }
  Future<void> _mcp()async{
    final value=widget.pilot.origin?.resolve('/mcp').toString();
    await showDialog<void>(context:context,builder:(ctx)=>AlertDialog(
      title:const Text('ChatGPT ⇄ O-AGENT MCP'),
      content:SingleChildScrollView(child:Column(
        crossAxisAlignment:CrossAxisAlignment.start,
        mainAxisSize:MainAxisSize.min,children:[
          const Text('For eligible ChatGPT workspaces, O-AGENT exposes '
            'scoped run-status and approval tools. ChatGPT needs a '
            'secure tunnel for your private server and separate '
            'authorization. This does NOT expose all ChatGPT chats.',
            style:TextStyle(height:1.55)),
          const SizedBox(height:12),
          SelectableText(value??'First sign in to your private O-AGENT server.'),
        ])),
      actions:[
        if(value!=null)TextButton(
          onPressed:(){Clipboard.setData(ClipboardData(text:value));
            Navigator.pop(ctx);},child:const Text('Copy endpoint')),
        TextButton(onPressed:()=>Navigator.pop(ctx),
          child:const Text('Close')),
      ]));
  }

  Widget _card(Widget child,{Color color=Colors.white})=>Container(
    margin:const EdgeInsets.only(bottom:12),padding:const EdgeInsets.all(18),
    decoration:BoxDecoration(color:color,borderRadius:BorderRadius.circular(24),
      border:Border.all(color:const Color(0xFFE8ECF1)),
      boxShadow:const [BoxShadow(
        color:Color(0x080A263B),blurRadius:20,offset:Offset(0,5))]),
    child:child);
  Widget _tile(String name,String description,IconData glyph,
      VoidCallback action,{String? status})=>_card(
    InkWell(onTap:action,borderRadius:BorderRadius.circular(16),
      child:Row(children:[
        Container(width:46,height:46,alignment:Alignment.center,
          decoration:BoxDecoration(color:const Color(0xFFEDF0FC),
            borderRadius:BorderRadius.circular(15)),
          child:Icon(glyph,color:_blue,size:22)),
        const SizedBox(width:13),
        Expanded(child:Column(crossAxisAlignment:CrossAxisAlignment.start,
          children:[
            Text(name,style:const TextStyle(
              color:_ink,fontWeight:FontWeight.w800,fontSize:15)),
            const SizedBox(height:4),
            Text(description,style:const TextStyle(
              color:_muted,fontSize:12,height:1.4)),
            if(status!=null)Padding(padding:const EdgeInsets.only(top:5),
              child:Text(status,style:const TextStyle(
                color:_blue,fontSize:11,fontWeight:FontWeight.w800))),
          ])),
        const SizedBox(width:8),
        const Icon(LucideIcons.chevronRight,size:17,color:_muted),
      ])));
  Widget _hero()=>Container(
    padding:const EdgeInsets.all(22),
    decoration:BoxDecoration(
      gradient:const LinearGradient(
        colors:[Color(0xFF17263F),Color(0xFF3B498A),Color(0xFF626AC0)],
        begin:Alignment.topLeft,end:Alignment.bottomRight),
      borderRadius:BorderRadius.circular(28)),
    child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
      Row(children:[
        Container(width:46,height:46,alignment:Alignment.center,
          decoration:BoxDecoration(
            color:Colors.white.withValues(alpha:.16),
            borderRadius:BorderRadius.circular(15)),
          child:const Text('GPT',style:TextStyle(color:Colors.white,
            fontWeight:FontWeight.w900,fontSize:15))),
        const Spacer(),
        Container(padding:const EdgeInsets.symmetric(horizontal:12,vertical:7),
          decoration:BoxDecoration(
            color:Colors.white.withValues(alpha:.13),
            borderRadius:BorderRadius.circular(28)),
          child:Text(widget.computer.connected?'Remote PC connected':'Connect your PC',
            style:const TextStyle(color:Colors.white,fontSize:11,
              fontWeight:FontWeight.w700))),
      ]),
      const SizedBox(height:19),
      const Text('Your ChatGPT\nworkspace.',
        style:TextStyle(color:Colors.white,fontSize:29,
          fontWeight:FontWeight.w900,letterSpacing:-.7,height:1.12)),
      const SizedBox(height:10),
      const Text('Live computer control. Readable exported conversations. '
        'An optional API and MCP workspace.',
        style:TextStyle(color:Color(0xFFE9EDFF),height:1.5,fontSize:13)),
    ]));
  Widget _switcher()=>Container(
    padding:const EdgeInsets.all(5),
    margin:const EdgeInsets.symmetric(vertical:18),
    decoration:BoxDecoration(color:const Color(0xFFE9EDF2),
      borderRadius:BorderRadius.circular(17)),
    child:Row(children:[
      for(final i in [0,1,2])Expanded(child:GestureDetector(
        onTap:()=>setState(()=>page=i),
        child:AnimatedContainer(duration:const Duration(milliseconds:180),
          padding:const EdgeInsets.symmetric(vertical:11),
          decoration:BoxDecoration(
            borderRadius:BorderRadius.circular(13),
            color:page==i?Colors.white:Colors.transparent,
            boxShadow:page==i?const [BoxShadow(
              color:Color(0x140A2630),blurRadius:9)]:[]),
          child:Text(['Live','History','Connect'][i],
            textAlign:TextAlign.center,
            style:TextStyle(color:page==i?_ink:_muted,
              fontSize:13,fontWeight:FontWeight.w800))))),
    ]));

  Widget _livePanel()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,
    children:[
      _tile('Control my live ChatGPT tab',
        widget.computer.connected
          ?'View screen pixels, tap, type and send in the existing PC browser.'
          :'Authorize your private PC gateway once; then open its live screen.',
        LucideIcons.monitor,_live,
        status:widget.computer.connected?'LIVE SCREEN AVAILABLE':'SETUP REQUIRED'),
      _card(const Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
        Text('What this actually connects',
          style:TextStyle(color:_ink,fontSize:16,fontWeight:FontWeight.w800)),
        SizedBox(height:8),
        Text('Select the monitor containing ChatGPT on your own PC. '
          'You can see the same conversation and interact with it using '
          'trusted remote input. The stream is not an account API. '
          'Only the visible, consented PC screen is controlled.',
          style:TextStyle(color:_muted,height:1.55,fontSize:13)),
      ])),
    ]);

  Widget _historyPanel(){
    final search=_search.text.toLowerCase().trim();
    final filtered=chats.where((c)=>search.isEmpty||
      c.title.toLowerCase().contains(search)||
      c.messages.any((m)=>m.text.toLowerCase().contains(search))).toList();
    return Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
      _tile(loading?'Importing…':'Import my ChatGPT export',
        'Choose official data export ZIP or conversations.json. '
        'No server upload; snapshot is read-only.',
        LucideIcons.archive,loading?(){}:_import,
        status:chats.isEmpty?'LOCAL FILE':chats.length.toString()+' CONVERSATIONS'),
      if(chats.isEmpty)_card(const Text(
        'In ChatGPT go to Settings → Data controls → Export data. '
        'Download the official export and select it here. '
        'The list can then be browsed and searched locally, but it '
        'will not update until a new export is imported.',
        style:TextStyle(color:_muted,fontSize:13,height:1.6)))
      else...[
        TextField(controller:_search,onChanged:(_)=>setState((){}),
          decoration:InputDecoration(
            prefixIcon:const Icon(LucideIcons.search,size:19),
            hintText:'Search all imported chats',filled:true,
            fillColor:Colors.white,border:OutlineInputBorder(
              borderRadius:BorderRadius.circular(18),
              borderSide:BorderSide.none))),
        const SizedBox(height:12),
        for(final item in filtered.take(50))_tile(item.title,
          item.messages.length.toString()+' readable messages',
          LucideIcons.messageCircle,()=>_openChat(item)),
        if(filtered.length>50)const Text(
          'Showing 50 matches. Search to narrow the list.',
          style:TextStyle(color:_muted,fontSize:12)),
      ],
      const SizedBox(height:11),
      const Text('Imported conversations cannot be resumed through the '
        'OpenAI API. Use Live to interact with your existing ChatGPT tab.',
        style:TextStyle(color:_muted,fontSize:12,height:1.5)),
    ]);
  }
  void _openChat(ChatGptConversation c)=>Navigator.push(context,
    MaterialPageRoute<void>(builder:(_)=>_ChatHistoryDetail(
      record:c,onLive:_live)));

  Widget _connectPanel()=>Column(crossAxisAlignment:CrossAxisAlignment.stretch,
    children:[
      _card(Column(crossAxisAlignment:CrossAxisAlignment.stretch,children:[
        const Text('Private PC screen connection',
          style:TextStyle(color:_ink,fontWeight:FontWeight.w800,fontSize:16)),
        const SizedBox(height:6),
        Text(widget.computer.connected
          ?'Authorized gateway connected. No repeated pairing needed.'
          :'This is your previously configured Windows remote gateway, '
            'not a ChatGPT password or login token.',
          style:const TextStyle(color:_muted,fontSize:12,height:1.5)),
        if(!widget.computer.connected)...[
          const SizedBox(height:14),
          TextField(controller:_url,keyboardType:TextInputType.url,
            autocorrect:false,enableSuggestions:false,
            decoration:const InputDecoration(
              labelText:'Private HTTPS gateway URL')),
          const SizedBox(height:12),
          TextField(controller:_token,obscureText:true,
            enableSuggestions:false,autocorrect:false,
            decoration:const InputDecoration(
              labelText:'Existing gateway owner token')),
          SwitchListTile(contentPadding:EdgeInsets.zero,
            title:const Text('Remember this trusted phone'),
            value:remember,onChanged:(v)=>setState(()=>remember=v)),
          FilledButton.icon(onPressed:connecting?null:_connect,
            icon:const Icon(LucideIcons.shieldCheck),
            label:Text(connecting?'Authenticating…':'Connect PC')),
        ],
      ])),
      _tile('Start a real OpenAI API chat',
        'Enter your own API key securely on this phone. '
        'Send actual prompts; this is separate from ChatGPT website chats.',
        LucideIcons.keyRound,(){
          Navigator.push(context,MaterialPageRoute<void>(
            builder:(_)=>const NativeOpenAiApiChat()));
        }),
      _tile('ChatGPT plugin / MCP connection',
        'Authorized ChatGPT can call O-AGENT workspace tools. '
        'MCP does not share all conversations automatically.',
        LucideIcons.link,_mcp),
    ]);

  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:_canvas,
    appBar:AppBar(title:const Text('ChatGPT',style:TextStyle(
      fontSize:19,fontWeight:FontWeight.w800,color:_ink)),
      backgroundColor:_canvas,scrolledUnderElevation:0),
    body:SafeArea(child:ListView(
      key:const ValueKey('chatgpt-integration'),
      padding:const EdgeInsets.fromLTRB(18,12,18,30),
      children:[
        _hero(),_switcher(),
        if(error!=null)_card(Text(error!,style:const TextStyle(
          color:Color(0xFFAF414B),fontSize:13))),
        if(page==0)_livePanel(),
        if(page==1)_historyPanel(),
        if(page==2)_connectPanel(),
        const SizedBox(height:12),
        const Text('Your ChatGPT password, browser cookies and sessions '
          'are never requested by this app. Live desktop input requires '
          'visible local consent; imported data stays in phone memory.',
          style:TextStyle(color:_muted,fontSize:11,height:1.5)),
      ])));
}
class _ChatHistoryDetail extends StatelessWidget {
  const _ChatHistoryDetail({required this.record,required this.onLive});
  final ChatGptConversation record;
  final VoidCallback onLive;
  @override
  Widget build(BuildContext context)=>Scaffold(
    backgroundColor:_canvas,
    appBar:AppBar(title:Text(record.title,maxLines:1,
      overflow:TextOverflow.ellipsis)),
    body:ListView(padding:const EdgeInsets.all(18),children:[
      Container(padding:const EdgeInsets.all(15),
        decoration:BoxDecoration(color:const Color(0xFFE8EEFD),
          borderRadius:BorderRadius.circular(16)),
        child:const Text('Exported snapshot — READ ONLY. '
          'This is not a live ChatGPT session. Its messages cannot '
          'be replayed into the original chat using the OpenAI API.',
          style:TextStyle(color:_ink,height:1.5,fontSize:12))),
      const SizedBox(height:14),
      for(final message in record.messages)Align(
        alignment:message.role=='user'
          ?Alignment.centerRight:Alignment.centerLeft,
        child:Container(padding:const EdgeInsets.all(15),
          margin:const EdgeInsets.only(bottom:12),
          constraints:const BoxConstraints(maxWidth:650),
          decoration:BoxDecoration(
            color:message.role=='user'
              ?const Color(0xFFE9EEFD):Colors.white,
            borderRadius:BorderRadius.circular(18)),
          child:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
            Text(message.role=='user'?'YOU':'CHATGPT',
              style:const TextStyle(color:_blue,fontWeight:FontWeight.w800,
                fontSize:11)),
            const SizedBox(height:7),
            SelectableText(message.text,style:const TextStyle(
              fontSize:14,color:_ink,height:1.55)),
          ]))),
      const SizedBox(height:8),
      FilledButton.icon(onPressed:onLive,
        icon:const Icon(LucideIcons.monitor),
        label:const Text('View real ChatGPT on my PC')),
    ]));
}

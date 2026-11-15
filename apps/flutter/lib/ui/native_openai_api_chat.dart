import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../core/openai_responses.dart';

/// Secure phone-owned API conversation, explicitly distinct from ChatGPT.com.
class NativeOpenAiApiChat extends StatefulWidget {
  const NativeOpenAiApiChat({super.key});
  @override
  State<NativeOpenAiApiChat> createState()=>_NativeOpenAiApiChatState();
}
class _NativeOpenAiApiChatState extends State<NativeOpenAiApiChat> {
  static const secure = FlutterSecureStorage();
  static const keySlot = 'oagent.openai.personal.api.key.v1';
  static const modelSlot = 'oagent.openai.personal.model.v1';
  final keyField=TextEditingController();
  final modelField=TextEditingController(text:'gpt-4.1-mini');
  final input=TextEditingController();
  final messages= <({String role,String text})>[];
  String? savedKey,previousId,error;
  bool busy=false,loading=true,reveal=false;

  @override void initState(){super.initState();_restore();}
  Future<void> _restore()async {
    try {
      final key=await secure.read(key:keySlot);
      final model=await secure.read(key:modelSlot);
      if(!mounted)return;
      setState((){
        savedKey=key;
        if(model!=null&&model.trim().isNotEmpty)modelField.text=model;
        loading=false;
      });
    }catch(_){if(mounted)setState((){
      loading=false;error='Secure key storage is unavailable on this phone.';
    });}
  }
  @override void dispose(){
    keyField.dispose();modelField.dispose();input.dispose();super.dispose();
  }
  Future<void> _save()async {
    final key=keyField.text.trim();
    if(key.length<24){setState(()=>error='Enter a valid OpenAI API key.');return;}
    final model=modelField.text.trim();
    if(model.isEmpty||!RegExp(r'^[a-zA-Z0-9._-]+').hasMatch(model)){
      setState(()=>error='Enter a valid model ID.');return;
    }
    try {
      await secure.write(key:keySlot,value:key);
      await secure.write(key:modelSlot,value:model);
      if(mounted)setState((){
        savedKey=key;keyField.clear();error=null;
      });
    }catch(_){if(mounted)setState(()=>error='Could not save to the '
      'Android Keystore / iOS Keychain. No key was sent.');}
  }
  Future<void> _revoke()async {
    if(busy)return;
    final yes=await showDialog<bool>(context:context,builder:(ctx)=>
      AlertDialog(title:const Text('Remove OpenAI API key?'),
        content:const Text('Erase this phone’s encrypted key and '
          'reset the local conversation. Existing website chats are unchanged.'),
        actions:[TextButton(onPressed:()=>Navigator.pop(ctx,false),
          child:const Text('Cancel')),
          TextButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('Erase key'))]));
    if(yes!=true)return;
    try{await secure.delete(key:keySlot);
      if(!mounted)return;
      setState((){
        savedKey=null;previousId=null;messages.clear();error=null;
      });
    }catch(_){if(mounted)setState(()=>error='Could not clear the secure key.');}
  }
  Future<void> _send()async {
    if(busy||savedKey==null)return;
    final text=input.text.trim();
    if(text.isEmpty)return;
    setState((){
      busy=true;error=null;messages.add((role:'user',text:text));
    });
    input.clear();
    try {
      final result=await sendOpenAiResponse(key:savedKey!,
        model:modelField.text.trim(),prompt:text,previousResponseId:previousId);
      if(!mounted)return;
      setState((){
        previousId=result.id;
        messages.add((role:'assistant',text:result.text));
      });
      await secure.write(key:modelSlot,value:modelField.text.trim());
    }catch(e) {
      // Never print provider response headers or key-derived diagnostics.
      if(mounted)setState(()=>error=e is FormatException?e.message:
        'API request failed. Check network, key, model or usage limits.');
    }finally{if(mounted)setState(()=>busy=false);}
  }
  void _newChat(){
    if(!busy)setState((){
      messages.clear();previousId=null;error=null;
    });
  }

  @override Widget build(BuildContext context)=>Scaffold(
    backgroundColor:const Color(0xFFF6F8FC),
    appBar:AppBar(title:const Text('OpenAI API conversation'),
      backgroundColor:const Color(0xFFF6F8FC),
      actions:[if(savedKey!=null)IconButton(
        tooltip:'New API conversation',onPressed:_newChat,
        icon:const Icon(LucideIcons.plus))]),
    body:SafeArea(child:loading
      ?const Center(child:CircularProgressIndicator())
      :Column(children:[
        if(savedKey==null)Expanded(child:ListView(
          padding:const EdgeInsets.all(20),children:[
          const Text('Connect your own API key',style:TextStyle(
            fontSize:24,fontWeight:FontWeight.w800)),
          const SizedBox(height:8),
          const Text('This starts a NEW API-owned conversation. '
            'It does not connect to ChatGPT website history or Projects. '
            'API usage may cost money.'),
          const SizedBox(height:18),
          TextField(controller:keyField,obscureText:!reveal,
            autocorrect:false,enableSuggestions:false,
            decoration:InputDecoration(labelText:'OpenAI API key',
              suffixIcon:IconButton(onPressed:()=>setState(()=>reveal=!reveal),
                icon:Icon(reveal?LucideIcons.eyeOff:LucideIcons.eye)))),
          const SizedBox(height:14),
          TextField(controller:modelField,
            decoration:const InputDecoration(labelText:'API model ID')),
          const SizedBox(height:17),
          FilledButton(onPressed:_save,child:const Text('Save key securely')),
        ]))else ...[
          Padding(padding:const EdgeInsets.fromLTRB(16,8,16,8),
            child:Row(children:[
              const Expanded(child:Text('Key stored on this phone · '
                'API replies, not website sync',
                style:TextStyle(fontSize:12))),
              TextButton(onPressed:_revoke,child:const Text('Remove key')),
            ])),
          Expanded(child:ListView(
            padding:const EdgeInsets.all(16),children:[
            for(final m in messages)Align(
              alignment:m.role=='user'?Alignment.centerRight:Alignment.centerLeft,
              child:Container(margin:const EdgeInsets.only(bottom:12),
                padding:const EdgeInsets.all(14),
                constraints:const BoxConstraints(maxWidth:620),
                decoration:BoxDecoration(
                  color:m.role=='user'?const Color(0xFFE7ECFC):Colors.white,
                  borderRadius:BorderRadius.circular(16)),
                child:Text(m.text,style:const TextStyle(height:1.5)))),
            if(messages.isEmpty)const Padding(
              padding:EdgeInsets.symmetric(vertical:25),
              child:Text('No messages yet. Start a new API-owned chat. '
                'Your existing ChatGPT chats remain separate.',
                textAlign:TextAlign.center)),
            if(busy)const LinearProgressIndicator(),
          ])),
          Padding(padding:const EdgeInsets.all(12),child:Row(children:[
            Expanded(child:TextField(controller:input,
              minLines:1,maxLines:5,enabled:!busy,
              decoration:const InputDecoration(
                hintText:'Message the API model…',
                border:OutlineInputBorder()))),
            const SizedBox(width:10),
            IconButton(onPressed:busy?null:_send,
              tooltip:'Send real API request',
              icon:const Icon(LucideIcons.send)),
          ])),
        ],
        if(error!=null)Padding(padding:const EdgeInsets.all(12),
          child:Text(error!,style:const TextStyle(color:Color(0xFFAB374A)))),
      ])));
}

import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import '../core/controller.dart';
import '../core/push_bootstrap.dart';
import 'ios_components.dart';

/// Firebase project identity is app-level configuration, never a personal
/// provider key. Firebase Admin private credentials stay on the backend.
class PushDeviceScreen extends StatefulWidget {
  const PushDeviceScreen({super.key, required this.controller});
  final ControlController controller;
  @override State<PushDeviceScreen> createState() => _PushDeviceState();
}
class _PushDeviceState extends State<PushDeviceScreen> {
  Map<String,dynamic>? data;
  bool working=false;
  String? error;
  StreamSubscription<String>? refreshSubscription;
  bool get configuredOnDevice => hasPushConfiguration;
  @override void initState(){super.initState();_refresh();}
  @override void dispose(){refreshSubscription?.cancel();super.dispose();}
  Future<void> _refresh() async {
    try {
      final response = await widget.controller.client?.pushDeviceStatus();
      if (mounted) setState(() {data=response;error=null;});
    } catch(e){if(mounted)setState(()=>error=e.toString());}
  }
  Future<void> _enable() async {
    if (working) return;
    if (!configuredOnDevice){
      setState(()=>error='This app build has not been registered with a Firebase project. '
        'The developer must configure FlutterFire and rebuild once with matching '
        'Firebase Android/iOS app identifiers.');
      return;
    }
    if(data?['configured']!=true){
      setState(()=>error='The backend has no Firebase service account. '
        'Ask the workspace host to enable encrypted FCM delivery.');
      return;
    }
    setState(()=>working=true);
    try{
      if (!await configureFirebaseMessaging()) {
        throw StateError('Firebase initialization failed. Check the app build '
          'configuration against the project registered in Firebase Console.');
      }
      final messaging=FirebaseMessaging.instance;
      final permission=await messaging.requestPermission(
        alert:true,badge:true,sound:true);
      if(permission.authorizationStatus!=AuthorizationStatus.authorized &&
        permission.authorizationStatus!=AuthorizationStatus.provisional){
        throw StateError('Notification permission not granted');
      }
      if(Platform.isIOS && await messaging.getAPNSToken()==null){
        throw StateError('APNs device token is not available. '
          'Check Apple Push Notification capability and signing.');
      }
      await messaging.setAutoInitEnabled(true);
      final token=await messaging.getToken();
      if(token==null||token.isEmpty){
        throw StateError('Firebase did not return a device registration');
      }
      await widget.controller.client!.enrollPushDevice(
        token:token,platform:Platform.isIOS?'ios':'android',
        label:Platform.isIOS?'O-AGENT iPhone':'O-AGENT Android');
      await refreshSubscription?.cancel();
      refreshSubscription=messaging.onTokenRefresh.listen((next) async {
        if (!mounted || widget.controller.client==null) return;
        try {
          await widget.controller.client!.enrollPushDevice(
            token:next,platform:Platform.isIOS?'ios':'android',
            label:Platform.isIOS?'O-AGENT iPhone':'O-AGENT Android');
          await _refresh();
        } catch (_) {
          // Do not log a token or persist it outside the backend vault.
        }
      });
      await _refresh();
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>working=false);}
  }
  Future<void> _revoke(String id) async {
    final yes=await showDialog<bool>(context:context,
      builder:(ctx)=>AlertDialog(
        title:const Text('Revoke push device?'),
        content:const Text('O-AGENT will no longer send notifications to '
          'this device token. Existing phone OS notification permissions are separate.'),
        actions:[
          TextButton(onPressed:()=>Navigator.pop(ctx,false),
            child:const Text('Keep')),
          FilledButton(onPressed:()=>Navigator.pop(ctx,true),
            child:const Text('Revoke')),
        ]));
    if(yes!=true||!mounted)return;
    setState(()=>working=true);
    try{
      await widget.controller.client?.revokePushDevice(id);
      await _refresh();
    }catch(e){if(mounted)setState(()=>error=e.toString());}
    finally{if(mounted)setState(()=>working=false);}
  }
  @override Widget build(BuildContext context){
    final devices=data?['devices'] is List
      ? (data!['devices'] as List).whereType<Map>().toList():<Map>[];
    return Scaffold(backgroundColor:OVisual.canvas(context),
      appBar:AppBar(title:const Text('Notifications'),actions:[
        IconButton(onPressed:_refresh,icon:const Icon(CupertinoIcons.refresh)),
      ]),
      body:SafeArea(child:Center(child:ConstrainedBox(
        constraints:const BoxConstraints(maxWidth:700),
        child:ListView(padding:const EdgeInsets.fromLTRB(19,16,19,36),
          children:[
            const OScreenTitle(eyebrow:'Permissioned alerts',
              title:'Stay informed.',
              subtitle:'Receive real task approvals and agent status changes '
                'while your phone is away from the app. No prompt text or '
                'secrets are included in notifications.'),
            const SizedBox(height:18),
            OSurface(child:Column(
              crossAxisAlignment:CrossAxisAlignment.start,children:[
                Row(children:[
                  const Icon(CupertinoIcons.bell_fill,color:OVisual.primary),
                  const SizedBox(width:10),
                  Expanded(child:Text('Firebase Cloud Messaging',
                    style:TextStyle(color:OVisual.label(context),
                      fontWeight:FontWeight.w800))),
                  OStatePill(data?['configured']==true &&
                    configuredOnDevice?'connected':'requires_setup'),
                ]),
                const SizedBox(height:10),
                Text('Requires configured Firebase project on both the '
                  'application and O-AGENT backend, Android notification '
                  'permission or iOS APNs capability. Your personal '
                  'OpenAI/Cursor key cannot replace Firebase credentials.',
                  style:TextStyle(color:OVisual.muted(context),
                    fontSize:12,height:1.5)),
                const SizedBox(height:14),
                FilledButton.icon(onPressed:working?null:_enable,
                  icon:const Icon(CupertinoIcons.bell),
                  label:Text(working?'Registering…':'Enable on this device')),
              ])),
            if(error!=null)Padding(padding:const EdgeInsets.only(top:13),
              child:OSurface(child:Text(error!,
                style:const TextStyle(color:OVisual.rose,fontSize:12)))),
            const OSectionTitle('Registered devices'),
            if(devices.isEmpty)const OEmptyState(
              icon:CupertinoIcons.device_phone_portrait,
              title:'No devices registered',
              message:'Opt in on this device after Firebase has been '
                'configured to receive background notifications.'),
            for(final item in devices)Padding(
              padding:const EdgeInsets.only(bottom:10),
              child:OIconTile(icon:CupertinoIcons.device_phone_portrait,
                title:item['label']?.toString()??'Mobile device',
                subtitle:(item['platform']?.toString()??'')+' · '+
                  (item['registeredAt']?.toString()??''),
                trailing:IconButton(
                  onPressed:working?null:()=>_revoke(item['id'].toString()),
                  tooltip:'Revoke this push device',
                  icon:const Icon(CupertinoIcons.xmark_circle,
                    color:OVisual.rose)))),
          ]),
      ))),
    );
  }
}

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'dart:io';
import 'package:o_agent_mobile/core/pilot_native.dart';

class FakeLogin implements PilotAuthenticator {
  @override
  Future<PilotTokens> signIn(Uri origin, Map<String, dynamic> config) async =>
    PilotTokens(accessToken:'short-lived-in-memory-token',
      refreshToken:'private-refresh-key',
      expiresAt:DateTime.now().add(const Duration(hours:1)));
  @override
  Future<PilotTokens> renew(Uri origin, Map<String, dynamic> config,
      String token) async => signIn(origin,config);
}
class FastExpiringLogin implements PilotAuthenticator {
  @override
  Future<PilotTokens> signIn(Uri origin, Map<String,dynamic> config) async =>
    PilotTokens(accessToken:'rotating-access-token',
      refreshToken:'rotating-refresh-token',
      expiresAt:DateTime.now().add(const Duration(seconds:30)));
  @override
  Future<PilotTokens> renew(Uri origin, Map<String,dynamic> config,
      String token) async => signIn(origin,config);
}
class ClockLogin implements PilotAuthenticator {
  ClockLogin(this.clock);
  final DateTime Function() clock;
  int renewals=0;
  @override
  Future<PilotTokens> signIn(Uri origin, Map<String,dynamic> config) async =>
    PilotTokens(accessToken:'validated-access',
      refreshToken:'validated-refresh',
      expiresAt:clock().add(const Duration(minutes:2)));
  @override
  Future<PilotTokens> renew(Uri origin,Map<String,dynamic> config,
      String token) async {
    renewals++;
    return PilotTokens(accessToken:'validated-access',
      refreshToken:'rotated-refresh',
      expiresAt:clock().add(const Duration(minutes:2)));
  }
}
class FakeStore implements PilotSessionStore {
  StoredPilotSession? saved;
  int writes = 0;
  @override Future<StoredPilotSession?> read() async => saved;
  @override Future<void> write(StoredPilotSession value) async {
    writes++;
    saved=value;
  }
  @override Future<void> clear() async {
    saved=null;
  }
}

class FailingPilotAuthenticator implements PilotAuthenticator {
  @override
  Future<PilotTokens> signIn(Uri origin, Map<String,dynamic> config) async {
    throw PlatformException(code:'appauth_error',message:'AUTH-CODE-SECRET');
  }
  @override
  Future<PilotTokens> renew(Uri origin, Map<String,dynamic> config,
      String refresh) async {
    throw PlatformException(code:'appauth_error',message:'AUTH-CODE-SECRET');
  }
}

void main(){
  TestWidgetsFlutterBinding.ensureInitialized();
  const origin='https://pilot.example.ts.net:8443/';
  test('strict private HTTPS origin strips no credentials into web links',(){
    expect(privatePilotOrigin('http://127.0.0.1:8787'),isNull);
    expect(privatePilotOrigin('https://user:key@pilot.example.ts.net:8443/'),isNull);
    expect(privatePilotOrigin('https://pilot.example.ts.net:8443/#token=secret'),isNull);
    expect(privatePilotOrigin('https://pilot.example.ts.net:8443/?key=secret'),isNull);
    expect(privatePilotOrigin('javascript:alert(1)'),isNull);
    expect(privatePilotOrigin(origin)!.toString(),origin);
    expect(nativeClientId,'oagent-mobile');
    expect(nativeRedirectUri,'com.omiiii.oagent:/oauth2redirect');
  });
  test('private pairing links remain bound to exact own tailnet origin',(){
    final own=Uri.parse(origin);
    final token='oen_' + ('q'*43);
    expect(pilotPairingToken(origin+'#pair='+token,own),token);
    expect(pilotPairingToken(token,own),token);
    expect(()=>pilotPairingToken('https://other.ts.net/#pair='+token,own),
      throwsA(isA<PilotFailure>()));
    expect(()=>pilotPairingToken(origin+'#pair=short',own),
      throwsA(isA<PilotFailure>()));
  });
  test('OIDC endpoints cannot silently point to a different auth server',(){
    final uri=Uri.parse(origin);
    final config={
      'authEnabled':true,'audience':'oagent-api',
      'authorizationEndpoint':origin+
        'auth/realms/oagent/protocol/openid-connect/auth',
      'tokenEndpoint':origin+
        'auth/realms/oagent/protocol/openid-connect/token',
    };
    expect(validatedPilotAuthConfig(uri,config)['authEnabled'],true);
    expect(()=>validatedPilotAuthConfig(uri,{
      ...config,'tokenEndpoint':'https://evil.example/steal',
    }),throwsA(isA<PilotFailure>()));
  });
  test('native requests never execute before a separate owner approval',() async{
    final calls=<String>[],saved=FakeStore();
    final online={
      'id':'11111111-1111-4111-8111-111111111111',
      'name':'Trusted PC',
      'last_seen_at':DateTime.now().toUtc().toIso8601String(),
      'revoked_at':null,
      'workspace_root':'C:\\Users\\Developer\\Trusted',
      'capabilities':['workspace_inventory'],
    };
    final pending={
      'id':'22222222-2222-4222-8222-222222222222',
      'run_id':'33333333-3333-4333-8333-333333333333',
      'device_id':online['id'],
      'kind':'run','description':'Read enrolled workspace',
      'action_hash':'a'*64,'actionable':true,
    };
    var approvalCreated=false,wasApproved=false;
    Future<Map<String,dynamic>> request(Uri url,String method,
      Map<String,dynamic>? body,String? bearer,Map<String,String> headers) async {
      calls.add(method+' '+url.path);
      if(url.path=='/v1/public-config'){
        expect(bearer,isNull);
        return {'authEnabled':true,'audience':'oagent-api',
          'authorizationEndpoint':origin+
            'auth/realms/oagent/protocol/openid-connect/auth',
          'tokenEndpoint':origin+
            'auth/realms/oagent/protocol/openid-connect/token'};
      }
      expect(bearer,'short-lived-in-memory-token');
      if(url.path=='/v1/me')return {'tenantId':'tenant-test','role':'owner'};
      if(url.path=='/v1/devices')return {'devices':[online]};
      if(url.path=='/v1/sessions')return {'sessions':[]};
      if(url.path=='/v1/provider-sessions')return {'sessions':[]};
      if(url.path=='/v1/runs'&&method=='GET')return {'runs':[]};
      if(url.path=='/v1/approvals'&&method=='GET'){
        return {'approvals':approvalCreated&&!wasApproved?[pending]:[]};
      }
      if(url.path=='/v1/runs'&&method=='POST'){
        expect(body!['mode'],'read_only');
        expect(body['kind'],'workspace_inventory');
        expect(headers['idempotency-key']!.length,greaterThan(16));
        approvalCreated=true;
        return {'runId':pending['run_id'],'approvalId':pending['id'],
          'status':'waiting_for_approval'};
      }
      if(url.path.endsWith('/decision')&&method=='POST'){
        expect(body!['expectedActionHash'],'a'*64);
        expect(body['approve'],true);
        wasApproved=true;
        return {'decision':'approved'};
      }
      throw StateError('Unexpected API path: '+url.toString());
    }
    final c=NativePilotController(request:request,auth:FakeLogin(),store:saved);
    addTearDown(c.dispose);
    await c.signIn(origin, rememberDevice: true);
    expect(c.connected,true);
    expect(c.onlineDevices,1);
    expect(saved.saved?.origin,'https://pilot.example.ts.net:8443');
    await c.requestTurn(device:online,kind:'workspace_inventory',
      mode:'read_only',prompt:'Read filenames only');
    expect(approvalCreated,true);
    expect(wasApproved,false,reason:'creating a prompt must not execute automatically');
    expect(c.approvals.length,1);
    await c.decide(pending,true);
    expect(wasApproved,true);
    expect(c.approvals,isEmpty);
    expect(calls.where((x)=>x.startsWith('POST')).length,2);
    await c.signOut();
    expect(saved.saved,isNull);
    expect(c.connected,false);
  });
  test('Remember phone unchecked stays unpersisted even after token renewal',
      () async {
    final saved=FakeStore();
    Future<Map<String,dynamic>> request(Uri url,String method,
        Map<String,dynamic>? body,String? bearer,Map<String,String> headers) async {
      if(url.path=='/v1/public-config')return {
        'authEnabled':true,'audience':'oagent-api',
        'authorizationEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/auth',
        'tokenEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/token'};
      expect(bearer,'rotating-access-token');
      if(url.path=='/v1/me')return {'role':'owner'};
      if(url.path=='/v1/devices')return {'devices':[]};
      if(url.path=='/v1/runs')return {'runs':[]};
      if(url.path=='/v1/approvals')return {'approvals':[]};
      if(url.path=='/v1/sessions')return {'sessions':[]};
      if(url.path=='/v1/provider-sessions')return {'sessions':[]};
      throw StateError('Unexpected '+url.path);
    }
    final c=NativePilotController(request:request,
      auth:FastExpiringLogin(),store:saved);
    addTearDown(c.dispose);
    await c.signIn(origin,rememberDevice:false);
    expect(c.connected,true);
    expect(saved.saved,isNull);
    await c.refresh();
    expect(saved.writes,0,reason:'renewal must not save a refresh key');
    expect(saved.saved,isNull);
    await c.signOut();
    await c.signIn(origin,rememberDevice:true);
    expect(saved.writes,greaterThan(0));
    expect(saved.saved,isNotNull);
  });
  test('unsupported provider and offline worker are rejected before network write',() async{
    final c=NativePilotController(request:(u,m,b,t,h) async{
      throw StateError('Should not call a server for offline work');
    },auth:FakeLogin(),store:FakeStore());
    addTearDown(c.dispose);
    expect(()=>c.requestTurn(device:{
        'id':'11111111-1111-4111-8111-111111111111',
        'revoked_at':null,'last_seen_at':'2020-01-01T00:00:00Z',
        'capabilities':['codex_cli_turn'],
      },kind:'codex_cli_turn',mode:'read_only',prompt:'continue'),
      throwsA(isA<PilotFailure>()));
  });
  test('verified Codex sessions bind continuation to correct discovered cwd',
      () async {
    final id='11111111-1111-4111-8111-111111111111';
    final runId='33333333-3333-4333-8333-333333333333';
    final device={
      'id':id,'name':'Trusted laptop',
      'last_seen_at':DateTime.now().toUtc().toIso8601String(),
      'revoked_at':null,'workspace_root':'/trusted/workspace',
      'capabilities':['workspace_inventory','codex_cli_turn'],
    };
    final session={
      'deviceId':id,'sessionId':'codex-thread-12345',
      'cwd':'/trusted/workspace/project-one',
      'title':'Existing work in VS Code',
      'syncedAt':DateTime.now().toUtc().toIso8601String(),
      'updatedAt':DateTime.now().toUtc().toIso8601String(),
      'messages':<Map<String,dynamic>>[],
    };
    final writes=<String,Map<String,dynamic>>{};
    Future<Map<String,dynamic>> request(Uri url,String method,
        Map<String,dynamic>? body,String? bearer,Map<String,String> headers) async {
      if(url.path=='/v1/public-config')return {
        'authEnabled':true,'audience':'oagent-api',
        'authorizationEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/auth',
        'tokenEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/token'};
      expect(bearer,'short-lived-in-memory-token');
      if(url.path=='/v1/me')return {'tenantId':'tenant-id','role':'owner'};
      if(url.path=='/v1/devices')return {'devices':[device]};
      if(url.path=='/v1/runs'&&method=='GET')return {'runs':[]};
      if(url.path=='/v1/approvals')return {'approvals':[]};
      if(url.path=='/v1/sessions')return {'sessions':[session]};
      if(method=='POST'){
        writes[url.path]=body??{};
        return {'runId':runId,'status':'waiting_for_approval'};
      }
      throw StateError('Unknown path '+url.path);
    }
    final c=NativePilotController(
      request:request,auth:FakeLogin(),store:FakeStore());
    addTearDown(c.dispose);
    await c.signIn(origin);
    expect(c.sessions.length,1);
    await expectLater(c.requestTurn(device:device,kind:'codex_cli_turn',
      mode:'read_only',prompt:'Continue previous code edits',
      sessionId:'invented-session-12345'),throwsA(isA<PilotFailure>()));
    expect(writes,isEmpty,reason:'manual guessed thread IDs must not run');
    await c.requestTurn(device:device,kind:'codex_cli_turn',
      mode:'read_only',prompt:'Continue previous code edits',
      sessionId:'codex-thread-12345');
    expect(writes['/v1/runs']?['cwd'],'/trusted/workspace/project-one');
    expect(writes['/v1/runs']?['sessionId'],'codex-thread-12345');
    expect(writes['/v1/runs']?['prompt'],'Continue previous code edits');
    await c.cancelRun(runId);
    expect(writes['/v1/runs/'+runId+'/cancel'],isNotNull);
    await c.acknowledgeInterruptedRun(runId);
    expect(writes['/v1/runs/'+runId+'/resolve-interrupted']?['confirm'],
      'MARK_INTERRUPTED_RUN_FAILED');
  });

  test('concurrent native data requests rotate the OAuth token only once',
      () async {
    var clock=DateTime.now().toUtc();
    final auth=ClockLogin(()=>clock);
    final saved=FakeStore();
    Future<Map<String,dynamic>> request(Uri url,String method,
      Map<String,dynamic>? body,String? bearer,Map<String,String> headers) async {
      if(url.path=='/v1/public-config')return {
        'authEnabled':true,'audience':'oagent-api',
        'authorizationEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/auth',
        'tokenEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/token'};
      expect(bearer,'validated-access');
      if(url.path=='/v1/me')return {'role':'owner'};
      if(url.path=='/v1/devices')return {'devices':[]};
      if(url.path=='/v1/runs'&&method=='GET')return {'runs':[]};
      if(url.path=='/v1/approvals')return {'approvals':[]};
      if(url.path=='/v1/sessions')return {'sessions':[]};
      if(url.path=='/v1/provider-sessions')return {'sessions':[]};
      if(url.path.startsWith('/v1/provider-sessions/'))return {'turns':[]};
      if(url.path.endsWith('/events'))return {'events':[]};
      if(url.path.startsWith('/v1/runs/'))return {'id':'verified-run'};
      throw StateError('Unexpected URL: '+url.toString());
    }
    final c=NativePilotController(request:request,auth:auth,store:saved,
      now:()=>clock);
    addTearDown(c.dispose);
    await c.signIn(origin,rememberDevice:false);
    expect(c.connected,true);
    expect(auth.renewals,0);
    clock=clock.add(const Duration(minutes:3));
    await Future.wait([
      c.runDetail('11111111-1111-4111-8111-111111111111'),
      c.runEvents('11111111-1111-4111-8111-111111111111'),
      c.providerHistory(kind:'claude_agent_turn',
        deviceId:'11111111-1111-4111-8111-111111111111',
        sessionId:'claude-session-123456'),
    ]);
    expect(auth.renewals,1,
      reason:'parallel API requests must share rotating refresh credentials');
    expect(saved.writes,0,
      reason:'token refresh must not override Remember phone unchecked');
  });

  test('SDK conversation continuation is device, provider and cwd bound',
      () async {
    final id='11111111-1111-4111-8111-111111111111';
    final device={
      'id':id,'name':'Trusted laptop',
      'last_seen_at':DateTime.now().toUtc().toIso8601String(),
      'revoked_at':null,'workspace_root':'/safe/workspace',
      'capabilities':['claude_agent_turn','copilot_sdk_turn'],
    };
    final saved={
      'kind':'claude_agent_turn','deviceId':id,
      'deviceName':'Trusted laptop',
      'sessionId':'claude-sdk-session-34567',
      'cwd':'/safe/workspace/repository',
      'lastPrompt':'Review the code changes',
      'updatedAt':DateTime.now().toUtc().toIso8601String(),
    };
    final posted=<Map<String,dynamic>>[];
    Future<Map<String,dynamic>> request(Uri url,String method,
        Map<String,dynamic>? body,String? token,Map<String,String> headers) async {
      if(url.path=='/v1/public-config')return {
        'authEnabled':true,'audience':'oagent-api',
        'authorizationEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/auth',
        'tokenEndpoint':origin+
          'auth/realms/oagent/protocol/openid-connect/token'};
      expect(token,'short-lived-in-memory-token');
      if(url.path=='/v1/me')return {'tenantId':'tenant-test','role':'owner'};
      if(url.path=='/v1/devices')return {'devices':[device]};
      if(url.path=='/v1/runs' && method=='GET')return {'runs':[]};
      if(url.path=='/v1/approvals')return {'approvals':[]};
      if(url.path=='/v1/sessions')return {'sessions':[]};
      if(url.path=='/v1/provider-sessions')return {'sessions':[saved]};
      if(url.path=='/v1/provider-sessions/claude_agent_turn/claude-sdk-session-34567'){
        expect(url.queryParameters['deviceId'],id);
        return {'turns':[{'prompt':'Review the code changes',
          'response':'Completed the original SDK work'}]};
      }
      if(url.path=='/v1/runs' && method=='POST'){
        posted.add(body!);
        return {'runId':'33333333-3333-4333-8333-333333333333',
          'status':'waiting_for_approval'};
      }
      throw StateError('Unexpected request '+url.toString());
    }
    final c=NativePilotController(
      request:request,auth:FakeLogin(),store:FakeStore());
    addTearDown(c.dispose);
    await c.signIn(origin);
    expect(c.connected,true);
    expect(c.providerSessions.length,1);
    final history=await c.providerHistory(kind:'claude_agent_turn',
      deviceId:id,sessionId:'claude-sdk-session-34567');
    expect(history.single['response'],'Completed the original SDK work');
    await expectLater(c.requestTurn(device:device,kind:'claude_agent_turn',
      mode:'read_only',prompt:'Continue',
      sessionId:'guessed-other-sdk-123456'),
      throwsA(isA<PilotFailure>()));
    await expectLater(c.requestTurn(device:device,kind:'copilot_sdk_turn',
      mode:'read_only',prompt:'Continue',
      sessionId:'claude-sdk-session-34567'),
      throwsA(isA<PilotFailure>()));
    expect(posted,isEmpty);
    await c.requestTurn(device:device,kind:'claude_agent_turn',
      mode:'read_only',prompt:'Continue verified session',
      sessionId:'claude-sdk-session-34567');
    expect(posted.single['cwd'],'/safe/workspace/repository');
    expect(posted.single['sessionId'],'claude-sdk-session-34567');
    expect(posted.single['kind'],'claude_agent_turn');
  });



  test('private native connection preflight verifies health, API, and Keycloak without credentials',
      () async {
    final paths=<String>[];
    final base=origin.substring(0,origin.length-1);
    Future<Map<String,dynamic>> request(Uri url,String method,
        Map<String,dynamic>? body,String? bearer,Map<String,String> headers) async {
      expect(bearer,isNull);
      expect(method,'GET');
      paths.add(url.path);
      if(url.path=='/health/ready')return {'status':'ready','database':'connected'};
      if(url.path=='/v1/public-config')return {
        'authEnabled':true,'audience':'oagent-api',
        'authorizationEndpoint':origin+'auth/realms/oagent/protocol/openid-connect/auth',
        'tokenEndpoint':origin+'auth/realms/oagent/protocol/openid-connect/token'};
      if(url.path.endsWith('/.well-known/openid-configuration'))return {
        'issuer':base+'/auth/realms/oagent',
        'authorization_endpoint':base+'/auth/realms/oagent/protocol/openid-connect/auth',
        'jwks_uri':base+'/auth/realms/oagent/protocol/openid-connect/certs',
      };
      throw StateError('unexpected path');
    }
    final c=NativePilotController(
      request:request,auth:FakeLogin(),store:FakeStore());
    addTearDown(c.dispose);
    await c.testConnection(origin);
    expect(c.error,isNull);
    expect(c.connectionStatus,contains('checks passed'));
    expect(c.connected,false);
    expect(paths,['/health/ready','/v1/public-config',
      '/auth/realms/oagent/.well-known/openid-configuration']);
    c.clearLoginFeedback();
    expect(c.connectionStatus,isNull);
  });

  test('private native preflight stops immediately if database is not ready',
      () async {
    final paths=<String>[];
    Future<Map<String,dynamic>> request(Uri url,String method,
        Map<String,dynamic>? body,String? bearer,Map<String,String> headers) async {
      paths.add(url.path);
      return {'status':'starting','database':'disconnected'};
    }
    final c=NativePilotController(
      request:request,auth:FakeLogin(),store:FakeStore());
    addTearDown(c.dispose);
    await c.testConnection(origin);
    expect(c.error,contains('database is not ready'));
    expect(c.connectionStatus,isNull);
    expect(paths,['/health/ready']);
  });

  test('unexpected network and platform errors are stage-specific and secret-free',
      () {
    expect(pilotLoginStageError(StateError('refresh-token-SECRET'),
      'configuration'),contains('API-02'));
    expect(pilotLoginStageError(StateError('private-password-SECRET'),
      'identity'),contains('ID-03'));
    expect(pilotLoginStageError(StateError('auth-code-SECRET'),
      'account'),contains('AUTH-05'));
    final android=pilotLoginStageError(
      PlatformException(code:'invalid_grant',
        message:'secret-oauth-code-value'),
      'android-auth');
    expect(android,contains('AUTH-04'));
    expect(android, isNot(contains('secret-oauth-code-value')));
    expect(pilotLoginStageError(StateError('secret-device-value'),
      'phone-storage'),contains('PHONE-06'));
    final socket=pilotLoginStageError(
      const SocketException('secret-host-name'), 'health');
    expect(socket,isNot(contains('secret-host-name')));
  });

  test('native sign-in reports the authentication stage if browser plugin fails',
      () async {
    final c=NativePilotController(
      request:(url,method,body,bearer,headers) async => {
        'authEnabled':true,'audience':'oagent-api',
        'authorizationEndpoint':origin+'auth/realms/oagent/protocol/openid-connect/auth',
        'tokenEndpoint':origin+'auth/realms/oagent/protocol/openid-connect/token'},
      auth:FailingPilotAuthenticator(),store:FakeStore());
    addTearDown(c.dispose);
    await c.signIn(origin);
    expect(c.connected,false);
    expect(c.error,contains('AUTH-04'));
    expect(c.error,isNot(contains('SECRET')));
  });

}

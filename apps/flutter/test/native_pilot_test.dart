import 'package:flutter_test/flutter_test.dart';
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
class FakeStore implements PilotSessionStore {
  StoredPilotSession? saved;
  @override Future<StoredPilotSession?> read() async => saved;
  @override Future<void> write(StoredPilotSession value) async {
    saved=value;
  }
  @override Future<void> clear() async {
    saved=null;
  }
}
void main(){
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
    await c.signIn(origin);
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
}

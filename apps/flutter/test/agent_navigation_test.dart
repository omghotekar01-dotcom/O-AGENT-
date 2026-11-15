import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/controller.dart';
import 'package:o_agent_mobile/core/pilot_native.dart';
import 'package:o_agent_mobile/theme.dart';
import 'package:o_agent_mobile/ui/native_pilot.dart';

class _TestLogin implements PilotAuthenticator {
  @override
  Future<PilotTokens> signIn(Uri origin, Map<String,dynamic> config) async =>
    PilotTokens(accessToken:'test-token', refreshToken:null,
      expiresAt:DateTime.now().add(const Duration(hours:1)));
  @override
  Future<PilotTokens> renew(Uri origin, Map<String,dynamic> config,
    String token) async => signIn(origin,config);
}
class _NoRemember implements PilotSessionStore {
  @override
  Future<StoredPilotSession?> read() async => null;
  @override
  Future<void> write(StoredPilotSession session) async {}
  @override
  Future<void> clear() async {}
}

void main() {
  testWidgets('signed-in iOS-style native home is Agents, Sessions, Remote, Inbox, Settings',
    (tester) async {
    const address='https://example.tailnet.ts.net:8443/';
    Future<Map<String,dynamic>> request(Uri url,String method,
      Map<String,dynamic>? body,String? bearer,
      Map<String,String> headers) async {
      if(url.path=='/v1/public-config')return {
        'authEnabled':true,'audience':'oagent-api',
        'authorizationEndpoint':address+
          'auth/realms/oagent/protocol/openid-connect/auth',
        'tokenEndpoint':address+
          'auth/realms/oagent/protocol/openid-connect/token',
      };
      if(url.path=='/v1/me')return {'role':'owner','tenantId':'test'};
      if(url.path=='/v1/devices')return {'devices':[]};
      if(url.path=='/v1/runs')return {'runs':[]};
      if(url.path=='/v1/approvals')return {'approvals':[]};
      if(url.path=='/v1/sessions')return {'sessions':[]};
      if(url.path=='/v1/provider-sessions')return {'sessions':[]};
      throw StateError('Unmocked endpoint');
    }
    final pilot=NativePilotController(request:request,
      auth:_TestLogin(),store:_NoRemember());
    final legacy=ControlController();
    addTearDown(pilot.dispose);
    addTearDown(legacy.dispose);
    await pilot.signIn(address);
    expect(pilot.connected,true);

    for (final platform in [TargetPlatform.iOS,TargetPlatform.android]) {
      await tester.pumpWidget(MaterialApp(
        theme:OTheme.studio().copyWith(platform:platform),
        home:CupertinoTheme(
          data:OTheme.sharedCupertino,
          child:NativePilotShell(legacy:legacy,pilot:pilot))));
      await tester.pumpAndSettle();
      expect(find.byType(CupertinoTabBar),findsOneWidget);
      expect(find.text('Your AI work.\nAnywhere.'),findsOneWidget);
      expect(find.text('OpenAI Codex CLI / IDE'),findsOneWidget);
      expect(find.text('Sessions'),findsOneWidget);
      expect(find.text('Inbox'),findsOneWidget);
      expect(find.text('Remote'),findsOneWidget);
      expect(find.text('Settings'),findsOneWidget);
      expect(tester.takeException(),isNull);
      await tester.tap(find.text('Remote'));
      await tester.pumpAndSettle();
      expect(find.text('Your actual screen.\nOn your phone.'),findsOneWidget);
      expect(find.text('Existing gateway owner token'),findsOneWidget);
      await tester.tap(find.text('Agents'));
      await tester.pumpAndSettle();
      expect(find.text('Your AI work.\nAnywhere.'),findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

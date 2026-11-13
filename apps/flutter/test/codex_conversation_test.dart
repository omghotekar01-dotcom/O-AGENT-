import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/api_client.dart';
import 'package:o_agent_mobile/core/controller.dart';
import 'package:o_agent_mobile/theme.dart';
import 'package:o_agent_mobile/ui/codex_conversation.dart';
import 'package:o_agent_mobile/ui/codex_session.dart';

const project = 'codex-local:test-worker:123456789012345678901234';
const conversation = '11111111-2222-4333-8444-555555555555';

class _LiveFixtureApi extends AgentApi {
  _LiveFixtureApi():super('http://127.0.0.1:8787',
      'test-operator-secret-not-a-real-token-12345');
  bool historyRequested = false;
  bool sentConfirmed = false;
  int sends = 0;
  @override Future<Map<String,dynamic>> loadCodexConversation({
    required String projectId,required String sessionId,
  }) async {
    assert(projectId == project && sessionId == conversation);
    historyRequested = true;
    return {'id':'history-task-1','status':'queued','result':null};
  }
  @override Future<Map<String,dynamic>> taskDetail(String id) async {
    if(id=='history-task-1'){
      return {
        'id':id,'status':'completed','result':{
          'messages':[
            {'role':'user','text':'Please review my project'},
            {'role':'assistant','text':'I reviewed it and found two tasks.'},
          ],
          'truncated':false,
        },
      };
    }
    return {'id':'turn-1','kind':'codex_cli_turn','status':'queued',
      'parameters':{'prompt':'Review the work without editing.',
        'sessionId':conversation,'mode':'read_only'},
      'updates':<Object>[], 'approvals':<String,Object>{}};
  }
  @override Future<Map<String,dynamic>> sendConfirmedCodexTurn({
    required String projectId,required String sessionId,
    required String prompt,required String mode,
  }) async {
    assert(projectId==project);
    assert(sessionId==conversation);
    assert(prompt=='Review the work without editing.');
    assert(mode=='read_only');
    sends++;
    sentConfirmed=true;
    return taskDetail('turn-1');
  }
}
class _LiveFixtureController extends ControlController {
  final fakeApi=_LiveFixtureApi();
  @override AgentApi? get client=>fakeApi;
  @override bool get connected=>true;
  @override void dispose(){fakeApi.close();super.dispose();}
}

void main(){
  testWidgets('A phone user can load actual saved Codex text without a paid API',
    (tester) async {
      final controller=_LiveFixtureController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme:OTheme.studio(),
        home:Scaffold(body:SingleChildScrollView(
          child:CodexConversationPanel(controller:controller,
            projectId:project,sessionId:conversation),
        )),
      ));
      expect(find.text('Load saved messages'),findsOneWidget);
      await tester.tap(find.text('Load saved messages'));
      await tester.pumpAndSettle();
      expect(controller.fakeApi.historyRequested,isTrue);
      expect(find.text('Please review my project'),findsOneWidget);
      expect(find.text('I reviewed it and found two tasks.'),findsOneWidget);
      expect(find.text('CODEX'),findsOneWidget);
      expect(tester.takeException(),isNull);
    });
  testWidgets('Codex prompt helper is free and exact one-time consent sends one task',
    (tester) async {
      tester.view.physicalSize=const Size(390,850);
      tester.view.devicePixelRatio=1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller=_LiveFixtureController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme:OTheme.studio(),home:CodexSessionScreen(
          controller:controller,projectId:project,
          sessionId:conversation,sessionTitle:'My real project',
          cwd:r'C:\Users\ASUS\Projects\O-AGENT',
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Progress update'),findsOneWidget);
      expect(find.text('What next?'),findsOneWidget);
      expect(find.text('Explain error'),findsOneWidget);
      await tester.tap(find.text('Progress update'));
      await tester.pump();
      final field=tester.widget<TextField>(find.byType(TextField).last);
      expect(field.controller!.text,contains('Summarize what has been completed'));
      await tester.enterText(find.byType(TextField).last,
        'Review the work without editing.');
      await tester.tap(find.byTooltip('Review and send instruction'));
      await tester.pumpAndSettle();
      expect(find.text('Send this instruction to Codex?'),findsOneWidget);
      expect(controller.fakeApi.sends,0);
      await tester.tap(find.text('Approve and send'));
      await tester.pumpAndSettle();
      expect(controller.fakeApi.sentConfirmed,isTrue);
      expect(controller.fakeApi.sends,1);
      expect(tester.takeException(),isNull);
    });
}

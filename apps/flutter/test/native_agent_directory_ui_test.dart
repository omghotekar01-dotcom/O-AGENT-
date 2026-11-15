import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/pilot_native.dart';
import 'package:o_agent_mobile/ui/native_agent_directory.dart';

void main(){
  testWidgets('iOS-style native directory renders before sign-in with truthful statuses',
      (tester)async{
    final pilot=NativePilotController();
    addTearDown(pilot.dispose);
    await tester.pumpWidget(MaterialApp(home:Scaffold(
      body:NativeAgentDirectory(
        pilot:pilot,preview:true,
        onSessions:(){},onDevices:(){},onLegacy:(){}))));
    expect(find.text('AI Agents'),findsOneWidget);
    expect(find.byType(CupertinoSearchTextField),findsOneWidget);
    expect(find.byType(CupertinoSlidingSegmentedControl<String>),findsOneWidget);
    expect(find.byType(CupertinoListSection),findsWidgets);
    expect(find.text('OpenAI Codex CLI / IDE'),findsOneWidget);
    expect(find.byKey(const ValueKey('agent-codex')),findsOneWidget);
    await tester.enterText(find.byType(CupertinoSearchTextField),'ChatGPT');
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-chatgpt')),findsOneWidget);
    expect(find.text('Official app / website only'),findsOneWidget);
    expect(find.text('OpenAI Codex CLI / IDE'),findsNothing);
    expect(tester.takeException(),isNull);
  });
}

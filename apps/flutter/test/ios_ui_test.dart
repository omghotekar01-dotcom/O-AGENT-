import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/ui/ios_components.dart';
import 'package:o_agent_mobile/ui/cursor_cloud.dart';
import 'package:o_agent_mobile/ui/projects.dart';

void main() {
  testWidgets('Original iOS-style grouped components fit a compact display',
    (tester) async {
      tester.view.physicalSize = const Size(360, 680);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        SingleChildScrollView(child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(children: [
            const OScreenTitle(eyebrow: 'Remote', title: 'Stay in control.',
              subtitle: 'Real work, without invented remote sessions.'),
            const SizedBox(height: 15),
            const OStatePill('waiting_for_approval'),
            const SizedBox(height: 15),
            OIconTile(icon: Icons.cloud_outlined, title: 'Cursor Cloud Agents',
              subtitle: 'True provider-owned cloud sessions and real agent runs',
              onTap: () {}),
          ]),
        )))));
      expect(find.text('Stay in control.'), findsOneWidget);
      expect(find.text('Cursor Cloud Agents'), findsOneWidget);
      expect(tester.takeException(), isNull);
  });

  testWidgets('Cursor credential sheet keeps the secret out of the UI after dismissal',
    (tester) async {
      String? saved;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        Builder(builder: (context) => FilledButton(
          onPressed: () async {
            saved = await showModalBottomSheet<String>(
              context: context, isScrollControlled: true,
              builder: (_) => const CursorKeySheet());
          },
          child: const Text('Connect Cursor'),
        )))));
      await tester.tap(find.text('Connect Cursor'));
      await tester.pumpAndSettle();
      expect(find.text('Cursor Cloud API key'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'test-cursor-private-token-1234');
      await tester.tap(find.text('Save and verify'));
      await tester.pumpAndSettle();
      expect(saved, 'test-cursor-private-token-1234');
      expect(find.text('test-cursor-private-token-1234'), findsNothing);
      expect(tester.takeException(), isNull);
    });

  testWidgets('Cursor prompt has explicit steer choice and confirmation phase',
    (tester) async {
      CursorPromptDraft? result;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        Builder(builder: (context) => FilledButton(
          onPressed: () async {
            result = await showModalBottomSheet<CursorPromptDraft>(
              context: context, isScrollControlled: true,
              builder: (_) => const CursorPromptSheet());
          },
          child: const Text('Send new prompt'),
        )))));
      await tester.tap(find.text('Send new prompt'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'Improve accessibility tests');
      await tester.tap(find.byType(SwitchListTile));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Review prompt before sending'));
      await tester.pumpAndSettle();
      expect(result?.prompt, 'Improve accessibility tests');
      expect(result?.steer, true);
      expect(tester.takeException(), isNull);
    });

  testWidgets('New cloud agent form chooses repo, plan mode and consent preferences',
    (tester) async {
      CursorCreateDraft? draft;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        Builder(builder: (context) => TextButton(
          onPressed: () async {
            draft = await showModalBottomSheet<CursorCreateDraft>(
              context: context, isScrollControlled: true,
              builder: (_) => const CursorCreateAgentSheet());
          },
          child: const Text('Create cloud agent'),
        )))));
      await tester.tap(find.text('Create cloud agent'));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsNWidgets(3));
      await tester.enterText(find.byType(TextField).at(0),
        'https://github.com/example/project');
      await tester.enterText(find.byType(TextField).at(1), 'development');
      await tester.enterText(find.byType(TextField).at(2),
        'Write a safe implementation plan');
      await tester.ensureVisible(find.text('Review before creating'));
      await tester.tap(find.text('Review before creating'));
      await tester.pumpAndSettle();
      expect(draft?.repoUrl, 'https://github.com/example/project');
      expect(draft?.startingRef, 'development');
      expect(draft?.prompt, 'Write a safe implementation plan');
      expect(draft?.mode, 'plan');
      expect(draft?.autoCreatePR, false);
      expect(tester.takeException(), isNull);
    });

  testWidgets('Project creation fields survive closing animation',
    (tester) async {
      Map<String, String>? saved;
      await tester.pumpWidget(MaterialApp(home: Scaffold(body:
        Builder(builder: (context) => TextButton(
          onPressed: () async {
            saved = await showDialog<Map<String, String>>(
              context: context, builder: (_) => const ProjectCreateDialog());
          },
          child: const Text('Create project workspace'),
        )))));
      await tester.tap(find.text('Create project workspace'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, 'My tested project');
      await tester.tap(find.text('Create project'));
      await tester.pumpAndSettle();
      expect(saved?['title'], 'My tested project');
      expect(tester.takeException(), isNull);
    });
}

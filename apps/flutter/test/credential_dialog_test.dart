import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/ui/account_workspace.dart';

void main() {
  testWidgets('API key dialog retains controllers through pop animation',
      (tester) async {
    Map<String, String>? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => FilledButton(onPressed: () async {
        saved = await showDialog<Map<String, String>>(context: ctx,
          builder: (_) => ProviderKeyDialog(
            existing: const {'id': 'openai', 'label': 'OpenAI API',
              'model': 'gpt-test', 'connected': false},
            onGetKey: () {}));
      }, child: const Text('Open provider'))))));
    await tester.tap(find.text('Open provider'));
    await tester.pumpAndSettle();
    expect(find.text('Model ID'), findsOneWidget);
    await tester.enterText(find.widgetWithText(TextField, 'Your API key'), 'sk-example-secret');
    await tester.tap(find.text('Save securely'));
    await tester.pumpAndSettle();
    expect(saved?['model'], 'gpt-test');
    expect(saved?['apiKey'], 'sk-example-secret');
    expect(tester.takeException(), isNull);
  });
  testWidgets('GitHub token dialog closes cleanly', (tester) async {
    String? saved;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: Builder(
      builder: (ctx) => FilledButton(onPressed: () async {
        saved = await showDialog<String>(context: ctx,
          builder: (_) => const GithubTokenDialog());
      }, child: const Text('Open GitHub'))))));
    await tester.tap(find.text('Open GitHub'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Personal access token'), 'github_pat_test');
    await tester.tap(find.text('Verify and connect'));
    await tester.pumpAndSettle();
    expect(saved, 'github_pat_test');
    expect(tester.takeException(), isNull);
  });
}

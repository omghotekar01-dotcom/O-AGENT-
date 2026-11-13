import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/controller.dart';
import 'package:o_agent_mobile/core/api_client.dart';
import 'package:o_agent_mobile/theme.dart';
import 'package:o_agent_mobile/ui/projects.dart';

void main() {
  testWidgets(
    'Projects navigated as a standalone route must have a Material ancestor',
    (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = ControlController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(MaterialApp(
        theme: OTheme.studio(),
        home: Scaffold(body: Builder(builder: (context) =>
          FilledButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ProjectHubScreen(controller: controller),
              ),
            ),
            child: const Text('Open projects'),
          ),
        )),
      ));
      await tester.tap(find.text('Open projects'));
      await tester.pumpAndSettle();

      // This previously threw "No Material widget found" in TextField
      // because the Projects route built RefreshIndicator/ListView directly.
      expect(find.text('Your AI command center.'), findsOneWidget);
      expect(find.byType(Scaffold), findsOneWidget);
      // ListView.builder eagerly constructs only visible children; the search
      // field sits beneath the dashboard cards on a compact phone.
      await tester.scrollUntilVisible(find.byType(TextField), 240,
        maxScrolls: 12);
      expect(find.byType(TextField), findsOneWidget);
      expect(find.ancestor(
        of: find.byType(TextField),
        matching: find.byType(Material),
      ), findsWidgets);

      await tester.ensureVisible(find.byType(TextField).first);
      await tester.enterText(find.byType(TextField).first, 'Flutter');
      await tester.pump();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('24 real-response-shaped projects render and remain searchable',
    (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final controller = _ProjectFixtureController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: OTheme.studio(),
        home: ProjectHubScreen(controller: controller),
      ));
      await tester.pumpAndSettle();

      // This mirrors the counts visible in the user's failing screenshot,
      // using a test fixture only. The production app never fabricates data.
      expect(find.text('Your AI command center.'), findsOneWidget);
      expect(find.text('24'), findsOneWidget);
      expect(find.text('23'), findsOneWidget);
      await tester.scrollUntilVisible(find.text('Projects · 24'), 230,
        maxScrolls: 10);
      expect(find.text('Projects · 24'), findsOneWidget);
      await tester.scrollUntilVisible(find.byType(TextField), 220,
        maxScrolls: 12);
      await tester.enterText(find.byType(TextField).first, 'Project 5');
      await tester.pumpAndSettle();
      expect(find.text('Project 5'), findsOneWidget);
      expect(find.text('Project 6'), findsNothing);
      expect(tester.takeException(), isNull);
    });

  testWidgets('Projects route shows a readable offline error without crashing',
    (tester) async {
      final controller = ControlController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(MaterialApp(
        theme: OTheme.studio(),
        home: ProjectHubScreen(controller: controller),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Cannot read project feed'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
}


class _ProjectFixtureApi extends AgentApi {
  _ProjectFixtureApi()
    : super('http://127.0.0.1:8787', 'fixture-test-operator-token-123456');

  @override
  Future<Map<String, dynamic>> projects() async => {
    'projects': [
      for (var i = 0; i < 24; i++)
        {
          'id': 'test-project-$i',
          'title': 'Project $i',
          'source': i < 23 ? 'codex_cli' : 'oagent',
          'sourceRef': 'repo/fixture-$i',
          'cwd': '/safe/test-workspace/$i',
          'state': 'available',
          'control': 'read_only',
          'description': 'A test-only project for layout validation',
        },
    ],
    'sources': [
      {'id': 'codex_cli', 'label': 'Codex CLI', 'status': 'connected'},
      {'id': 'github', 'label': 'GitHub', 'status': 'connected'},
    ],
    'sourceErrors': <Object>[],
  };
}
class _ProjectFixtureController extends ControlController {
  final _fixtureApi = _ProjectFixtureApi();
  @override AgentApi? get client => _fixtureApi;
  @override bool get connected => true;
  @override void dispose() {
    _fixtureApi.close();
    super.dispose();
  }
}

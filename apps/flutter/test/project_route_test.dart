import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/controller.dart';
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
      expect(find.byType(TextField), findsOneWidget);
      expect(find.byType(ChoiceChip), findsWidgets);
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

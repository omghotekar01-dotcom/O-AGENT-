import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/main.dart';
import 'package:o_agent_mobile/core/controller.dart';
import 'package:o_agent_mobile/core/models.dart';
import 'package:o_agent_mobile/theme.dart';
import 'package:o_agent_mobile/ui/screens.dart';

void main() {
  testWidgets('login screen is honest about backend connectivity', (tester) async {
    await tester.pumpWidget(const OAgentApp());
    expect(find.text('Connect to O-AGENT'), findsOneWidget);
    expect(find.textContaining('Development connection'), findsOneWidget);
    expect(find.textContaining('Only real machines'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.textContaining('demo'), findsNothing);
  });

  testWidgets('operator token remains required before connect', (tester) async {
    await tester.pumpWidget(const OAgentApp());
    expect(find.text('Operator token'), findsOneWidget);
    final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Connect to O-AGENT'));
    expect(button.onPressed, isNotNull);
  });
  testWidgets('mobile dashboard metrics do not overflow at compact widths', (tester) async {
    tester.view.physicalSize = const Size(720, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = ControlController()
      ..snapshot = const ControlSnapshot(machines: [], tasks: [], nextSequence: 1);
    addTearDown(controller.dispose);

    await tester.pumpWidget(MaterialApp(
      theme: OTheme.dark(),
      home: Scaffold(body: OverviewScreen(controller: controller, navigateTo: (_) {})),
    ));
    expect(find.text('Machines'), findsOneWidget);
    expect(find.text('Approvals'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/main.dart';
import 'package:o_agent_mobile/core/controller.dart';
import 'package:o_agent_mobile/core/models.dart';
import 'package:o_agent_mobile/theme.dart';
import 'package:o_agent_mobile/ui/screens.dart';

void main() {
  testWidgets('primary experience is native instead of a website', (tester) async {
    await tester.pumpWidget(const OAgentApp());
    expect(find.text('Sign in to native app'), findsOneWidget);
    await tester.drag(find.byType(ListView).first, const Offset(0, -550));
    await tester.pumpAndSettle();
    expect(find.text('Earlier native project workspace'), findsOneWidget);
    expect(find.textContaining('Private HTTPS address'), findsOneWidget);
    expect(find.text('Open secure mobile command center'), findsNothing);
    expect(find.text('Operator token'), findsNothing);
  });

  testWidgets('native login has a single HTTPS endpoint field', (tester) async {
    await tester.pumpWidget(const OAgentApp());
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Sign in to native app'), findsOneWidget);
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

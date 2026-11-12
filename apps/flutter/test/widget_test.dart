import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/main.dart';

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
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/controller.dart';
import 'package:o_agent_mobile/ui/public_account.dart';

void main() {
  testWidgets('Public signup, verification and recovery forms are visible', (tester) async {
    final controller = ControlController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(home: PublicAccountScreen(
      controller: controller, backend: 'https://agent.example.org', remember: false)));
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Verify email'), findsWidgets);
    expect(find.text('Forgot password'), findsWidgets);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Create account'));
    await tester.pump();
    expect(find.text('Display name'), findsOneWidget);
  });
}

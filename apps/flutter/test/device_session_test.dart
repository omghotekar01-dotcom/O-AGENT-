import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/controller.dart';
import 'package:o_agent_mobile/core/device_session.dart';
import 'package:o_agent_mobile/main.dart';

class FakeSessionStore implements SessionStore {
  SavedDeviceSession? data;
  int cleared = 0;

  @override
  Future<void> clear() async {
    data = null;
    cleared++;
  }

  @override
  Future<SavedDeviceSession?> read() async => data;

  @override
  Future<void> save(SavedDeviceSession session) async {
    data = session;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('secure restoration does nothing when the user did not opt in', () async {
    final store = FakeSessionStore();
    final controller = ControlController(sessionStore: store);
    addTearDown(controller.dispose);
    expect(await controller.reconnectSavedSession(), isFalse);
    expect(controller.hasSavedSession, isFalse);
    expect(controller.restoringSession, isFalse);
  });

  test('disconnect clears an optional stored token', () async {
    final store = FakeSessionStore()
      ..data = const SavedDeviceSession(endpoint: 'https://example.org', token: 'example-long-not-real-operator-token');
    final controller = ControlController(sessionStore: store);
    addTearDown(controller.dispose);
    controller.disconnect();
    await Future<void>.delayed(Duration.zero);
    expect(store.data, isNull);
    expect(store.cleared, 1);
    expect(controller.hasSavedSession, isFalse);
  });

  testWidgets('remembering the device is an explicit choice, disabled by default', (tester) async {
    final controller = ControlController(sessionStore: FakeSessionStore());
    addTearDown(controller.dispose);
    await tester.pumpWidget(OAgentApp(controller: controller));
    await tester.pumpAndSettle();
    final remember = find.widgetWithText(CheckboxListTile, 'Remember this device');
    expect(remember, findsOneWidget);
    expect(tester.widget<CheckboxListTile>(remember).value, isFalse);
    await tester.tap(remember);
    await tester.pump();
    expect(tester.widget<CheckboxListTile>(remember).value, isTrue);
  });
}

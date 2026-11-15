import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'core/controller.dart';
import 'core/push_bootstrap.dart';
import 'theme.dart';
import 'ui/native_pilot.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureFirebaseMessaging();
  runApp(const OAgentApp());
}

class OAgentApp extends StatefulWidget {
  const OAgentApp({super.key, this.controller});
  final ControlController? controller;

  @override
  State<OAgentApp> createState() => _OAgentAppState();
}

class _OAgentAppState extends State<OAgentApp> {
  late final ControlController controller = widget.controller ?? ControlController();

  @override
  void dispose() {
    if (widget.controller == null) controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'O-AGENT',
        debugShowCheckedModeBanner: false,
        theme: OTheme.studio(),
        home: CupertinoTheme(
          data: OTheme.sharedCupertino,
          child: NativePilotShell(legacy: controller),
        ),
      );
}

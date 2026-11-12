import 'package:flutter/material.dart';
import 'core/controller.dart';
import 'theme.dart';
import 'ui/studio.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
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
        home: StudioShell(controller: controller),
      );
}

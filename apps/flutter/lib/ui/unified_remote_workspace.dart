import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import '../core/controller.dart';
import '../theme.dart';
import 'ios_components.dart';
import 'remote_mission_control.dart';

/// Mounts the already-developed live screen, VS Code and project controller
/// INSIDE the current app navigation. Never pushes the old StudioConnect
/// or asks for an unrelated new O-AGENT account. The old gateway still needs
/// its own locally approved credentials until a secure account migration exists.
class UnifiedRemoteWorkspace extends StatefulWidget {
  const UnifiedRemoteWorkspace({
    super.key, required this.legacy, required this.onDevices});
  final ControlController legacy;
  final VoidCallback onDevices;

  @override
  State<UnifiedRemoteWorkspace> createState() => _UnifiedRemoteWorkspaceState();
}

class _UnifiedRemoteWorkspaceState extends State<UnifiedRemoteWorkspace> {
  final address = TextEditingController();
  final secret = TextEditingController();
  bool remember = true;
  bool connecting = false;
  String? failure;

  @override
  void initState() {
    super.initState();
    widget.legacy.addListener(_changed);
    // Reuse an already-authorized device session, if the owner previously
    // saved one in Android Keystore or iOS Keychain.
    Future.microtask(() => widget.legacy.reconnectSavedSession());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.legacy.removeListener(_changed);
    address.dispose();
    secret.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (connecting) return;
    final target = Uri.tryParse(address.text.trim());
    if (target == null || target.scheme != 'https' ||
        target.host.isEmpty || target.userInfo.isNotEmpty ||
        target.hasQuery || target.hasFragment ||
        (target.path.isNotEmpty && target.path != '/')) {
      setState(() => failure = 'Enter the actual private HTTPS '
        'screen-control gateway address. Do not use localhost on your phone.');
      return;
    }
    if (secret.text.trim().length < 24) {
      setState(() => failure = 'The existing remote gateway needs '
        'its separately authorized owner access token. '
        'Do not paste your O-AGENT SaaS password or pairing link here.');
      return;
    }
    setState(() { connecting = true; failure = null; });
    final success = await widget.legacy.connect(
      target.origin, secret.text, remember: remember);
    if (!mounted) return;
    setState(() {
      connecting = false;
      if (success) {
        secret.clear();
      } else {
        failure = 'The existing screen-control gateway did not '
          'authenticate or respond. Check that its trusted Windows '
          'launcher is running and its HTTPS Tailscale route is valid.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.legacy.connected) {
      // Real streaming, pointer/keyboard control, GitHub projects,
      // VS Code activity, agent tasks and approvals live in this widget.
      return RemoteMissionControlScreen(controller: widget.legacy);
    }
    return ColoredBox(
      color: OTheme.paper,
      child: ListView(padding: const EdgeInsets.fromLTRB(20, 24, 20, 36),
        children: [
          const OScreenTitle(
            eyebrow: 'LIVE REMOTE WORKSPACE',
            title: 'Your actual screen.\nOn your phone.',
            subtitle: 'See a consented laptop display and control the '
              'currently focused apps, or inspect connected projects and '
              'provider work. No simulated remote desktop.'),
          const SizedBox(height: 18),
          OSurface(tint: OTheme.lavender, child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(CupertinoIcons.desktopcomputer,
                color: OTheme.violet, size: 29),
              const SizedBox(height: 10),
              const Text('Real laptop screen & agent controls',
                style: TextStyle(fontSize: 17,
                  fontWeight: FontWeight.w800, color: OTheme.ink)),
              const SizedBox(height: 7),
              const Text(
                'The older O-AGENT Windows gateway already supports '
                'consented live screen frames, trusted input, real '
                'Codex/project activity, GitHub projects and Cursor '
                'connections. Those controls open HERE after the '
                'gateway is authenticated—not in a second app.',
                style: TextStyle(fontSize: 13, height: 1.5,
                  color: OTheme.ink)),
              const SizedBox(height: 12),
              TextButton.icon(onPressed: widget.onDevices,
                icon: const Icon(CupertinoIcons.device_laptop),
                label: const Text('Manage enrolled PC')),
            ])),
          const SizedBox(height: 20),
          const OSectionTitle('Connect your existing remote gateway'),
          OSurface(child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Existing settings on the PC are kept. If the previous '
                'gateway is configured, the one-click launcher can start '
                'it alongside the private SaaS worker. '
                'You still authorize this gateway once using its own token.',
                style: TextStyle(fontSize: 12, height: 1.5,
                  color: Color(0xFF586B75))),
              const SizedBox(height: 14),
              TextField(
                key: const ValueKey('remote-gateway-origin'),
                controller: address,
                autocorrect: false, enableSuggestions: false,
                keyboardType: TextInputType.url,
                decoration: const InputDecoration(
                  labelText: 'Existing HTTPS remote gateway address',
                  hintText: 'https://your-pc.tailnet.ts.net/')),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('remote-gateway-token'),
                controller: secret, obscureText: true,
                autocorrect: false, enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'Existing gateway owner token',
                  helperText: 'Separate from the native Keycloak account')),
              const SizedBox(height: 14),
              Row(children: [
                const Expanded(child: Text(
                  'Remember this trusted phone',
                  style: TextStyle(color: OTheme.ink,
                    fontWeight: FontWeight.w700))),
                CupertinoSwitch(value: remember,
                  onChanged: (v) => setState(() => remember = v)),
              ]),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: connecting ? null : _connect,
                icon: connecting
                  ? const SizedBox(width: 18, height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white))
                  : const Icon(CupertinoIcons.lock_shield),
                label: Text(connecting
                  ? 'Verifying remote gateway…'
                  : 'Open existing screen and projects')),
              if (widget.legacy.restoringSession)
                const Padding(padding: EdgeInsets.only(top: 12),
                  child: Text('Restoring secure saved remote connection…')),
              if (failure != null) Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(failure!, style: const TextStyle(
                  color: Color(0xFFAD404A), fontSize: 12))),
            ])),
          const SizedBox(height: 14),
          const OSurface(child: Text(
            'Why is this gateway asking for an existing token? '
            'It is a separate older backend with different authentication. '
            'We cannot silently move its Windows DPAPI secrets into the '
            'new OIDC account. Automatic secure migration is a remaining '
            'engineering task. Do not disable HTTPS or share credentials.',
            style: TextStyle(fontSize: 12, height: 1.5,
              color: Color(0xFF586B75)))),
        ],
      ),
    );
  }
}

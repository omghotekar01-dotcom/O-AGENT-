import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/controller.dart';
import 'ios_components.dart';

/// View-only, explicitly consented live screen previews. No mouse or keyboard
/// injection, no background capture, no saved screenshots, no browser takeover.
class ScreenPreviewScreen extends StatefulWidget {
  const ScreenPreviewScreen({super.key, required this.controller});
  final ControlController controller;
  @override State<ScreenPreviewScreen> createState() => _ScreenPreviewState();
}
class _ScreenPreviewState extends State<ScreenPreviewScreen> {
  Timer? timer;
  Map<String, dynamic>? status;
  Uint8List? frame;
  String? error;
  bool loading = false, stopping = false;
  @override void initState() {
    super.initState();
    _refresh();
    timer = Timer.periodic(const Duration(milliseconds: 1400), (_) => _refresh());
  }
  @override void dispose() { timer?.cancel(); super.dispose(); }
  Future<void> _refresh() async {
    if (loading || !mounted) return;
    final api = widget.controller.client;
    if (api == null) return;
    loading = true;
    try {
      final current = await api.screenStatus();
      final jpeg = current['fresh'] == true ? await api.screenFrame() : null;
      if (mounted && api == widget.controller.client) {
        setState(() {
          status = current;
          frame = jpeg;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally { loading = false; }
  }
  Future<void> _stop() async {
    if (stopping) return;
    final agreed = await showDialog<bool>(context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Stop screen sharing?'),
        content: const Text('This immediately revokes the active capture '
          'lease and prevents further frames from appearing on your phone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep sharing')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Stop sharing')),
        ]));
    if (agreed != true || !mounted) return;
    setState(() => stopping = true);
    try {
      await widget.controller.client?.stopScreenShare();
      if (mounted) setState(() => frame = null);
    } catch (e) { if (mounted) setState(() => error = e.toString()); }
    finally { if (mounted) setState(() => stopping = false); }
    await _refresh();
  }
  Future<void> _copyLink() async {
    final api = widget.controller.client;
    if (api == null) return;
    final uri = api.endpoint.resolve('/screen-capture').toString();
    await Clipboard.setData(ClipboardData(text: uri));
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Screen picker URL copied. Open it on your laptop.')));
  }
  @override Widget build(BuildContext context) {
    final live = status?['capturing'] == true && status?['fresh'] == true;
    final sharing = status?['capturing'] == true;
    return Scaffold(backgroundColor: OVisual.canvas(context),
      appBar: AppBar(title: const Text('View desktop'), actions: [
        IconButton(tooltip: 'Refresh preview', onPressed: _refresh,
          icon: const Icon(CupertinoIcons.refresh)),
      ]),
      body: SafeArea(child: Center(child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: ListView(padding: const EdgeInsets.fromLTRB(19, 14, 19, 34),
          children: [
            const OScreenTitle(eyebrow: 'Private view-only preview',
              title: 'See what is on screen.',
              subtitle: 'Only the window or display explicitly chosen '
                'on your laptop is visible here. No remote input or hidden recording.'),
            const SizedBox(height: 19),
            OSurface(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(CupertinoIcons.desktopcomputer, color: OVisual.primary),
                  const SizedBox(width: 11),
                  Expanded(child: Text('Consented screen session',
                    style: TextStyle(fontWeight: FontWeight.w700,
                      color: OVisual.label(context)))),
                  OStatePill(live ? 'online' : sharing ? 'waiting' : 'offline',
                    label: live ? 'Live preview' : sharing ? 'Waiting for frames'
                      : 'Not sharing'),
                ]),
                const SizedBox(height: 15),
                Container(
                  constraints: const BoxConstraints(minHeight: 180),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(13),
                    color: const Color(0xFF17171E)),
                  clipBehavior: Clip.antiAlias,
                  child: frame == null
                    ? const Center(child: Padding(
                      padding: EdgeInsets.all(32),
                      child: Text('No consented preview is available.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.white70))))
                    : Image.memory(frame!, fit: BoxFit.contain,
                      gaplessPlayback: true,
                      errorBuilder: (_, __, ___) =>
                        const Center(child: Text('Preview could not be decoded.'))),
                ),
                if (status?['lastFrameAt'] != null) Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text('Last frame: ' + status!['lastFrameAt'].toString(),
                    style: TextStyle(color: OVisual.muted(context), fontSize: 11))),
                if (error != null) Padding(padding: const EdgeInsets.only(top: 10),
                  child: Text(error!, style: const TextStyle(
                    color: OVisual.rose, fontSize: 12))),
                const SizedBox(height: 13),
                Wrap(spacing: 9, runSpacing: 9, children: [
                  FilledButton.tonalIcon(onPressed: _copyLink,
                    icon: const Icon(CupertinoIcons.link, size: 18),
                    label: const Text('Copy laptop sharing URL')),
                  if (sharing) OutlinedButton.icon(
                    onPressed: stopping ? null : _stop,
                    icon: const Icon(CupertinoIcons.stop_circle, size: 18),
                    label: const Text('Stop immediately')),
                ]),
              ])),
            const OSectionTitle('How to start'),
            const OIconTile(icon: CupertinoIcons.hand_raised,
              title: '1. Open the copied URL on your laptop',
              subtitle: 'Use a modern browser on your trusted HTTPS O-AGENT '
                'backend. Enter your existing owner token on the laptop.'),
            const SizedBox(height: 10),
            const OIconTile(icon: CupertinoIcons.rectangle_on_rectangle,
              title: '2. Choose the exact screen or window',
              subtitle: 'Your browser asks for consent and displays its own '
                'sharing indicator. Audio capture is disabled.'),
            const SizedBox(height: 10),
            const OIconTile(icon: CupertinoIcons.lock_shield,
              title: '3. Inspect and stop whenever needed',
              subtitle: 'Preview JPEGs stay in server memory for only a few '
                'seconds. Stop on laptop or revoke sharing here on mobile.'),
          ])),
      )),
    );
  }
}

import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/controller.dart';

/// Fullscreen viewer for an explicitly shared Windows desktop. Touch input is
/// DISABLED until a visible local companion is paired with a one-time code.
/// Never attaches to a browser's account/session or silently captures a screen.
class RemoteFullscreenScreen extends StatefulWidget {
  const RemoteFullscreenScreen({super.key, required this.controller});
  final ControlController controller;

  @override
  State<RemoteFullscreenScreen> createState() => _RemoteFullscreenState();
}

class _RemoteFullscreenState extends State<RemoteFullscreenScreen> {
  Timer? _poller;
  Uint8List? _frame;
  Map<String, dynamic>? _sharing;
  Map<String, dynamic>? _input;
  final _text = TextEditingController();
  bool _loading = false;
  bool _control = false;
  bool _sending = false;
  String? _error;
  int _lastMoveMs = 0;

  bool get _paired => _input?['paired'] == true;
  bool get _fresh => _sharing?['fresh'] == true;
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _refresh();
    _poller = Timer.periodic(const Duration(milliseconds: 950), (_) => _refresh());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _text.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _refresh() async {
    if (!mounted || _loading) return;
    final api = widget.controller.client;
    if (api == null) return;
    _loading = true;
    try {
      final sharing = await api.screenStatus();
      final picture = sharing['fresh'] == true ? await api.screenFrame() : null;
      final input = await api.remoteInputStatus();
      if (!mounted || widget.controller.client != api) return;
      setState(() {
        _sharing = sharing;
        _input = input;
        _frame = picture;
        if (!_paired || !_fresh) _control = false;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _loading = false;
    }
  }

  Future<void> _pair() async {
    final code = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Pair Windows remote control'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('On your laptop, keep screen sharing active and double-click REMOTE-CONTROL.cmd. Type ENABLE in its visible window. Enter the 8-digit code it displays.',
            style: TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 12),
          TextField(controller: code, autofocus: true,
            keyboardType: TextInputType.number, maxLength: 8,
            decoration: const InputDecoration(labelText: '8-digit pairing code')),
          const SizedBox(height: 8),
          const Text('Pairing permits mouse and keyboard access to the Windows desktop for 20 minutes. Anyone at your laptop can stop the companion.',
            style: TextStyle(fontSize: 12)),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, code.text.trim()),
            child: const Text('Pair')),
        ],
      ),
    );
    code.dispose();
    if (value == null || !mounted) return;
    try {
      await widget.controller.client?.pairRemoteInput(value);
      await _refresh();
      if (mounted && _paired) setState(() => _control = true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _stop() async {
    try {
      await widget.controller.client?.stopRemoteInput();
      if (mounted) setState(() => _control = false);
      await _refresh();
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send(Map<String, dynamic> action) async {
    if (!_paired || !_fresh || _sending) return;
    _sending = true;
    try {
      await widget.controller.client?.sendRemoteInput(action);
    } catch (e) {
      if (mounted && action['type'] != 'move') setState(() => _error = e.toString());
    } finally {
      _sending = false;
    }
  }

  void _move(DragUpdateDetails details) {
    if (!_control || !_paired) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastMoveMs < 70) return;
    _lastMoveMs = now;
    final dx = (details.delta.dx * 2.0).round().clamp(-150, 150);
    final dy = (details.delta.dy * 2.0).round().clamp(-150, 150);
    if (dx == 0 && dy == 0) return;
    _send({'type': 'move', 'dx': dx, 'dy': dy});
  }

  void _typeOnDesktop() {
    _text.clear();
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18,
          MediaQuery.viewInsetsOf(sheet).bottom + 22),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Type into the focused laptop window',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text('Only ordinary text. Do not enter passwords, API keys, payment details or sensitive data.',
              style: TextStyle(fontSize: 12)),
            TextField(controller: _text, maxLength: 300, autofocus: true,
              decoration: const InputDecoration(hintText: 'Text to type on laptop'),
              minLines: 1, maxLines: 3),
            FilledButton.icon(
              onPressed: () {
                final value = _text.text;
                Navigator.pop(sheet);
                if (value.isNotEmpty) _send({'type': 'text', 'text': value});
              },
              icon: const Icon(Icons.keyboard),
              label: const Text('Type on laptop')),
          ],
        )),
    );
  }

  Widget _desktopImage() {
    if (_frame == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(30),
        child: Text('Waiting for fresh images from the selected laptop display.',
          style: TextStyle(color: Colors.white70), textAlign: TextAlign.center)));
    }
    if (_control && _paired) {
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onPanUpdate: _move,
        onTap: () => _send({'type': 'click', 'button': 'left'}),
        onDoubleTap: () => _send({'type': 'click', 'button': 'double'}),
        onLongPress: () => _send({'type': 'click', 'button': 'right'}),
        child: SizedBox.expand(
          child: Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true)),
      );
    }
    return InteractiveViewer(
      minScale: 1, maxScale: 6, panEnabled: true,
      child: SizedBox.expand(
        child: Image.memory(_frame!, fit: BoxFit.contain, gaplessPlayback: true)),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.black,
    body: SafeArea(top: false, bottom: false, child: Stack(children: [
      Positioned.fill(child: _desktopImage()),
      Positioned(left: 10, right: 10, top: 24,
        child: DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xDD15151B),
            borderRadius: BorderRadius.circular(16)),
          child: Padding(padding: const EdgeInsets.all(7), child: Row(children: [
            IconButton(
              tooltip: 'Close full screen', onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white)),
            Expanded(child: Text(
              _control ? 'Remote input ON' : 'Fullscreen view · pinch to zoom',
              style: const TextStyle(color: Colors.white, fontSize: 12))),
            if (_paired) TextButton(
              onPressed: () => setState(() => _control = !_control),
              child: Text(_control ? 'View' : 'Control',
                style: const TextStyle(color: Colors.white))),
            if (!_paired) TextButton(
              onPressed: _pair, child: const Text('Pair control',
                style: TextStyle(color: Colors.white))),
          ]))),
      ),
      Positioned(left: 10, right: 10, bottom: 18,
        child: DecoratedBox(
          decoration: BoxDecoration(color: const Color(0xE915151B),
            borderRadius: BorderRadius.circular(16)),
          child: Padding(padding: const EdgeInsets.all(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              if (_error != null) Padding(padding: const EdgeInsets.all(7),
                child: Text(_error!, style: const TextStyle(
                  color: Color(0xFFFFA89A), fontSize: 11))),
              if (!_fresh) const Padding(padding: EdgeInsets.all(6),
                child: Text('No fresh screen frame. Remote input is disabled.',
                  style: TextStyle(color: Colors.orangeAccent, fontSize: 11))),
              if (_paired && _control) ...[
                const Text('Drag: pointer · Tap: click · Long press: right click · Double tap: double click',
                  style: TextStyle(color: Colors.white70, fontSize: 10),
                  textAlign: TextAlign.center),
                SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    IconButton(tooltip: 'Scroll up', onPressed: () =>
                      _send({'type': 'scroll', 'steps': 1}),
                      icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white)),
                    IconButton(tooltip: 'Scroll down', onPressed: () =>
                      _send({'type': 'scroll', 'steps': -1}),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white)),
                    IconButton(tooltip: 'Type text', onPressed: _typeOnDesktop,
                      icon: const Icon(Icons.keyboard, color: Colors.white)),
                    TextButton(onPressed: () => _send({'type': 'key', 'key': 'enter'}),
                      child: const Text('Enter', style: TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => _send({'type': 'key', 'key': 'backspace'}),
                      child: const Text('⌫', style: TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => _send({'type': 'key', 'key': 'escape'}),
                      child: const Text('Esc', style: TextStyle(color: Colors.white))),
                    TextButton(onPressed: _stop,
                      child: const Text('Stop control',
                        style: TextStyle(color: Colors.orangeAccent))),
                  ])),
              ] else Text(_paired
                ? 'Control paired. Tap Control above to use the virtual trackpad.'
                : 'View only. Pair a visible Windows helper for pointer/keyboard input.',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                textAlign: TextAlign.center),
            ]),
          )),
      ),
    ])),
  );
}

import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/controller.dart';
import '../core/api_client.dart';

/// Fullscreen viewer for an explicitly shared Windows desktop. Touch input is
/// DISABLED until a locally trusted visible companion is explicitly activated
/// by the owner, or a legacy short-lived pairing code is confirmed.
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
  bool _connecting = false;
  String? _error;
  int _frameSequence = -1;
  int _pollCount = 0;
  double _pointerSpeed = 1.5;
  double _residualX = 0, _residualY = 0;
  final List<Map<String, dynamic>> _actions = [];

  bool get _paired => _input?['paired'] == true;
  bool get _fresh => _sharing?['fresh'] == true;
  @override
  void initState() {
    super.initState();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    _refresh();
    _poller = Timer.periodic(const Duration(milliseconds: 450), (_) => _refresh());
  }

  @override
  void dispose() {
    _poller?.cancel();
    _actions.clear();
    _text.dispose();
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  Future<void> _refresh({bool force = false}) async {
    if (!mounted || _loading) return;
    final api = widget.controller.client;
    if (api == null) return;
    _loading = true;
    try {
      // Refresh metadata every ~2 seconds; request only JPEGs with a newer
      // sequence in between. This avoids three full HTTP round-trips and
      // repeated decoding for every preview tick.
      final metadata = force || _sharing == null || (_pollCount++ % 4 == 0);
      final sharing = metadata ? await api.screenStatus() : _sharing!;
      final input = metadata ? await api.remoteInputStatus() : _input;
      final picture = sharing['fresh'] == true
        ? await api.screenFrameUpdate(after: _frameSequence) : null;
      if (!mounted || widget.controller.client != api) return;
      setState(() {
        _sharing = sharing;
        if (input != null) _input = input;
        if (picture != null) {
          _frame = picture.bytes;
          _frameSequence = picture.sequence;
        } else if (sharing['fresh'] != true) {
          _frame = null;
          _frameSequence = -1;
        }
        if (!_paired || !_fresh) {
          _control = false;
          _actions.clear();
        }
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      _loading = false;
    }
  }

  Future<void> _activate() async {
    if (_connecting) return;
    if (!_fresh) {
      setState(() => _error =
        'The laptop is not sending live screen frames. Select a screen on your laptop first.');
      return;
    }
    if (_input?['trustedReady'] != true && _input?['trustedMode'] != true) {
      if (!mounted) return;
      final legacy = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable one-tap control once'),
          content: const Text(
            'On the trusted laptop, run ENABLE-ONE-TAP-CONTROL.cmd '
            'and choose ENABLE. Restart O-AGENT.cmd once. '
            'The visible Windows helper will then start automatically. '
            'After that, press Control here—no eight-digit codes. '
            'A temporary manual pairing option is available for older setups.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Not now')),
            TextButton(onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Temporary code instead')),
          ],
        ),
      );
      if (legacy == true && mounted) await _legacyPair();
      return;
    }
    setState(() => _connecting = true);
    try {
      final api = widget.controller.client;
      if (api == null) throw const ApiException('Backend is not connected');
      final result = await api.activateTrustedRemoteInput();
      if (!mounted) return;
      setState(() {
        _input = result;
        _control = result['paired'] == true;
        _error = _control ? null : 'The laptop did not confirm remote input activation.';
      });
      await _refresh(force: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _legacyPair() async {
    String codeInput = '';
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Temporary Windows pairing'),
        content: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('On the laptop, start REMOTE-CONTROL.cmd, type ENABLE, '
            'then enter its temporary eight-digit code. '
            'For everyday use, enable trusted one-tap control instead.',
            style: TextStyle(fontSize: 13, height: 1.5)),
          const SizedBox(height: 12),
          TextField(autofocus: true, onChanged: (value) => codeInput = value,
            keyboardType: TextInputType.number, maxLength: 8,
            decoration: const InputDecoration(labelText: 'Temporary code')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, codeInput.trim()),
            child: const Text('Pair')),
        ],
      ),
    );
    if (value == null || !mounted) return;
    try {
      final result = await widget.controller.client?.pairRemoteInput(value);
      if (mounted) setState(() {
        _input = result;
        _control = result?['paired'] == true;
      });
      await _refresh(force: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _stop() async {
    try {
      await widget.controller.client?.stopRemoteInput();
      if (mounted) setState(() {
        _control = false;
        _actions.clear();
      });
      await _refresh(force: true);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  Future<void> _send(Map<String, dynamic> action) async {
    if (!_control || !_paired || !_fresh) return;
    final value = Map<String, dynamic>.from(action);
    if (value['type'] == 'move' && _actions.isNotEmpty &&
        _actions.last['type'] == 'move') {
      final prior = _actions.last;
      final dx = (prior['dx'] as int) + (value['dx'] as int);
      final dy = (prior['dy'] as int) + (value['dy'] as int);
      if (dx.abs() <= 150 && dy.abs() <= 150) {
        prior['dx'] = dx;
        prior['dy'] = dy;
      } else {
        _actions.add(value);
      }
    } else {
      _actions.add(value);
    }
    // Never discard a click, text or key. Movement is bounded by backend
    // coalescing; stop accepting extra drag samples if the network is stuck.
    if (_actions.length > 36 && value['type'] == 'move') {
      _actions.removeLast();
    }
    if (_sending) return;
    _sending = true;
    while (_actions.isNotEmpty && mounted && _control && _paired && _fresh) {
      final next = _actions.removeAt(0);
      try {
        await widget.controller.client?.sendRemoteInput(next);
      } catch (e) {
        if (e is ApiException && e.statusCode == 429) {
          // Explicit queue pacing; a rejected key/click is retried once.
          await Future<void>.delayed(const Duration(milliseconds: 75));
          try {
            await widget.controller.client?.sendRemoteInput(next);
          } catch (retryError) {
            if (mounted && next['type'] != 'move') {
              setState(() => _error = retryError.toString());
            }
          }
        } else if (mounted && next['type'] != 'move') {
          setState(() => _error = e.toString());
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 25));
    }
    _sending = false;
  }

  void _move(DragUpdateDetails details) {
    if (!_control || !_paired) return;
    // Do not drop the motion delta before coalescing: doing so used to make
    // cursor movement noticeably shorter than the actual finger drag.
    final exactX = details.delta.dx * _pointerSpeed + _residualX;
    final exactY = details.delta.dy * _pointerSpeed + _residualY;
    final dx = exactX.round().clamp(-150, 150);
    final dy = exactY.round().clamp(-150, 150);
    _residualX = exactX - dx;
    _residualY = exactY - dy;
    if (dx == 0 && dy == 0) return;
    _send({'type': 'move', 'dx': dx, 'dy': dy});
  }

  void _typeOnDesktop({bool submit = false}) {
    _text.clear();
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (sheet) => Padding(
        padding: EdgeInsets.fromLTRB(18, 12, 18,
          MediaQuery.viewInsetsOf(sheet).bottom + 22),
        child: Column(mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(submit ? 'Send a prompt to the focused AI app'
              : 'Type into the focused laptop window',
              style: const TextStyle(fontSize: 18,
                fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Text(submit
              ? 'First tap the actual ChatGPT, VS Code, Copilot or other text '
                'field on the shared screen. The phone will type this prompt '
                'and press Enter. Review the exact text before sending.'
              : 'Only ordinary text. Do not enter passwords, API keys, payment '
                'details or sensitive data.',
              style: const TextStyle(fontSize: 12)),
            TextField(controller: _text, maxLength: 300, autofocus: true,
              decoration: const InputDecoration(hintText: 'Text to type on laptop'),
              minLines: 1, maxLines: 3),
            FilledButton.icon(
              onPressed: () {
                final value = _text.text;
                Navigator.pop(sheet);
                if (value.isNotEmpty) {
                  _send({'type': 'text', 'text': value});
                  if (submit) _send({'type': 'key', 'key': 'enter'});
                }
              },
              icon: const Icon(Icons.keyboard),
              label: Text(submit ? 'Send prompt & Enter' : 'Type on laptop')),
          ],
        )),
    );
  }

  /// Translate a touch on the letterboxed JPEG into normalized monitor
  /// coordinates. A window/tab share falls back to relative trackpad clicks.
  /// Windows independently rejects absolute clicks on multiple monitors.
  void _tapAt(Offset local, Size view, String button) {
    if (!_control || !_paired || !_fresh) return;
    final sourceW = (_sharing?['sourceWidth'] as num?)?.toDouble() ?? 0;
    final sourceH = (_sharing?['sourceHeight'] as num?)?.toDouble() ?? 0;
    if (_sharing?['displaySurface'] != 'monitor' ||
        sourceW <= 0 || sourceH <= 0 ||
        view.width <= 0 || view.height <= 0) {
      _send({'type': 'click', 'button': button});
      return;
    }
    final scale = math.min(view.width / sourceW, view.height / sourceH);
    final drawnW = sourceW * scale, drawnH = sourceH * scale;
    final left = (view.width - drawnW) / 2;
    final top = (view.height - drawnH) / 2;
    if (local.dx < left || local.dy < top ||
        local.dx > left + drawnW || local.dy > top + drawnH) return;
    final x = (((local.dx - left) / drawnW) * 10000).round()
      .clamp(0, 10000);
    final y = (((local.dy - top) / drawnH) * 10000).round()
      .clamp(0, 10000);
    _send({'type': 'tap', 'x': x, 'y': y, 'button': button});
  }

  Widget _desktopImage() {
    if (_frame == null) {
      return const Center(child: Padding(
        padding: EdgeInsets.all(30),
        child: Text('Waiting for fresh images from the selected laptop display.',
          style: TextStyle(color: Colors.white70), textAlign: TextAlign.center)));
    }
    if (_control && _paired) {
      return LayoutBuilder(builder: (context, limits) {
        final view = Size(limits.maxWidth, limits.maxHeight);
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onPanUpdate: _move,
          onTapUp: (details) =>
            _tapAt(details.localPosition, view, 'left'),
          onDoubleTapDown: (details) =>
            _tapAt(details.localPosition, view, 'double'),
          onDoubleTap: () {},
          onLongPressStart: (details) =>
            _tapAt(details.localPosition, view, 'right'),
          child: SizedBox.expand(
            child: Image.memory(_frame!, fit: BoxFit.contain,
              gaplessPlayback: true)),
        );
      });
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
              onPressed: _control ? _stop : _activate,
              child: Text(_control ? 'Stop input' : 'Control',
                style: const TextStyle(color: Colors.white))),
            if (!_paired) TextButton(
              onPressed: _connecting ? null : _activate,
              child: Text(_connecting ? 'Connecting...' :
                (_input?['trustedReady'] == true ? 'Control' : 'Set up control'),
                style: const TextStyle(color: Colors.white))),
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
                Text('Actual screen capture: ${_sharing?['estimatedFps'] ?? 'measuring'} fps · '
                  'Windows input queue: ${_input?['queueDepth'] ?? 0}',
                  style: const TextStyle(color: Colors.white70,
                    fontSize: 10)),
                if (_input?['lastInputResult'] is Map)
                  Padding(padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: Text(
                      (_input!['lastInputResult']['ok'] == true
                        ? 'Windows executed the last '
                        : 'Windows rejected the last ') +
                      (_input!['lastInputResult']['type']?.toString() ??
                        'input action') +
                      (_input!['lastInputResult']['ok'] == true
                        ? '' : ' · check active window focus/permissions'),
                      style: TextStyle(
                        color: _input!['lastInputResult']['ok'] == true
                          ? Colors.lightGreenAccent : Colors.orangeAccent,
                        fontSize: 10))),
                const SizedBox(height: 5),
                Text(_sharing?['displaySurface'] == 'monitor'
                  ? 'Tap the shared screen to click that point (single-monitor laptops). '
                    'Drag to move the cursor. Long press right-clicks.'
                  : 'Drag to move the cursor. In window/tab sharing, '
                    'tap clicks at the current pointer position.',

                  style: TextStyle(color: Colors.white70, fontSize: 10),
                  textAlign: TextAlign.center),
                Row(children: [
                  const Text('Cursor speed', style: TextStyle(
                    color: Colors.white70, fontSize: 11)),
                  Expanded(child: Slider(value: _pointerSpeed, min: .5,
                    max: 3.0, divisions: 10,
                    label: _pointerSpeed.toStringAsFixed(1),
                    onChanged: (value) =>
                      setState(() => _pointerSpeed = value))),
                  Text('${_pointerSpeed.toStringAsFixed(1)}×',
                    style: const TextStyle(color: Colors.white70,
                      fontSize: 11)),
                ]),
                SingleChildScrollView(scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    IconButton(tooltip: 'Scroll up', onPressed: () =>
                      _send({'type': 'scroll', 'steps': 1}),
                      icon: const Icon(Icons.keyboard_arrow_up, color: Colors.white)),
                    IconButton(tooltip: 'Scroll down', onPressed: () =>
                      _send({'type': 'scroll', 'steps': -1}),
                      icon: const Icon(Icons.keyboard_arrow_down, color: Colors.white)),
                    FilledButton.icon(
                      onPressed: () => _typeOnDesktop(submit: true),
                      icon: const Icon(Icons.send, size: 17),
                      label: const Text('Send prompt')),
                    IconButton(tooltip: 'Type text without Enter',
                      onPressed: () => _typeOnDesktop(),
                      icon: const Icon(Icons.keyboard, color: Colors.white)),
                    TextButton(onPressed: () => _send({'type': 'key', 'key': 'enter'}),
                      child: const Text('Enter', style: TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => _send({'type': 'key', 'key': 'backspace'}),
                      child: const Text('⌫', style: TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => _send({'type': 'key', 'key': 'escape'}),
                      child: const Text('Esc', style: TextStyle(color: Colors.white))),
                    for (final shortcut in const {
                      'copy':'Copy', 'paste':'Paste', 'undo':'Undo',
                      'select_all':'Select all', 'save':'Save',
                    }.entries)
                      TextButton(
                        onPressed: () => _send({'type':'shortcut',
                          'name':shortcut.key}),
                        child: Text(shortcut.value,
                          style: const TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => _send({'type': 'key', 'key': 'tab'}),
                      child: const Text('Tab', style: TextStyle(color: Colors.white))),
                    for (final key in const ['left','up','down','right'])
                      IconButton(tooltip: 'Arrow $key',
                        onPressed: () => _send({'type': 'key', 'key': key}),
                        icon: Icon(key == 'left' ? Icons.arrow_left :
                          key == 'right' ? Icons.arrow_right :
                          key == 'up' ? Icons.arrow_drop_up :
                          Icons.arrow_drop_down, color: Colors.white)),
                    TextButton(onPressed: _stop,
                      child: const Text('Stop control',
                        style: TextStyle(color: Colors.orangeAccent))),
                  ])),
              ] else Text(_paired
                ? 'Control paired. Tap Control above to use the virtual trackpad.'
                : _input?['trustedReady'] == true
                  ? 'Laptop ready. Tap Control above to start a time-limited session.'
                  : 'View only. Enable trusted one-tap control on your laptop once.',
                style: const TextStyle(color: Colors.white70, fontSize: 11),
                textAlign: TextAlign.center),
            ]),
          )),
      ),
    ])),
  );
}

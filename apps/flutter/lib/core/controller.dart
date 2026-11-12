import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import 'api_client.dart';
import 'models.dart';

/// Coordinates actual state from the backend; no prefilled records or demo mode.
class ControlController extends ChangeNotifier with WidgetsBindingObserver {
  AgentApi? _api;
  Timer? _poller;
  int _generation = 0;
  bool _busyRefreshing = false;

  String? endpoint;
  String? error;
  ControlSnapshot? snapshot;
  List<DomainEvent> events = const [];
  String? selectedMachineId;
  DateTime? lastSuccessfulSync;
  int _cursor = 0;
  bool connecting = false;
  bool acting = false;
  bool refreshing = false;

  bool get connected => _api != null && snapshot != null;
  bool get hasMachineOnline => snapshot?.machines.any((m) => m.online) ?? false;
  Machine? get selectedMachine {
    for (final machine in snapshot?.machines ?? const <Machine>[]) {
      if (machine.id == selectedMachineId) return machine;
    }
    return null;
  }

  ControlController() {
    WidgetsBinding.instance.addObserver(this);
  }

  Future<bool> connect(String origin, String token) async {
    if (connecting) return false;
    final generation = ++_generation;
    connecting = true;
    error = null;
    notifyListeners();
    AgentApi? pending;
    try {
      pending = AgentApi(origin, token.trim());
      final state = await pending.readState();
      if (generation != _generation) {
        pending.close();
        return false;
      }
      _api?.close();
      _api = pending;
      endpoint = pending.endpoint.toString();
      snapshot = state;
      selectedMachineId = null;
      events = const [];
      _cursor = 0;
      lastSuccessfulSync = DateTime.now();
      _poller?.cancel();
      _poller = Timer.periodic(const Duration(seconds: 5), (_) => refresh());
      connecting = false;
      notifyListeners();
      await refresh();
      return true;
    } catch (e) {
      pending?.close();
      if (generation == _generation) {
        error = e.toString();
        connecting = false;
        notifyListeners();
      }
      return false;
    }
  }

  void selectMachine(String id) {
    if (snapshot?.machines.any((m) => m.id == id && m.online) != true) return;
    selectedMachineId = id;
    notifyListeners();
  }

  Future<void> refresh() async {
    final api = _api;
    if (api == null || _busyRefreshing) return;
    final generation = _generation;
    _busyRefreshing = true;
    refreshing = true;
    notifyListeners();
    try {
      final state = await api.readState();
      if (generation != _generation) return;
      snapshot = state;
      lastSuccessfulSync = DateTime.now();
      error = null;
      if (selectedMachineId != null && state.machines.every((m) => m.id != selectedMachineId || !m.online)) {
        selectedMachineId = null;
      }
      // Fetch incremental events; backend limits each page to 200.
      for (var page = 0; page < 5; page++) {
        final newEvents = await api.readEvents(after: _cursor);
        if (generation != _generation) return;
        if (newEvents.isEmpty) break;
        final known = events.map((e) => e.id).toSet();
        final unique = newEvents.where((e) => !known.contains(e.id)).toList();
        events = [...events, ...unique];
        if (events.length > 150) events = events.sublist(events.length - 150);
        _cursor = newEvents.last.sequence;
        if (newEvents.length < 200) break;
      }
    } catch (e) {
      if (generation == _generation) error = e.toString();
    } finally {
      if (generation == _generation) {
        _busyRefreshing = false;
        refreshing = false;
        notifyListeners();
      }
    }
  }

  Future<bool> _action(Future<void> Function(AgentApi api) action) async {
    final api = _api;
    if (api == null || acting) return false;
    acting = true;
    error = null;
    notifyListeners();
    try {
      await action(api);
      await refresh();
      return true;
    } catch (e) {
      error = e.toString();
      notifyListeners();
      return false;
    } finally {
      acting = false;
      notifyListeners();
    }
  }

  Future<bool> requestSystemInfo(String workerId) => _action((api) => api.submitTask(workerId: workerId, kind: 'system_info'));

  Future<bool> requestInventory(String workerId) => _action((api) => api.submitTask(workerId: workerId, kind: 'workspace_inventory'));

  Future<bool> resolveApproval(String taskId, bool approve) => _action((api) => api.decide(taskId, approve: approve));

  Future<bool> cancelTask(String taskId) => _action((api) => api.cancel(taskId));

  void clearError() {
    error = null;
    notifyListeners();
  }

  void disconnect() {
    _generation++;
    _poller?.cancel();
    _api?.close();
    _api = null;
    endpoint = null;
    error = null;
    snapshot = null;
    events = const [];
    selectedMachineId = null;
    lastSuccessfulSync = null;
    connecting = false;
    acting = false;
    refreshing = false;
    _busyRefreshing = false;
    _cursor = 0;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && connected) refresh();
  }

  @override
  void dispose() {
    _poller?.cancel();
    _api?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

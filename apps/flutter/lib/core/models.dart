/// Server-authoritative data models. No mock data or hard-coded agent counts.
class Machine {
  const Machine({
    required this.id,
    required this.name,
    required this.status,
    required this.lastSeenAt,
  });

  final String id;
  final String name;
  final String status;
  final DateTime? lastSeenAt;

  bool get online => status == 'online';

  factory Machine.fromJson(Map<String, dynamic> json) => Machine(
        id: json['id']?.toString() ?? '',
        name: json['name']?.toString() ?? 'Unnamed machine',
        status: json['status']?.toString() ?? 'offline',
        lastSeenAt: _date(json['lastSeenAt'], unixMilliseconds: true),
      );
}

class AgentTask {
  const AgentTask({
    required this.id,
    required this.workerId,
    required this.kind,
    required this.status,
    required this.createdAt,
    this.result,
    this.error,
    this.parameters,
    this.approvals,
  });

  final String id;
  final String workerId;
  final String kind;
  final String status;
  final DateTime? createdAt;
  final Object? result;
  final String? error;
  final Map<String, dynamic>? parameters;
  final Map<String, dynamic>? approvals;

  bool get awaitingApproval => status == 'waiting_for_approval';
  bool get cancellable => status == 'queued' || status == 'waiting_for_approval';
  bool get running => status == 'running';
  bool get terminal => const {'completed', 'failed', 'cancelled', 'rejected', 'interrupted'}.contains(status);

  String get title {
    switch (kind) {
      case 'system_info':
        return 'System health report';
      case 'workspace_inventory':
        return 'Workspace inventory';
      case 'codex_cloud_submit':
        return 'Submit new Codex Cloud task';
      case 'codex_cli_turn':
        return 'Run a real Codex CLI session turn';
      default:
        return kind.replaceAll('_', ' ');
    }
  }

  factory AgentTask.fromJson(Map<String, dynamic> json) => AgentTask(
        id: json['id']?.toString() ?? '',
        workerId: json['workerId']?.toString() ?? '',
        kind: json['kind']?.toString() ?? '',
        status: json['status']?.toString() ?? 'unknown',
        createdAt: _date(json['createdAt'], unixMilliseconds: true),
        result: json['result'],
        error: json['error']?.toString(),
        parameters: json['parameters'] is Map ? Map<String, dynamic>.from(json['parameters'] as Map) : null,
        approvals: json['approvals'] is Map ? Map<String, dynamic>.from(json['approvals'] as Map) : null,
      );
}

class DomainEvent {
  const DomainEvent({
    required this.id,
    required this.sequence,
    required this.type,
    required this.at,
    this.workerId,
    this.taskId,
  });

  final String id;
  final int sequence;
  final String type;
  final DateTime? at;
  final String? workerId;
  final String? taskId;

  factory DomainEvent.fromJson(Map<String, dynamic> json) => DomainEvent(
        id: json['id']?.toString() ?? '',
        sequence: (json['sequence'] as num?)?.toInt() ?? 0,
        type: json['type']?.toString() ?? 'unknown',
        at: _date(json['at']),
        workerId: json['workerId']?.toString(),
        taskId: json['taskId']?.toString(),
      );
}

class ControlSnapshot {
  const ControlSnapshot({
    required this.machines,
    required this.tasks,
    required this.nextSequence,
  });

  final List<Machine> machines;
  final List<AgentTask> tasks;
  final int nextSequence;

  int get onlineCount => machines.where((m) => m.online).length;
  int get runningCount => tasks.where((t) => t.running).length;
  int get pendingCount => tasks.where((t) => t.awaitingApproval).length;
  int get completedCount => tasks.where((t) => t.status == 'completed').length;

  factory ControlSnapshot.fromJson(Map<String, dynamic> json) {
    final rawWorkers = json['workers'];
    final rawTasks = json['tasks'];
    if (rawWorkers is! List || rawTasks is! List) {
      throw const FormatException('Invalid control-plane snapshot response');
    }
    return ControlSnapshot(
      machines: rawWorkers.map((e) => Machine.fromJson(Map<String, dynamic>.from(e as Map))).toList(growable: false),
      tasks: rawTasks.map((e) => AgentTask.fromJson(Map<String, dynamic>.from(e as Map))).toList(growable: false),
      nextSequence: (json['nextSequence'] as num?)?.toInt() ?? 1,
    );
  }
}

DateTime? _date(Object? value, {bool unixMilliseconds = false}) {
  if (value == null) return null;
  if (unixMilliseconds && value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true).toLocal();
  }
  return DateTime.tryParse(value.toString())?.toLocal();
}

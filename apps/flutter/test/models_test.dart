import 'package:flutter_test/flutter_test.dart';
import 'package:o_agent_mobile/core/models.dart';

void main() {
  test('workers and tasks reflect real server fields', () {
    final snapshot = ControlSnapshot.fromJson({
      'workers': [
        {'id': 'laptop', 'name': 'Laptop', 'status': 'online', 'lastSeenAt': 1794471000000},
        {'id': 'offline', 'name': 'Old worker', 'status': 'offline', 'lastSeenAt': 1794460000000},
      ],
      'tasks': [
        {'id': 'task1', 'workerId': 'laptop', 'kind': 'workspace_inventory',
         'status': 'waiting_for_approval', 'createdAt': 1794471000000},
        {'id': 'task2', 'workerId': 'laptop', 'kind': 'system_info',
         'status': 'completed', 'createdAt': 1794471000000, 'result': {'cpuCount': 8}},
        {'id': 'task3', 'workerId': 'laptop', 'kind': 'system_info',
         'status': 'running', 'createdAt': 1794471000000},
      ],
      'nextSequence': 5,
    });
    expect(snapshot.machines.length, 2);
    expect(snapshot.onlineCount, 1);
    expect(snapshot.pendingCount, 1);
    expect(snapshot.runningCount, 1);
    expect(snapshot.completedCount, 1);
    expect(snapshot.tasks.first.awaitingApproval, isTrue);
    expect(snapshot.tasks.first.cancellable, isTrue);
    expect(snapshot.tasks[1].cancellable, isFalse);
    expect((snapshot.tasks[1].result as Map)['cpuCount'], 8);
  });

  test('invalid server response is rejected instead of inventing empty data', () {
    expect(() => ControlSnapshot.fromJson({'workers': 'not-a-list', 'tasks': []}), throwsFormatException);
  });

  test('event timestamps and sequences parse reliably', () {
    final event = DomainEvent.fromJson({
      'id': 'e-1', 'sequence': 17, 'type': 'task.completed',
      'at': '2026-11-12T10:00:00Z', 'taskId': 'task1',
    });
    expect(event.sequence, 17);
    expect(event.taskId, 'task1');
    expect(event.at, isNotNull);
  });
}

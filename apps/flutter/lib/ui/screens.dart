import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../core/controller.dart';
import '../core/models.dart';
import '../theme.dart';

String readableTime(DateTime? date) {
  if (date == null) return 'Not available';
  final local = date.toLocal();
  String pad(int n) => n.toString().padLeft(2, '0');
  return '${pad(local.day)}/${pad(local.month)} ${pad(local.hour)}:${pad(local.minute)}';
}

Color taskColor(String status) {
  switch (status) {
    case 'completed':
    case 'online':
      return OTheme.aqua;
    case 'running':
      return OTheme.purple;
    case 'waiting_for_approval':
      return const Color(0xFFFFC67B);
    case 'rejected':
    case 'failed':
    case 'offline':
      return const Color(0xFFFF909D);
    default:
      return const Color(0xFFB5AEC4);
  }
}

class AgentShell extends StatefulWidget {
  const AgentShell({super.key, required this.controller});
  final ControlController controller;

  @override
  State<AgentShell> createState() => _AgentShellState();
}

class _AgentShellState extends State<AgentShell> {
  int index = 0;
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final controller = widget.controller;
        if (!controller.connected) {
          return ConnectScreen(controller: controller);
        }
        final destinations = const [
          NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.dns_outlined), selectedIcon: Icon(Icons.dns), label: 'Machines'),
          NavigationDestination(icon: Icon(Icons.task_alt_outlined), selectedIcon: Icon(Icons.task_alt), label: 'Tasks'),
          NavigationDestination(icon: Icon(Icons.verified_user_outlined), selectedIcon: Icon(Icons.verified_user), label: 'Approvals'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
        ];
        final pages = [
          OverviewScreen(controller: controller, navigateTo: (tab) => setState(() => index = tab)),
          MachinesScreen(controller: controller, navigateTo: (tab) => setState(() => index = tab)),
          TasksScreen(controller: controller),
          ApprovalsScreen(controller: controller),
          SettingsScreen(controller: controller),
        ];
        return Scaffold(
          appBar: AppBar(
            title: const Row(children: [
              Icon(Icons.auto_awesome, color: OTheme.purple, size: 23),
              SizedBox(width: 8),
              Text('O-AGENT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            ]),
            actions: [
              if (controller.refreshing)
                const Padding(padding: EdgeInsets.all(13), child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))),
              IconButton(
                tooltip: 'Refresh live backend state',
                onPressed: controller.refresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 960),
                child: Column(
                  children: [
                    if (controller.error != null)
                      MaterialBanner(
                        backgroundColor: const Color(0xFF422733),
                        content: Text(controller.error!, style: const TextStyle(color: Color(0xFFFFD1D7))),
                        leading: const Icon(Icons.warning_amber_rounded, color: Color(0xFFFFB1C0)),
                        actions: [
                          TextButton(onPressed: controller.clearError, child: const Text('Dismiss')),
                        ],
                      ),
                    Expanded(child: pages[index]),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: NavigationBar(
            selectedIndex: index,
            destinations: destinations,
            onDestinationSelected: (tab) => setState(() => index = tab),
          ),
        );
      },
    );
  }
}

class ConnectScreen extends StatefulWidget {
  const ConnectScreen({super.key, required this.controller});
  final ControlController controller;
  @override
  State<ConnectScreen> createState() => _ConnectScreenState();
}

class _ConnectScreenState extends State<ConnectScreen> {
  late final TextEditingController urlController;
  final TextEditingController tokenController = TextEditingController();
  bool obscure = true;

  @override
  void initState() {
    super.initState();
    urlController = TextEditingController(
      text: Platform.isAndroid ? 'http://10.0.2.2:8787' : 'http://127.0.0.1:8787',
    );
  }

  @override
  void dispose() {
    urlController.dispose();
    tokenController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        return Scaffold(
          body: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 490),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 60, height: 60,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(colors: [Color(0xFFAF87ED), Color(0xFF5A547D)]),
                        ),
                        child: const Icon(Icons.auto_awesome_rounded, color: Colors.white, size: 31),
                      ),
                      const SizedBox(height: 27),
                      Text('Take control of\nyour agent workspace.',
                          style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800, height: 1.15)),
                      const SizedBox(height: 12),
                      const Text('Connect to your own O-AGENT control-plane server. Only real machines, tasks, and results are displayed.',
                          style: TextStyle(color: Color(0xFFBBB6CD), height: 1.5)),
                      const SizedBox(height: 30),
                      OPanel(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Development connection', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                            const SizedBox(height: 18),
                            TextField(
                              controller: urlController,
                              keyboardType: TextInputType.url,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Backend URL',
                                hintText: 'https://your-server.example',
                                prefixIcon: Icon(Icons.language_rounded),
                              ),
                            ),
                            const SizedBox(height: 15),
                            TextField(
                              controller: tokenController,
                              obscureText: obscure,
                              autocorrect: false,
                              enableSuggestions: false,
                              decoration: InputDecoration(
                                labelText: 'Operator token',
                                prefixIcon: const Icon(Icons.key_rounded),
                                suffixIcon: IconButton(
                                  tooltip: obscure ? 'Show token' : 'Hide token',
                                  icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                                  onPressed: () => setState(() => obscure = !obscure),
                                ),
                              ),
                            ),
                            const SizedBox(height: 18),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                icon: widget.controller.connecting
                                    ? const SizedBox(width: 17, height: 17, child: CircularProgressIndicator(strokeWidth: 2))
                                    : const Icon(Icons.arrow_forward_rounded),
                                label: Text(widget.controller.connecting ? 'Connecting…' : 'Connect to O-AGENT'),
                                onPressed: widget.controller.connecting ? null : () async {
                                  final ok = await widget.controller.connect(urlController.text, tokenController.text);
                                  if (!mounted) return;
                                  if (ok) tokenController.clear();
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (widget.controller.error != null) ...[
                        const SizedBox(height: 13),
                        Text(widget.controller.error!, style: const TextStyle(color: Color(0xFFFF9AA9))),
                      ],
                      const SizedBox(height: 23),
                      const IconLabel(icon: Icons.shield_outlined, text: 'Token is kept in app memory only; it is never saved to device storage.'),
                      const SizedBox(height: 12),
                      const IconLabel(icon: Icons.info_outline, text: 'Local HTTP is allowed only in debug mode. Remote access requires trusted HTTPS.'),
                      const SizedBox(height: 12),
                      const IconLabel(icon: Icons.devices_other, text: 'Start the backend and gateway from docs/MVP_RUNBOOK.md before connecting.'),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key, required this.controller, required this.navigateTo});
  final ControlController controller;
  final ValueChanged<int> navigateTo;

  @override
  Widget build(BuildContext context) {
    final state = controller.snapshot!;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(17, 12, 17, 30),
        children: [
          Text('COMMAND CENTRE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 2, color: OTheme.purple.withValues(alpha: 0.95))),
          const SizedBox(height: 6),
          Text('Good to see you.', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Last backend sync: ${readableTime(controller.lastSuccessfulSync)}', style: const TextStyle(color: Color(0xFFAAA6B8), fontSize: 12)),
          const SizedBox(height: 18),
          OPanel(
            child: Row(children: [
              Container(
                width: 50, height: 50,
                decoration: BoxDecoration(color: const Color(0xFF302946), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.hub_rounded, color: OTheme.purple, size: 27),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Development control plane', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(state.onlineCount == 0 ? 'No active machine connection' : '${state.onlineCount} machine(s) online', style: const TextStyle(color: Color(0xFFB8B1C7), fontSize: 12)),
              ])),
              DotStatus(online: state.onlineCount > 0),
            ]),
          ),
          const SizedBox(height: 16),
          GridView.count(
            // Four columns squeeze the metric labels on many phones and
            // trigger RenderFlex overflow banners. Use two columns for
            // compact screens and a fixed height for readable content.
            crossAxisCount: MediaQuery.sizeOf(context).width >= 840 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 11,
            crossAxisSpacing: 11,
            mainAxisExtent: 116,
            children: [
              MetricTile(label: 'Machines', value: '${state.machines.length}', icon: Icons.computer_outlined, color: OTheme.purple),
              MetricTile(label: 'Online', value: '${state.onlineCount}', icon: Icons.wifi_rounded, color: OTheme.aqua),
              MetricTile(label: 'Executing', value: '${state.runningCount}', icon: Icons.play_circle_outline_rounded, color: const Color(0xFF83AFFF)),
              MetricTile(label: 'Approvals', value: '${state.pendingCount}', icon: Icons.verified_user_outlined, color: const Color(0xFFFFC67B)),
            ],
          ),
          const SizedBox(height: 24),
          const SectionTitle(title: 'Quick actions', trailing: 'Actual backend operations'),
          const SizedBox(height: 10),
          OPanel(child: Column(children: [
            ActionLine(
              icon: Icons.monitor_heart_outlined, title: 'Request system health',
              subtitle: 'CPU, memory, OS and uptime from a real worker',
              enabled: controller.selectedMachine?.online == true && !controller.acting,
              onPressed: () async {
                final m = controller.selectedMachine;
                if (m == null) return;
                final ok = await controller.requestSystemInfo(m.id);
                if (context.mounted) showActionResult(context, ok, controller);
              },
            ),
            const Divider(),
            ActionLine(
              icon: Icons.folder_open_rounded, title: 'Inspect workspace',
              subtitle: 'Requires explicit approval before listing files',
              enabled: controller.selectedMachine?.online == true && !controller.acting,
              onPressed: () async {
                final m = controller.selectedMachine;
                if (m == null) return;
                final ok = await controller.requestInventory(m.id);
                if (context.mounted) showActionResult(context, ok, controller);
              },
            ),
          ])),
          const SizedBox(height: 9),
          TextButton.icon(
            onPressed: () => navigateTo(1),
            icon: const Icon(Icons.dns_rounded),
            label: Text(controller.selectedMachine == null ? 'Choose a machine first' : 'Selected: ${controller.selectedMachine!.name}'),
          ),
          const SizedBox(height: 22),
          SectionTitle(title: 'Recent activity', actionLabel: 'All tasks', onPressed: () => navigateTo(2)),
          const SizedBox(height: 10),
          if (controller.events.isEmpty)
            const EmptyPanel(icon: Icons.history_toggle_off_rounded, title: 'No agent activity yet', detail: 'Events will appear after real machine or task operations.')
          else
            ...controller.events.reversed.take(4).map((ev) => EventRow(event: ev)),
          const SizedBox(height: 14),
          const NoticePanel(
            title: 'Agent integrations not yet enabled',
            detail: 'Provider login, AI chat, desktop streaming and cloud execution require additional backend components. No fake connections are displayed.',
          ),
        ],
      ),
    );
  }
}

class MachinesScreen extends StatelessWidget {
  const MachinesScreen({super.key, required this.controller, required this.navigateTo});
  final ControlController controller;
  final ValueChanged<int> navigateTo;

  @override
  Widget build(BuildContext context) {
    final machines = controller.snapshot!.machines;
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(17),
        children: [
          const PageHeading(title: 'Machines', subtitle: 'Enrolled development gateways. Statuses are based on backend heartbeats.'),
          if (machines.isEmpty)
            const EmptyPanel(
              icon: Icons.desktop_access_disabled_outlined,
              title: 'No machines registered',
              detail: 'Run npm run worker on your laptop with the matching server and worker tokens.',
            ),
          ...machines.map((machine) {
            final selected = controller.selectedMachineId == machine.id;
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: OPanel(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Container(padding: const EdgeInsets.all(11), decoration: BoxDecoration(color: const Color(0xFF302C41), borderRadius: BorderRadius.circular(13)), child: const Icon(Icons.laptop_mac_rounded, color: OTheme.purple)),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(machine.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                      Text(machine.id, style: const TextStyle(fontSize: 12, color: Color(0xFFABA4BA))),
                    ])),
                    StatusPill(status: machine.status),
                  ]),
                  const SizedBox(height: 13),
                  Text('Last heartbeat: ${readableTime(machine.lastSeenAt)}', style: const TextStyle(fontSize: 12, color: Color(0xFFADA9BC))),
                  const SizedBox(height: 16),
                  Row(children: [
                    Expanded(child: OutlinedButton(
                      onPressed: machine.online ? () => controller.selectMachine(machine.id) : null,
                      child: Text(selected ? 'Selected' : 'Select machine'),
                    )),
                    const SizedBox(width: 10),
                    Expanded(child: FilledButton(
                      onPressed: !machine.online || controller.acting ? null : () async {
                        controller.selectMachine(machine.id);
                        final ok = await controller.requestSystemInfo(machine.id);
                        if (context.mounted) showActionResult(context, ok, controller);
                        navigateTo(2);
                      },
                      child: const Text('Health report'),
                    )),
                  ]),
                ]),
              ),
            );
          }),
          const NoticePanel(
            title: 'Real execution boundary',
            detail: 'The gateway currently supports system information and approved top-level file inventory. It cannot start an AI agent, run arbitrary shell commands, or wake a powered-off laptop.',
          ),
        ],
      ),
    );
  }
}

class TasksScreen extends StatefulWidget {
  const TasksScreen({super.key, required this.controller});
  final ControlController controller;
  @override
  State<TasksScreen> createState() => _TasksScreenState();
}

class _TasksScreenState extends State<TasksScreen> {
  String filter = 'all';
  @override
  Widget build(BuildContext context) {
    final all = widget.controller.snapshot!.tasks;
    final filtered = all.where((task) {
      if (filter == 'running') return task.running || task.status == 'queued';
      if (filter == 'completed') return task.status == 'completed';
      if (filter == 'failed') return const {'failed', 'rejected', 'cancelled', 'interrupted'}.contains(task.status);
      return true;
    }).toList();

    return RefreshIndicator(
      onRefresh: widget.controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(17),
        children: [
          const PageHeading(title: 'Tasks', subtitle: 'Genuine task status, execution results and failure reports.'),
          OPanel(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Submit an authorized task', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: widget.controller.selectedMachine?.online == true ? widget.controller.selectedMachineId : null,
                hint: const Text('Select an online machine'),
                isExpanded: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.computer_outlined)),
                items: widget.controller.snapshot!.machines.where((m) => m.online).map(
                  (m) => DropdownMenuItem(value: m.id, child: Text(m.name, overflow: TextOverflow.ellipsis)),
                ).toList(),
                onChanged: (value) { if (value != null) widget.controller.selectMachine(value); },
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: FilledButton.tonal(
                  onPressed: widget.controller.selectedMachine?.online != true || widget.controller.acting ? null : () async {
                    final ok = await widget.controller.requestSystemInfo(widget.controller.selectedMachineId!);
                    if (context.mounted) showActionResult(context, ok, widget.controller);
                  },
                  child: const Text('System info'),
                )),
                const SizedBox(width: 9),
                Expanded(child: FilledButton(
                  onPressed: widget.controller.selectedMachine?.online != true || widget.controller.acting ? null : () async {
                    final ok = await widget.controller.requestInventory(widget.controller.selectedMachineId!);
                    if (context.mounted) showActionResult(context, ok, widget.controller);
                  },
                  child: const Text('List workspace'),
                )),
              ]),
            ]),
          ),
          const SizedBox(height: 19),
          SectionTitle(title: 'Execution history', trailing: '${all.length} records'),
          const SizedBox(height: 11),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: [
              for (final option in const ['all', 'running', 'completed', 'failed'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(option[0].toUpperCase() + option.substring(1)),
                    selected: filter == option,
                    onSelected: (_) => setState(() => filter = option),
                  ),
                ),
            ]),
          ),
          const SizedBox(height: 12),
          if (filtered.isEmpty)
            EmptyPanel(icon: Icons.task_alt_outlined, title: 'No ${filter == 'all' ? '' : '$filter '}tasks', detail: 'Submit a task using a connected machine, then watch the real status appear.')
          else
            ...filtered.map((task) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: InkWell(
                borderRadius: BorderRadius.circular(19),
                onTap: () => showTaskDetail(context, task, widget.controller),
                child: OPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(task.kind == 'system_info' ? Icons.monitor_heart_outlined : Icons.folder_outlined, color: OTheme.purple),
                    const SizedBox(width: 10),
                    Expanded(child: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700))),
                    StatusPill(status: task.status),
                  ]),
                  const SizedBox(height: 11),
                  Text('Machine: ${task.workerId}', style: const TextStyle(color: Color(0xFFABA6BD), fontSize: 12)),
                  Text('Created: ${readableTime(task.createdAt)}', style: const TextStyle(color: Color(0xFFABA6BD), fontSize: 12)),
                  if (task.error != null) ...[
                    const SizedBox(height: 8),
                    Text(task.error!, style: const TextStyle(color: Color(0xFFFF9BA6), fontSize: 12)),
                  ],
                ])),
              ),
            )),
        ],
      ),
    );
  }
}

class ApprovalsScreen extends StatelessWidget {
  const ApprovalsScreen({super.key, required this.controller});
  final ControlController controller;

  @override
  Widget build(BuildContext context) {
    final pending = controller.snapshot!.tasks.where((t) => t.awaitingApproval).toList();
    return RefreshIndicator(
      onRefresh: controller.refresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(17),
        children: [
          PageHeading(title: 'Approvals', subtitle: '${pending.length} outstanding decisions. Every approval is tied to a real backend task.'),
          const NoticePanel(
            title: 'Review before approving',
            detail: 'A workspace inventory lists top-level filenames on the target machine. It does not open files, delete data, execute commands or change software.',
          ),
          const SizedBox(height: 14),
          if (pending.isEmpty)
            const EmptyPanel(icon: Icons.verified_user_outlined, title: 'Nothing waiting', detail: 'Requests requiring your decision will appear here.')
          else
            ...pending.map((task) => Padding(
              padding: const EdgeInsets.only(bottom: 13),
              child: OPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.gpp_maybe_rounded, color: Color(0xFFFFC67B)),
                  const SizedBox(width: 9),
                  Expanded(child: Text(task.title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16))),
                  const StatusPill(status: 'waiting_for_approval'),
                ]),
                const SizedBox(height: 13),
                Text('Target machine: ${task.workerId}', style: const TextStyle(fontSize: 13)),
                const SizedBox(height: 5),
                Text('Requested: ${readableTime(task.createdAt)}', style: const TextStyle(color: Color(0xFFAAA5BC), fontSize: 12)),
                const SizedBox(height: 15),
                Row(children: [
                  Expanded(child: FilledButton(
                    onPressed: controller.acting ? null : () => decideWithConfirmation(context, task, controller, true),
                    style: FilledButton.styleFrom(backgroundColor: OTheme.aqua),
                    child: const Text('Approve'),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: OutlinedButton(
                    onPressed: controller.acting ? null : () => decideWithConfirmation(context, task, controller, false),
                    child: const Text('Reject'),
                  )),
                ]),
              ])),
            )),
        ],
      ),
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key, required this.controller});
  final ControlController controller;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(17),
      children: [
        const PageHeading(title: 'Settings', subtitle: 'Connection, privacy and capability transparency.'),
        OPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Connected backend', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 10),
          SelectableText(controller.endpoint ?? 'Not connected', style: const TextStyle(color: OTheme.aqua, fontSize: 13)),
          const SizedBox(height: 10),
          Text('Last synced: ${readableTime(controller.lastSuccessfulSync)}', style: const TextStyle(color: Color(0xFFABA5BC), fontSize: 12)),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: controller.disconnect,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Disconnect and clear session token'),
            ),
          ),
        ])),
        const SizedBox(height: 14),
        const OPanel(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Available in this development build', style: TextStyle(fontWeight: FontWeight.w700)),
          SizedBox(height: 12),
          IconLabel(icon: Icons.check_circle_outline, text: 'Read real machine heartbeat and online/offline status'),
          SizedBox(height: 10),
          IconLabel(icon: Icons.check_circle_outline, text: 'Submit system information task to connected worker'),
          SizedBox(height: 10),
          IconLabel(icon: Icons.check_circle_outline, text: 'Request approval for top-level workspace inventory'),
          SizedBox(height: 10),
          IconLabel(icon: Icons.check_circle_outline, text: 'Inspect task result, error, state and event history'),
          SizedBox(height: 10),
          IconLabel(icon: Icons.check_circle_outline, text: 'Refresh from backend and sync when app resumes'),
        ])),
        const SizedBox(height: 14),
        const NoticePanel(
          title: 'Production features not connected',
          detail: 'AI-provider chat, user accounts, credential vault, MCP, desktop screen streaming, iOS push notifications, and durable cloud tasks still require backend integrations. They are not simulated in this app.',
        ),
        const SizedBox(height: 12),
        const IconLabel(icon: Icons.lock_outline, text: 'The development operator token is held in memory and cleared on disconnect. Use HTTPS and short-lived credentials in production.'),
      ],
    );
  }
}

Future<void> decideWithConfirmation(BuildContext context, AgentTask task, ControlController controller, bool approve) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(approve ? 'Approve workspace inventory?' : 'Reject this operation?'),
      content: Text('Operation: ${task.title}\nTarget machine: ${task.workerId}\nTask: ${task.id}\n\nThis request lists top-level workspace filenames only.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: const Text('Back')),
        FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(approve ? 'Approve' : 'Reject')),
      ],
    ),
  );
  if (confirmed != true) return;
  final ok = await controller.resolveApproval(task.id, approve);
  if (context.mounted) showActionResult(context, ok, controller);
}

Future<void> showTaskDetail(BuildContext context, AgentTask task, ControlController controller) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Text(task.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 10),
          StatusPill(status: task.status),
          const SizedBox(height: 14),
          SelectableText('ID: ${task.id}\nMachine: ${task.workerId}\nStarted: ${readableTime(task.createdAt)}'),
          if (task.result != null) ...[
            const SizedBox(height: 18),
            const Text('Actual worker result', style: TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 280),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: const Color(0xFF11121B), borderRadius: BorderRadius.circular(12)),
              child: SingleChildScrollView(child: SelectableText(const JsonEncoder.withIndent('  ').convert(task.result), style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
            ),
          ],
          if (task.error != null) Padding(
            padding: const EdgeInsets.only(top: 15),
            child: SelectableText('Error: ${task.error}', style: const TextStyle(color: Color(0xFFFF9BA6))),
          ),
          if (task.cancellable) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: controller.acting ? null : () async {
                  final ok = await controller.cancelTask(task.id);
                  if (sheetContext.mounted) Navigator.pop(sheetContext);
                  if (context.mounted) showActionResult(context, ok, controller);
                },
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('Cancel pending task'),
              ),
            ),
          ],
        ]),
      ),
    ),
  );
}

void showActionResult(BuildContext context, bool ok, ControlController controller) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(ok ? 'Request accepted by the backend' : (controller.error ?? 'Request failed'))),
  );
}

// ---- Shared display primitives ----

class OPanel extends StatelessWidget {
  const OPanel({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => Card(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}

class PageHeading extends StatelessWidget {
  const PageHeading({super.key, required this.title, required this.subtitle});
  final String title;
  final String subtitle;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 20, top: 6),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
      const SizedBox(height: 6),
      Text(subtitle, style: const TextStyle(color: Color(0xFFB7B2C5), height: 1.4)),
    ]),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, this.trailing, this.actionLabel, this.onPressed});
  final String title;
  final String? trailing;
  final String? actionLabel;
  final VoidCallback? onPressed;
  @override
  Widget build(BuildContext context) => Row(children: [
    Expanded(child: Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 17))),
    if (trailing != null) Text(trailing!, style: const TextStyle(fontSize: 11, color: Color(0xFFA9A4B9))),
    if (actionLabel != null) TextButton(onPressed: onPressed, child: Text(actionLabel!)),
  ]);
}

class MetricTile extends StatelessWidget {
  const MetricTile({super.key, required this.label, required this.value, required this.icon, required this.color});
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  @override
  Widget build(BuildContext context) => OPanel(
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Row(children: [Icon(icon, color: color, size: 19), const Spacer(), Text(value, style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w800))]),
      Text(label, style: const TextStyle(color: Color(0xFFB7B2C5), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
    ]),
  );
}

class DotStatus extends StatelessWidget {
  const DotStatus({super.key, required this.online});
  final bool online;
  @override
  Widget build(BuildContext context) => Container(
    width: 10, height: 10,
    decoration: BoxDecoration(shape: BoxShape.circle, color: online ? OTheme.aqua : const Color(0xFF827E8C)),
  );
}

class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.status});
  final String status;
  @override
  Widget build(BuildContext context) {
    final color = taskColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(25)),
      child: Text(status.replaceAll('_', ' '), style: TextStyle(fontWeight: FontWeight.w700, fontSize: 10, color: color)),
    );
  }
}

class IconLabel extends StatelessWidget {
  const IconLabel({super.key, required this.icon, required this.text});
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Icon(icon, color: OTheme.purple, size: 18),
    const SizedBox(width: 9),
    Expanded(child: Text(text, style: const TextStyle(fontSize: 12, color: Color(0xFFB4AEC4), height: 1.4))),
  ]);
}

class NoticePanel extends StatelessWidget {
  const NoticePanel({super.key, required this.title, required this.detail});
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => OPanel(
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Icons.info_outline_rounded, color: Color(0xFFFFC67B), size: 22),
      const SizedBox(width: 10),
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text(detail, style: const TextStyle(fontSize: 12, height: 1.5, color: Color(0xFFB7B0C5))),
      ])),
    ]),
  );
}

class EmptyPanel extends StatelessWidget {
  const EmptyPanel({super.key, required this.icon, required this.title, required this.detail});
  final IconData icon;
  final String title;
  final String detail;
  @override
  Widget build(BuildContext context) => OPanel(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 22, horizontal: 10),
      child: Column(children: [
        Icon(icon, size: 38, color: OTheme.purple),
        const SizedBox(height: 12),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text(detail, textAlign: TextAlign.center, style: const TextStyle(color: Color(0xFFB7B0C5), fontSize: 12, height: 1.5)),
      ]),
    ),
  );
}

class ActionLine extends StatelessWidget {
  const ActionLine({super.key, required this.icon, required this.title, required this.subtitle, required this.enabled, required this.onPressed});
  final IconData icon;
  final String title;
  final String subtitle;
  final bool enabled;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: enabled ? onPressed : null,
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(children: [
        Icon(icon, color: enabled ? OTheme.purple : const Color(0xFF777180)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: enabled ? null : const Color(0xFF9993A5))),
          const SizedBox(height: 3),
          Text(subtitle, style: const TextStyle(color: Color(0xFFADA5BD), fontSize: 11)),
        ])),
        const Icon(Icons.chevron_right_rounded, size: 19),
      ]),
    ),
  );
}

class EventRow extends StatelessWidget {
  const EventRow({super.key, required this.event});
  final DomainEvent event;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 9),
    child: OPanel(
      child: Row(children: [
        const Icon(Icons.bolt_rounded, color: OTheme.aqua, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(event.type.replaceAll('.', ' · '), style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
          const SizedBox(height: 3),
          Text('Seq #${event.sequence} · ${event.workerId ?? event.taskId ?? 'system'}',
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Color(0xFFACA6BA), fontSize: 11)),
        ])),
        Text(readableTime(event.at), style: const TextStyle(color: Color(0xFFADA6BB), fontSize: 11)),
      ]),
    ),
  );
}

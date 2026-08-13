import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';

class TasksPage extends StatefulWidget {
  const TasksPage({super.key});

  @override
  State<TasksPage> createState() => _TasksPageState();
}

class _TasksPageState extends State<TasksPage> {
  List<StaffTask> _tasks = const [];
  bool _boardView = true;
  bool _createdByMe = false;
  bool _loading = false;
  Object? _error;
  bool _started = false;
  int _loadGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    final generation = ++_loadGeneration;
    final createdByMe = _createdByMe;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final tasks = await AppControllerScope.of(
        context,
      ).loadTasks(mineOnly: !createdByMe);
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _tasks = tasks;
        _loading = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  List<StaffTask> get _visibleTasks {
    final controller = AppControllerScope.of(context);
    final account = controller.account;
    if (account == null) return const [];
    bool matches(StaffTask task) {
      if (_createdByMe) {
        if (task.creatorPrincipalId != null) {
          return task.isCreatedBy(
            principalKind: account.principalKind,
            principalId: account.id,
          );
        }
        return task.creator == controller.displayName;
      }
      if (task.assigneePrincipalId != null) {
        return task.isAssignedTo(
          principalKind: account.principalKind,
          principalId: account.id,
        );
      }
      return task.assignee == controller.displayName;
    }

    return _tasks.where(matches).toList(growable: false);
  }

  bool _canTransition(StaffTask task) {
    final controller = AppControllerScope.of(context);
    final account = controller.account;
    if (account == null || account.readOnly) return false;
    final isAssignee = task.assigneePrincipalId == null
        ? task.assignee == controller.displayName
        : task.isAssignedTo(
            principalKind: account.principalKind,
            principalId: account.id,
          );
    return isAssignee ||
        controller.can('tasks:transition_any') ||
        controller.can('tasks:assign_any');
  }

  bool _canMoveTo(StaffTask task, TaskStage stage) {
    if (!_canTransition(task) || task.stage == stage) return false;
    return switch (task.stage) {
      TaskStage.todo || TaskStage.inProgress || TaskStage.blocked => true,
      TaskStage.done => stage == TaskStage.todo || stage == TaskStage.cancelled,
      TaskStage.cancelled => stage == TaskStage.todo,
    };
  }

  Future<void> _moveTask(StaffTask task, TaskStage stage) async {
    if (!_canMoveTo(task, stage)) return;
    final index = _tasks.indexWhere((item) => item.id == task.id);
    if (index < 0) return;
    final previous = _tasks[index];
    setState(() {
      _tasks[index] = task.copyWith(stage: stage);
    });
    try {
      final updated = await AppControllerScope.of(
        context,
      ).transitionTask(task, stage);
      if (!mounted) return;
      setState(() => _tasks[index] = updated);
    } catch (_) {
      if (!mounted) return;
      setState(() => _tasks[index] = previous);
      showPremiumToast(
        context,
        context.tr('taskMoveFailed'),
        icon: Icons.info_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  void _showNewTask() {
    final titleController = TextEditingController();
    final descriptionController = TextEditingController();
    var highPriority = false;
    var dueAt = DateTime.now().add(const Duration(days: 1));
    dueAt = DateTime(dueAt.year, dueAt.month, dueAt.day, 18);
    var busy = false;
    String? error;
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            2,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('addTask'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: titleController,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: context.tr('taskTitle'),
                  ),
                ),
                const SizedBox(height: 13),
                TextField(
                  controller: descriptionController,
                  minLines: 3,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: context.tr('description'),
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 13),
                PremiumCard(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 6,
                  ),
                  child: Column(
                    children: [
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.calendar_today_outlined),
                        title: Text(context.tr('dueDate')),
                        subtitle: Text(
                          DateFormat.yMMMEd(
                            AppControllerScope.of(context).locale.languageCode,
                          ).add_Hm().format(dueAt),
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: busy
                            ? null
                            : () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: dueAt,
                                  firstDate: DateTime.now(),
                                  lastDate: DateTime.now().add(
                                    const Duration(days: 730),
                                  ),
                                );
                                if (date == null || !context.mounted) return;
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(dueAt),
                                );
                                if (time == null) return;
                                setSheetState(
                                  () => dueAt = DateTime(
                                    date.year,
                                    date.month,
                                    date.day,
                                    time.hour,
                                    time.minute,
                                  ),
                                );
                              },
                      ),
                      const Divider(),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        secondary: const Icon(Icons.flag_outlined),
                        title: Text(context.tr('highPriority')),
                        value: highPriority,
                        onChanged: (value) =>
                            setSheetState(() => highPriority = value),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: busy
                        ? null
                        : () async {
                            final title = titleController.text.trim();
                            if (title.isEmpty) {
                              setSheetState(
                                () => error = context.tr('taskTitleRequired'),
                              );
                              return;
                            }
                            setSheetState(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              final created =
                                  await AppControllerScope.of(
                                    context,
                                  ).createTask(
                                    title: title,
                                    description: descriptionController.text,
                                    highPriority: highPriority,
                                    dueAt: dueAt,
                                  );
                              if (!context.mounted || !sheetContext.mounted) {
                                return;
                              }
                              setState(() => _tasks = [created, ..._tasks]);
                              Navigator.pop(sheetContext);
                              showPremiumToast(
                                context,
                                context.tr('taskCreated'),
                              );
                            } catch (_) {
                              if (!context.mounted) return;
                              setSheetState(() {
                                busy = false;
                                error = context.tr('taskCreateFailed');
                              });
                            }
                          },
                    icon: busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_task_rounded),
                    label: Text(context.tr('createTask')),
                  ),
                ),
                if (error != null) ...[
                  const SizedBox(height: 9),
                  Text(error!, style: const TextStyle(color: AppTheme.coral)),
                ],
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      titleController.dispose();
      descriptionController.dispose();
    });
  }

  void _showTask(StaffTask task) {
    final canTransition = _canTransition(task);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 2, 24, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  if (task.highPriority)
                    StatusPill(
                      label: context.tr('highPriority'),
                      color: AppTheme.coral,
                      icon: Icons.flag_rounded,
                    ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => Navigator.pop(sheetContext),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                task.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                task.description,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 22),
              _TaskMeta(
                icon: Icons.schedule_rounded,
                label: context.tr('dueDate'),
                value: _taskDueLabel(context, task.due),
              ),
              _TaskMeta(
                icon: Icons.person_outline_rounded,
                label: context.tr('assignedToMe'),
                value: task.assignee,
              ),
              _TaskMeta(
                icon: Icons.account_tree_outlined,
                label: context.tr('createdByMe'),
                value: task.creator,
              ),
              const SizedBox(height: 18),
              if (canTransition)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SegmentedButton<TaskStage>(
                    segments: TaskStage.values
                        .map(
                          (stage) => ButtonSegment(
                            value: stage,
                            enabled:
                                stage == task.stage || _canMoveTo(task, stage),
                            label: Text(_taskStageLabel(context, stage)),
                          ),
                        )
                        .toList(growable: false),
                    selected: {task.stage},
                    onSelectionChanged: (value) {
                      _moveTask(task, value.first);
                      Navigator.pop(sheetContext);
                    },
                  ),
                )
              else
                Text(
                  context.tr('taskViewOnly'),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton:
          AppControllerScope.of(context).canMutate('tasks:write')
          ? FloatingActionButton.extended(
              heroTag: 'tasks-create',
              onPressed: _showNewTask,
              icon: const Icon(Icons.add_rounded),
              label: Text(context.tr('addTask')),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MaxWidthBox(
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: PageIntro(
                  title: context.tr('myTasks'),
                  subtitle: context.trCount(
                    'openTasksCount',
                    _visibleTasks
                        .where(
                          (task) =>
                              task.stage != TaskStage.done &&
                              task.stage != TaskStage.cancelled,
                        )
                        .length,
                  ),
                  trailing: IconButton.filledTonal(
                    tooltip: context.tr('refresh'),
                    onPressed: _loadTasks,
                    icon: const Icon(Icons.refresh_rounded),
                  ),
                ),
              ),
            ),
            MaxWidthBox(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 18),
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ChoiceChip(
                          label: Text(context.tr('assignedToMe')),
                          selected: !_createdByMe,
                          onSelected: (_) {
                            if (!_createdByMe) return;
                            setState(() => _createdByMe = false);
                            _loadTasks();
                          },
                        ),
                        ChoiceChip(
                          label: Text(context.tr('createdByMe')),
                          selected: _createdByMe,
                          onSelected: (_) {
                            if (_createdByMe) return;
                            setState(() => _createdByMe = true);
                            _loadTasks();
                          },
                        ),
                      ],
                    ),
                    SegmentedButton<bool>(
                      segments: const [
                        ButtonSegment(
                          value: true,
                          icon: Icon(Icons.view_kanban_outlined),
                        ),
                        ButtonSegment(
                          value: false,
                          icon: Icon(Icons.view_list_rounded),
                        ),
                      ],
                      selected: {_boardView},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) =>
                          setState(() => _boardView = value.first),
                    ),
                  ],
                ),
              ),
            ),
            if (_error != null && _tasks.isNotEmpty)
              MaxWidthBox(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TaskRefreshWarning(onRetry: _loadTasks),
                ),
              ),
            Expanded(
              child: _loading && _tasks.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null && _tasks.isEmpty
                  ? _TasksLoadState(onRetry: _loadTasks)
                  : AnimatedSwitcher(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 350),
                      child: _boardView
                          ? _TaskBoard(
                              key: const ValueKey('board'),
                              tasks: _visibleTasks,
                              onMove: _moveTask,
                              canMove: _canMoveTo,
                              canTransition: _canTransition,
                              onOpen: _showTask,
                            )
                          : _TaskList(
                              key: const ValueKey('list'),
                              tasks: _visibleTasks,
                              onOpen: _showTask,
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskBoard extends StatelessWidget {
  const _TaskBoard({
    super.key,
    required this.tasks,
    required this.onMove,
    required this.canMove,
    required this.canTransition,
    required this.onOpen,
  });
  final List<StaffTask> tasks;
  final void Function(StaffTask task, TaskStage stage) onMove;
  final bool Function(StaffTask task, TaskStage stage) canMove;
  final bool Function(StaffTask task) canTransition;
  final ValueChanged<StaffTask> onOpen;

  @override
  Widget build(BuildContext context) {
    final stages = TaskStage.values;
    return LayoutBuilder(
      builder: (context, constraints) {
        final columnWidth = constraints.maxWidth >= 1040
            ? ((constraints.maxWidth - 40 - 48) / 5).clamp(250.0, 330.0)
            : (constraints.maxWidth - 40).clamp(260.0, 320.0);
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 100),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: stages
                  .map(
                    (stage) => Padding(
                      padding: EdgeInsetsDirectional.only(
                        end: stage == stages.last ? 0 : 12,
                      ),
                      child: SizedBox(
                        width: columnWidth,
                        child: _TaskColumn(
                          stage: stage,
                          tasks: tasks
                              .where((task) => task.stage == stage)
                              .toList(),
                          onMove: onMove,
                          canMove: canMove,
                          canTransition: canTransition,
                          onOpen: onOpen,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _TaskColumn extends StatelessWidget {
  const _TaskColumn({
    required this.stage,
    required this.tasks,
    required this.onMove,
    required this.canMove,
    required this.canTransition,
    required this.onOpen,
  });
  final TaskStage stage;
  final List<StaffTask> tasks;
  final void Function(StaffTask task, TaskStage stage) onMove;
  final bool Function(StaffTask task, TaskStage stage) canMove;
  final bool Function(StaffTask task) canTransition;
  final ValueChanged<StaffTask> onOpen;

  String _label(BuildContext context) => _taskStageLabel(context, stage);

  Color _color(BuildContext context) => switch (stage) {
    TaskStage.todo => AppTheme.coral,
    TaskStage.inProgress => Theme.of(context).colorScheme.primary,
    TaskStage.blocked => AppTheme.gold,
    TaskStage.done => AppTheme.mint,
    TaskStage.cancelled => Theme.of(context).colorScheme.outline,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    return DragTarget<StaffTask>(
      onWillAcceptWithDetails: (details) => canMove(details.data, stage),
      onAcceptWithDetails: (details) => onMove(details.data, stage),
      builder: (context, candidates, _) => AnimatedContainer(
        duration: MediaQuery.disableAnimationsOf(context)
            ? Duration.zero
            : const Duration(milliseconds: 220),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: candidates.isEmpty
              ? Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .28)
              : color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: candidates.isEmpty
                ? Colors.transparent
                : color.withValues(alpha: .4),
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(5, 4, 5, 11),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _label(context),
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(99),
                    ),
                    child: Text(
                      '${tasks.length}',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (tasks.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 30),
                child: Column(
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      color: Theme.of(context).colorScheme.outlineVariant,
                      size: 31,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      context.tr('emptyTitle'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              )
            else
              ...tasks.map(
                (task) => Padding(
                  padding: const EdgeInsets.only(bottom: 9),
                  child: canTransition(task)
                      ? LongPressDraggable<StaffTask>(
                          data: task,
                          feedback: Material(
                            color: Colors.transparent,
                            child: SizedBox(
                              width: 275,
                              child: _TaskCard(task: task, onTap: null),
                            ),
                          ),
                          childWhenDragging: Opacity(
                            opacity: .35,
                            child: _TaskCard(task: task, onTap: null),
                          ),
                          child: _TaskCard(
                            task: task,
                            onTap: () => onOpen(task),
                          ),
                        )
                      : _TaskCard(task: task, onTap: () => onOpen(task)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({required this.task, required this.onTap});
  final StaffTask task;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return PremiumCard(
      radius: 18,
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.stage == TaskStage.blocked ||
              task.stage == TaskStage.cancelled) ...[
            StatusPill(
              label: _taskStageLabel(context, task.stage),
              color: task.stage == TaskStage.blocked
                  ? AppTheme.gold
                  : Theme.of(context).colorScheme.outline,
              icon: task.stage == TaskStage.blocked
                  ? Icons.block_rounded
                  : Icons.cancel_outlined,
            ),
            const SizedBox(height: 11),
          ],
          if (task.highPriority) ...[
            StatusPill(
              label: context.tr('highPriority'),
              color: AppTheme.coral,
              icon: Icons.flag_rounded,
            ),
            const SizedBox(height: 11),
          ],
          Text(
            task.title,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 7),
          Text(
            task.description,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          if (task.tags.isNotEmpty) ...[
            const SizedBox(height: 11),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: task.tags
                  .map(
                    (tag) => StatusPill(
                      label: tag,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  )
                  .toList(),
            ),
          ],
          const SizedBox(height: 13),
          Row(
            children: [
              Icon(
                Icons.schedule_rounded,
                size: 15,
                color: task.highPriority
                    ? AppTheme.coral
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 5),
              Expanded(
                child: Text(
                  _taskDueLabel(context, task.due),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: task.highPriority
                        ? AppTheme.coral
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              PersonAvatar(name: task.creator, size: 25),
            ],
          ),
        ],
      ),
    );
  }
}

class _TaskList extends StatelessWidget {
  const _TaskList({super.key, required this.tasks, required this.onOpen});
  final List<StaffTask> tasks;
  final ValueChanged<StaffTask> onOpen;

  @override
  Widget build(BuildContext context) {
    if (tasks.isEmpty) {
      return EmptyState(
        title: context.tr('emptyTitle'),
        body: context.tr('emptyBody'),
        icon: Icons.task_alt_rounded,
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
      itemCount: tasks.length,
      separatorBuilder: (_, _) => const SizedBox(height: 9),
      itemBuilder: (context, index) => PremiumCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: () => onOpen(tasks[index]),
        child: Row(
          children: [
            Checkbox(
              value: tasks[index].stage == TaskStage.done
                  ? true
                  : tasks[index].stage == TaskStage.cancelled
                  ? null
                  : false,
              tristate: true,
              onChanged: null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tasks[index].title,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _taskDueLabel(context, tasks[index].due),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (tasks[index].stage == TaskStage.blocked ||
                      tasks[index].stage == TaskStage.cancelled) ...[
                    const SizedBox(height: 5),
                    Text(
                      _taskStageLabel(context, tasks[index].stage),
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: tasks[index].stage == TaskStage.blocked
                            ? AppTheme.gold
                            : Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (tasks[index].highPriority)
              const Icon(Icons.flag_rounded, color: AppTheme.coral, size: 19),
            const SizedBox(width: 7),
            const Icon(Icons.chevron_right_rounded),
          ],
        ),
      ),
    );
  }
}

class _TaskMeta extends StatelessWidget {
  const _TaskMeta({
    required this.icon,
    required this.label,
    required this.value,
  });
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          final labelWidget = Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          );
          final valueWidget = Text(
            value.isEmpty ? '—' : value,
            style: Theme.of(context).textTheme.labelMedium,
            textAlign: stacked ? TextAlign.start : TextAlign.end,
          );
          return Row(
            crossAxisAlignment: stacked
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 19,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 11),
              if (stacked)
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      labelWidget,
                      const SizedBox(height: 3),
                      valueWidget,
                    ],
                  ),
                )
              else ...[
                SizedBox(width: 104, child: labelWidget),
                Expanded(child: valueWidget),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _TasksLoadState extends StatelessWidget {
  const _TasksLoadState({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 70,
            height: 70,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.task_alt_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 31,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('tasksNeedMoment'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('tryAgain')),
          ),
        ],
      ),
    ),
  );
}

class _TaskRefreshWarning extends StatelessWidget {
  const _TaskRefreshWarning({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(14, 8, 8, 8),
    decoration: BoxDecoration(
      color: AppTheme.gold.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.gold.withValues(alpha: .22)),
    ),
    child: Row(
      children: [
        const Icon(Icons.sync_problem_rounded, color: AppTheme.gold),
        const SizedBox(width: 9),
        Expanded(child: Text(context.tr('tasksShowingPrevious'))),
        TextButton(onPressed: onRetry, child: Text(context.tr('tryAgain'))),
      ],
    ),
  );
}

String _taskDueLabel(BuildContext context, String value) {
  if (value.isEmpty) return context.tr('noDueDate');
  final date = DateTime.tryParse(value);
  if (date == null) return value;
  final locale = AppControllerScope.of(context).locale.languageCode;
  return DateFormat.yMMMEd(locale).add_Hm().format(date.toLocal());
}

String _taskStageLabel(BuildContext context, TaskStage stage) =>
    switch (stage) {
      TaskStage.todo => context.tr('toDo'),
      TaskStage.inProgress => context.tr('inProgress'),
      TaskStage.blocked => context.tr('blocked'),
      TaskStage.done => context.tr('done'),
      TaskStage.cancelled => context.tr('cancelled'),
    };

import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/workflow_models.dart';

class StaffAchievementsPage extends StatefulWidget {
  const StaffAchievementsPage({super.key});

  @override
  State<StaffAchievementsPage> createState() => _StaffAchievementsPageState();
}

class _StaffAchievementsPageState extends State<StaffAchievementsPage> {
  Future<List<StaffAchievementInfo>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppControllerScope.of(context).loadStaffAchievements();
  }

  Future<void> _refresh() async {
    final future = AppControllerScope.of(context).loadStaffAchievements();
    setState(() => _future = future);
    await future;
  }

  Future<void> _create() async {
    final created = await showAppSheet<bool>(
      context: context,
      builder: (_) => const _CreateAchievementSheet(),
    );
    if (created == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final canWrite = controller.canMutate('achievements:write');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('achievements')),
        actions: [
          if (canWrite)
            IconButton(
              tooltip: 'Create achievement',
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      body: FutureBuilder<List<StaffAchievementInfo>>(
        future: _future,
        builder: (context, snapshot) => RefreshIndicator.adaptive(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: PageIntro(
                    title: context.tr('achievements'),
                    subtitle: context.tr('achievementsSubtitle'),
                    trailing: snapshot.hasData
                        ? StatusPill(
                            label:
                                '${snapshot.data!.where((item) => item.status == 'active').length}',
                            color: const Color(0xFF2D8B73),
                          )
                        : null,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'Achievements need another moment',
                    body: 'The recognition catalogue could not be refreshed.',
                    action: context.tr('tryAgain'),
                    onAction: _refresh,
                    icon: Icons.cloud_off_outlined,
                  ),
                )
              else if ((snapshot.data ?? const []).isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: context.tr('noItems'),
                    body: context.tr('achievementsSubtitle'),
                    action: canWrite ? 'Create achievement' : null,
                    onAction: canWrite ? _create : null,
                    icon: Icons.workspace_premium_outlined,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.crossAxisExtent >= 700
                          ? 2
                          : 1;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: 220,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final achievement = snapshot.data![index];
                          return PremiumCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 52,
                                      height: 52,
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppTheme.gold.withValues(
                                          alpha: .12,
                                        ),
                                        borderRadius: BorderRadius.circular(17),
                                      ),
                                      child: Text(
                                        achievement.emoji,
                                        style: const TextStyle(fontSize: 25),
                                      ),
                                    ),
                                    const Spacer(),
                                    StatusPill(
                                      label: achievement.status,
                                      color: achievement.status == 'active'
                                          ? const Color(0xFF2D8B73)
                                          : AppTheme.gold,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 15),
                                Text(
                                  achievement.name,
                                  style: Theme.of(context).textTheme.titleLarge,
                                ),
                                const SizedBox(height: 5),
                                Expanded(
                                  child: Text(
                                    achievement.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                if (canWrite &&
                                    achievement.status == 'active' &&
                                    achievement.scope == 'group')
                                  FilledButton.tonalIcon(
                                    onPressed: () => _grant(achievement),
                                    icon: const Icon(
                                      Icons.workspace_premium_outlined,
                                    ),
                                    label: const Text('Give achievement'),
                                  ),
                              ],
                            ),
                          );
                        }, childCount: snapshot.data!.length),
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _grant(StaffAchievementInfo achievement) async {
    final granted = await showAppSheet<bool>(
      context: context,
      builder: (_) => _GrantAchievementSheet(achievement: achievement),
    );
    if (granted == true && mounted) {
      showPremiumToast(context, 'The achievement was added to the student.');
    }
  }
}

class _CreateAchievementSheet extends StatefulWidget {
  const _CreateAchievementSheet();

  @override
  State<_CreateAchievementSheet> createState() =>
      _CreateAchievementSheetState();
}

class _CreateAchievementSheetState extends State<_CreateAchievementSheet> {
  final _name = TextEditingController();
  final _description = TextEditingController();
  final _emoji = TextEditingController(text: '⭐');
  List<LearningGroup> _groups = const [];
  int? _groupId;
  bool _loading = true;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _loadGroups();
  }

  Future<void> _loadGroups() async {
    final groups = await AppControllerScope.of(context).loadGroups();
    if (!mounted) return;
    setState(() {
      _groups = groups.where((item) => item.remoteId != null).toList();
      _groupId = _groups.firstOrNull?.remoteId;
      _loading = false;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _emoji.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_groupId == null || _name.text.trim().isEmpty) return;
    setState(() => _saving = true);
    try {
      await AppControllerScope.of(context).createGroupAchievement(
        cohortId: _groupId!,
        name: _name.text,
        description: _description.text,
        emoji: _emoji.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          'The achievement could not be created.',
          color: AppTheme.coral,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Create a group achievement',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Teachers can create recognition only for their assigned groups.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator.adaptive())
          else
            DropdownButtonFormField<int>(
              initialValue: _groupId,
              decoration: const InputDecoration(labelText: 'Group'),
              items: _groups
                  .map(
                    (group) => DropdownMenuItem(
                      value: group.remoteId,
                      child: Text(group.name),
                    ),
                  )
                  .toList(growable: false),
              onChanged: (value) => setState(() => _groupId = value),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              SizedBox(
                width: 82,
                child: TextField(
                  controller: _emoji,
                  textAlign: TextAlign.center,
                  decoration: const InputDecoration(labelText: 'Icon'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: _name,
                  decoration: const InputDecoration(labelText: 'Name'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 3,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'What this achievement recognizes',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving || _groups.isEmpty ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.add_rounded),
            label: const Text('Create achievement'),
          ),
        ],
      ),
    ),
  );
}

class _GrantAchievementSheet extends StatefulWidget {
  const _GrantAchievementSheet({required this.achievement});

  final StaffAchievementInfo achievement;

  @override
  State<_GrantAchievementSheet> createState() => _GrantAchievementSheetState();
}

class _GrantAchievementSheetState extends State<_GrantAchievementSheet> {
  final _note = TextEditingController();
  Future<List<AssignedStudentInfo>>? _future;
  AssignedStudentInfo? _student;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppControllerScope.of(context).loadAssignedStudents();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final id = int.tryParse(_student?.student.id ?? '');
    if (id == null) return;
    setState(() => _saving = true);
    try {
      await AppControllerScope.of(context).grantStaffAchievement(
        achievementId: widget.achievement.id,
        studentId: id,
        note: _note.text,
      );
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          'The achievement could not be granted.',
          color: AppTheme.coral,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: FutureBuilder<List<AssignedStudentInfo>>(
      future: _future,
      builder: (context, snapshot) {
        final students = (snapshot.data ?? const <AssignedStudentInfo>[])
            .where(
              (item) =>
                  widget.achievement.cohortId == null ||
                  item.group.remoteId == widget.achievement.cohortId,
            )
            .toList(growable: false);
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${widget.achievement.emoji} ${widget.achievement.name}',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              DropdownButtonFormField<AssignedStudentInfo>(
                initialValue: _student,
                decoration: const InputDecoration(labelText: 'Student'),
                items: students
                    .map(
                      (item) => DropdownMenuItem(
                        value: item,
                        child: Text(item.student.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _student = value),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _note,
                minLines: 3,
                maxLines: 5,
                decoration: const InputDecoration(
                  labelText: 'Personal note',
                  hintText: 'Explain what the student did well.',
                ),
              ),
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: _saving || _student == null ? null : _save,
                icon: const Icon(Icons.workspace_premium_outlined),
                label: const Text('Give achievement'),
              ),
            ],
          ),
        );
      },
    ),
  );
}

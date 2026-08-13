import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/remote_models.dart';
import 'attendance_page.dart';
import 'branch_transfer_sheet.dart';
import 'student_detail_page.dart';

class GroupDetailPage extends StatefulWidget {
  const GroupDetailPage({super.key, required this.group});
  final LearningGroup group;

  @override
  State<GroupDetailPage> createState() => _GroupDetailPageState();
}

class _GroupDetailPageState extends State<GroupDetailPage> {
  final _scrollController = ScrollController();
  final _studentsKey = GlobalKey();
  late LearningGroup _group = widget.group;
  Future<void>? _loading;
  Object? _error;
  bool _detailsLoaded = false;
  CohortCycleProgressInfo? _cycleProgress;
  Object? _cycleError;
  Future<void>? _cycleLoading;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loading ??= _load();
    _cycleLoading ??= _loadCycleProgress();
  }

  Future<void> _loadCycleProgress() async {
    final controller = AppControllerScope.of(context);
    if (mounted) setState(() => _cycleError = null);
    try {
      final progress = await controller.loadCohortCycleProgress(_group);
      if (mounted) setState(() => _cycleProgress = progress);
    } catch (error) {
      if (mounted) setState(() => _cycleError = error);
    }
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final updated = await AppControllerScope.of(
        context,
      ).loadGroupDetails(_group);
      if (mounted) {
        setState(() {
          _group = updated;
          _detailsLoaded = true;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _refresh() async {
    final loading = _load();
    final cycleLoading = _loadCycleProgress();
    setState(() {
      _loading = loading;
      _cycleLoading = cycleLoading;
    });
    await Future.wait([loading, cycleLoading]);
  }

  Future<void> _editTeachingProgress() async {
    final controller = AppControllerScope.of(context);
    if (!controller.canEditCohortTeachingProgress(_group)) return;
    final draft = await showAppSheet<_TeachingProgressDraft>(
      context: context,
      builder: (_) => _TeachingProgressSheet(
        level: _group.level,
        studyMonth: _group.studyMonth ?? _cycleProgress?.currentStudyMonth ?? 1,
        lessonCycleLength:
            _group.lessonCycleLength ?? _cycleProgress?.lessonCycleLength ?? 12,
      ),
    );
    if (!mounted || draft == null) return;
    try {
      final updated = await controller.updateCohortTeachingProgress(
        group: _group,
        level: draft.level,
        studyMonth: draft.studyMonth,
        lessonCycleLength: draft.lessonCycleLength,
      );
      if (!mounted) return;
      setState(() => _group = updated);
      final loading = _loadCycleProgress();
      setState(() => _cycleLoading = loading);
      await loading;
      if (mounted) {
        showPremiumToast(
          context,
          context.tr('changesSaved'),
          icon: Icons.auto_graph_rounded,
        );
      }
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          context.tr('actionUnavailable'),
          icon: Icons.info_outline_rounded,
          color: AppTheme.gold,
        );
      }
    }
  }

  void _openAttendance({bool exams = false}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AttendancePage(group: _group, initialExamTab: exams),
      ),
    );
  }

  void _showStudents() {
    final target = _studentsKey.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
      alignment: .08,
    );
  }

  Future<void> _moveGroup() async {
    final moved = await showGroupBranchTransferSheet(context, _group);
    if (moved && mounted) Navigator.of(context).pop(true);
  }

  Future<void> _openStudent(Student student) async {
    final moved = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => StudentDetailPage(student: student, group: _group),
      ),
    );
    if (moved == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppControllerScope.of(context);
    final canReadStudents = controller.can('students:read');
    return Scaffold(
      appBar: AppBar(
        title: Text(_group.name),
        actions: [
          if (controller.canTransferBranches &&
              _group.remoteId != null &&
              _group.branchId != null)
            IconButton(
              tooltip: context.tr('moveGroupBranch'),
              onPressed: _moveGroup,
              icon: const Icon(Icons.compare_arrows_rounded),
            ),
          IconButton(
            tooltip: context.tr('refresh'),
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: RefreshIndicator.adaptive(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(child: _GroupHero(group: _group)),
              ),
              if (_error != null) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 13)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(child: _GentleError(onRetry: _refresh)),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final metrics = [
                        (
                          _detailsLoaded && canReadStudents
                              ? '${_group.students.length}'
                              : '—',
                          context.tr('students'),
                          Icons.groups_outlined,
                          theme.colorScheme.primary,
                        ),
                        (
                          _detailsLoaded && _group.attendance != null
                              ? '${(_group.attendance! * 100).round()}%'
                              : '—',
                          context.tr('attendance'),
                          Icons.fact_check_outlined,
                          const Color(0xFF258C76),
                        ),
                        (
                          _group.capacity?.toString() ?? '—',
                          context.tr('capacity'),
                          Icons.event_seat_outlined,
                          const Color(0xFFE07886),
                        ),
                      ];
                      final textScale = MediaQuery.textScalerOf(
                        context,
                      ).scale(1);
                      final columns = textScale >= 1.5
                          ? 1
                          : constraints.maxWidth >= 620
                          ? 3
                          : 3;
                      final width =
                          (constraints.maxWidth - 9 * (columns - 1)) / columns;
                      return Wrap(
                        spacing: 9,
                        runSpacing: 9,
                        children: metrics
                            .map(
                              (metric) => SizedBox(
                                width: width,
                                child: MetricTile(
                                  value: metric.$1,
                                  label: metric.$2,
                                  icon: metric.$3,
                                  color: metric.$4,
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: MaxWidthBox(child: _GroupInfo(group: _group)),
              ),
              if (AppControllerScope.of(context).account?.principalKind ==
                      'teacher' &&
                  AppControllerScope.of(context).can('cohorts:read')) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 18)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: FutureBuilder<void>(
                      future: _cycleLoading,
                      builder: (context, snapshot) => _CycleProgressCard(
                        progress: _cycleProgress,
                        loading:
                            snapshot.connectionState ==
                                ConnectionState.waiting &&
                            _cycleProgress == null,
                        failed: _cycleError != null,
                        onRetry: () {
                          final loading = _loadCycleProgress();
                          setState(() => _cycleLoading = loading);
                        },
                        onEdit: controller.canEditCohortTeachingProgress(_group)
                            ? _editTeachingProgress
                            : null,
                      ),
                    ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: _GroupActions(
                    onAttendance: controller.can('attendance:read')
                        ? () => _openAttendance()
                        : null,
                    onExams: controller.can('academics:read')
                        ? () => _openAttendance(exams: true)
                        : null,
                    onStudents: canReadStudents ? _showStudents : null,
                  ),
                ),
              ),
              if (canReadStudents) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 27)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: KeyedSubtree(
                      key: _studentsKey,
                      child: SectionHeader(
                        title: context.tr('studentList'),
                        subtitle: _group.students.isEmpty
                            ? context.tr('studentListPreparing')
                            : context.trCount(
                                'studentsCount',
                                _group.students.length,
                              ),
                      ),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 11)),
                FutureBuilder<void>(
                  future: _loading,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting &&
                        _group.students.isEmpty) {
                      return SliverToBoxAdapter(
                        child: MaxWidthBox(child: _StudentSkeleton()),
                      );
                    }
                    if (_group.students.isEmpty) {
                      return SliverToBoxAdapter(
                        child: MaxWidthBox(
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 34),
                            child: EmptyState(
                              title: context.tr('noStudentsYet'),
                              body: context.tr('noStudentsYetBody'),
                              icon: Icons.group_add_outlined,
                            ),
                          ),
                        ),
                      );
                    }
                    return SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        MediaQuery.sizeOf(context).width >= 1080
                            ? (MediaQuery.sizeOf(context).width - 1080) / 2 + 20
                            : 20,
                        0,
                        MediaQuery.sizeOf(context).width >= 1080
                            ? (MediaQuery.sizeOf(context).width - 1080) / 2 + 20
                            : 20,
                        34,
                      ),
                      sliver: SliverList.separated(
                        itemCount: _group.students.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final student = _group.students[index];
                          return FadeSlideIn(
                            delay: Duration(milliseconds: 35 * index),
                            child: _StudentRow(
                              student: student,
                              onOpen: () => _openStudent(student),
                              onRequest:
                                  AppControllerScope.of(
                                    context,
                                  ).canMutate('approvals:write')
                                  ? () => showStudentRequestSheet(
                                      context,
                                      group: _group,
                                      student: student,
                                    )
                                  : null,
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupHero extends StatelessWidget {
  const _GroupHero({required this.group});
  final LearningGroup group;

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    String dateLabel(DateTime? value) =>
        value == null ? '—' : DateFormat.yMMMd(locale).format(value.toLocal());
    final subtitle = [
      group.department,
      group.level,
    ].where((value) => value.isNotEmpty && value != '—').join(' · ');
    final now = DateTime.now();
    final status = group.endDate != null && group.endDate!.isBefore(now)
        ? context.tr('completed')
        : group.startDate != null && group.startDate!.isAfter(now)
        ? context.tr('upcoming')
        : context.tr('active');
    final statusColor = group.endDate != null && group.endDate!.isBefore(now)
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : group.startDate != null && group.startDate!.isAfter(now)
        ? AppTheme.gold
        : AppTheme.mint;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            const Color(0xFF30336E),
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: .18),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: .12),
                  ),
                ),
                child: const Icon(
                  Icons.auto_stories_rounded,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              StatusPill(label: status, color: statusColor, icon: Icons.circle),
            ],
          ),
          const SizedBox(height: 24),
          Text(
            group.name,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              letterSpacing: -.8,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white.withValues(alpha: .72),
              ),
            ),
          ],
          const SizedBox(height: 20),
          Wrap(
            spacing: 9,
            runSpacing: 9,
            children: [
              _HeroChip(icon: Icons.meeting_room_outlined, text: group.room),
              _HeroChip(
                icon: Icons.date_range_outlined,
                text:
                    '${dateLabel(group.startDate)} — ${dateLabel(group.endDate)}',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  const _HeroChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxWidth: (MediaQuery.sizeOf(context).width - 84).clamp(180, 520),
    ),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .11),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: .82), size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text.isEmpty ? '—' : text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class _GroupInfo extends StatelessWidget {
  const _GroupInfo({required this.group});
  final LearningGroup group;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (context.tr('branch'), group.branch, Icons.location_on_outlined),
      (
        context.tr('department'),
        group.department,
        Icons.account_balance_outlined,
      ),
      (
        context.tr('mainTeacher'),
        group.mainTeacher,
        Icons.person_outline_rounded,
      ),
      (context.tr('level'), group.level, Icons.stairs_outlined),
      if (group.studyMonth != null)
        (
          context.tr('month'),
          '${group.studyMonth}',
          Icons.calendar_month_outlined,
        ),
      (context.tr('mainRoom'), group.room, Icons.meeting_room_outlined),
    ];
    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: rows
            .map(
              (row) => Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 17,
                  vertical: 11,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.primaryContainer.withValues(alpha: .68),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Icon(
                        row.$3,
                        size: 18,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        row.$1,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        row.$2.isEmpty ? '—' : row.$2,
                        textAlign: TextAlign.end,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ],
                ),
              ),
            )
            .toList(),
      ),
    );
  }
}

class _CycleProgressCard extends StatelessWidget {
  const _CycleProgressCard({
    required this.progress,
    required this.loading,
    required this.failed,
    required this.onRetry,
    this.onEdit,
  });

  final CohortCycleProgressInfo? progress;
  final bool loading;
  final bool failed;
  final VoidCallback onRetry;
  final VoidCallback? onEdit;

  @override
  Widget build(BuildContext context) {
    final data = progress;
    if (loading && data == null) {
      return PremiumCard(
        child: Semantics(
          label: context.tr('lessonCycle'),
          child: const SizedBox(
            height: 92,
            child: Center(child: CircularProgressIndicator.adaptive()),
          ),
        ),
      );
    }
    if (failed && data == null) {
      return PremiumCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                Icons.refresh_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.tr('cycleUnavailable'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 5),
                  Text(
                    context.tr('cycleUnavailableBody'),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 11),
                  TextButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: Text(context.tr('tryAgain')),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }
    if (data == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final locale = AppControllerScope.of(context).locale.languageCode;
    final next = data.nextScheduledLesson;
    final fraction = data.completedInCurrentCycle / data.lessonCycleLength;
    final examColor = theme.brightness == Brightness.dark
        ? const Color(0xFFFFC66B)
        : const Color(0xFF8A4B00);
    return PremiumCard(
      padding: const EdgeInsets.all(19),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final summary = Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.tertiary,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.track_changes_rounded,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('lessonCycle'),
                          style: theme.textTheme.titleMedium,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          context.l10n.format('cycleOverallProgress', {
                            'count': data.completedLessons,
                          }),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onEdit != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      tooltip: context.tr('updateProgress'),
                      onPressed: onEdit,
                      icon: const Icon(Icons.edit_outlined),
                    ),
                  ],
                ],
              );
              final status = StatusPill(
                label: context.l10n.format('lessonCycleShort', {
                  'count': data.lessonCycleLength,
                }),
                color: theme.colorScheme.primary,
              );
              final stacked =
                  MediaQuery.textScalerOf(context).scale(1) >= 1.45 ||
                  constraints.maxWidth < 330;
              if (stacked) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [summary, const SizedBox(height: 11), status],
                );
              }
              return Row(
                children: [
                  Expanded(child: summary),
                  const SizedBox(width: 10),
                  status,
                ],
              );
            },
          ),
          const SizedBox(height: 18),
          Text(
            context.l10n.format('cycleProgress', {
              'completed': data.completedInCurrentCycle,
              'total': data.lessonCycleLength,
            }),
            style: theme.textTheme.labelLarge,
          ),
          const SizedBox(height: 9),
          Semantics(
            label: context.l10n.format('cycleProgress', {
              'completed': data.completedInCurrentCycle,
              'total': data.lessonCycleLength,
            }),
            value: '${(fraction * 100).round()}%',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                value: fraction,
                minHeight: 9,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
              ),
            ),
          ),
          const SizedBox(height: 13),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _CycleChip(
                icon: Icons.stairs_outlined,
                label: data.currentLevel.isEmpty
                    ? context.tr('level')
                    : data.currentLevel,
              ),
              _CycleChip(
                icon: Icons.calendar_month_outlined,
                label: context.l10n.format('studyMonthValue', {
                  'month': data.currentStudyMonth,
                }),
              ),
              _CycleChip(
                icon: Icons.looks_one_outlined,
                label: context.l10n.format('cycleNextLesson', {
                  'number': data.nextCycleLessonNumber,
                }),
              ),
              _CycleChip(
                icon: Icons.flag_outlined,
                label: context.l10n.count(
                  'cycleLessonsRemaining',
                  data.lessonsRemainingInCycle,
                ),
              ),
            ],
          ),
          if (data.examDayDue) ...[
            const SizedBox(height: 15),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppTheme.gold.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(17),
                border: Border.all(color: AppTheme.gold.withValues(alpha: .32)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.workspace_premium_outlined, color: examColor),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('cycleExamDue'),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: examColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          context.tr('cycleExamDueBody'),
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (next != null) ...[
            const SizedBox(height: 15),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: .62,
                ),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.event_available_outlined,
                    color: theme.colorScheme.primary,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          next.title.isEmpty
                              ? context.tr('nextLesson')
                              : next.title,
                          style: theme.textTheme.titleSmall,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          DateFormat.yMMMd(
                            locale,
                          ).add_Hm().format(next.startsAt.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (next.roomName.isNotEmpty) ...[
                          const SizedBox(height: 3),
                          Text(
                            next.roomName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!data.completionDataComplete) ...[
            const SizedBox(height: 14),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        context.tr('cycleCompletionIncomplete'),
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        context.l10n.count(
                          'cycleIncomplete',
                          data.pastScheduledLessonsWithoutCompletion,
                        ),
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 13),
          Text(
            context.tr('cycleLevelManual'),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (failed) ...[
            const SizedBox(height: 9),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.tr('refresh')),
            ),
          ],
        ],
      ),
    );
  }
}

class _TeachingProgressDraft {
  const _TeachingProgressDraft({
    required this.level,
    required this.studyMonth,
    required this.lessonCycleLength,
  });

  final String level;
  final int studyMonth;
  final int lessonCycleLength;
}

class _TeachingProgressSheet extends StatefulWidget {
  const _TeachingProgressSheet({
    required this.level,
    required this.studyMonth,
    required this.lessonCycleLength,
  });

  final String level;
  final int studyMonth;
  final int lessonCycleLength;

  @override
  State<_TeachingProgressSheet> createState() => _TeachingProgressSheetState();
}

class _TeachingProgressSheetState extends State<_TeachingProgressSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _levelController;
  late final TextEditingController _monthController;
  late int _cycleLength;

  @override
  void initState() {
    super.initState();
    _levelController = TextEditingController(text: widget.level);
    _monthController = TextEditingController(text: '${widget.studyMonth}');
    _cycleLength = widget.lessonCycleLength;
  }

  @override
  void dispose() {
    _levelController.dispose();
    _monthController.dispose();
    super.dispose();
  }

  void _save() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(
      _TeachingProgressDraft(
        level: _levelController.text.trim(),
        studyMonth: int.parse(_monthController.text),
        lessonCycleLength: _cycleLength,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('updateProgress'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 18),
              TextFormField(
                controller: _levelController,
                maxLength: 64,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: context.tr('level'),
                  prefixIcon: const Icon(Icons.stairs_outlined),
                ),
              ),
              const SizedBox(height: 8),
              TextFormField(
                controller: _monthController,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                textInputAction: TextInputAction.done,
                onFieldSubmitted: (_) => _save(),
                validator: (value) {
                  final month = int.tryParse(value ?? '');
                  return month != null && month >= 1 && month <= 600
                      ? null
                      : context.tr('studyMonthRange');
                },
                decoration: InputDecoration(
                  labelText: context.tr('month'),
                  prefixIcon: const Icon(Icons.calendar_month_outlined),
                ),
              ),
              const SizedBox(height: 18),
              Text(
                context.tr('lessonCycle'),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 9),
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 8, label: Text('8')),
                    ButtonSegment(value: 12, label: Text('12')),
                  ],
                  selected: {_cycleLength},
                  onSelectionChanged: (selection) =>
                      setState(() => _cycleLength = selection.single),
                ),
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(context.tr('cancel')),
                    ),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _save,
                      icon: const Icon(Icons.check_rounded),
                      label: Text(context.tr('save')),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CycleChip extends StatelessWidget {
  const _CycleChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    constraints: BoxConstraints(
      maxWidth: (MediaQuery.sizeOf(context).width - 76).clamp(190, 460),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: .58),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.labelSmall,
          ),
        ),
      ],
    ),
  );
}

class _GroupActions extends StatelessWidget {
  const _GroupActions({
    required this.onAttendance,
    required this.onExams,
    required this.onStudents,
  });
  final VoidCallback? onAttendance;
  final VoidCallback? onExams;
  final VoidCallback? onStudents;

  @override
  Widget build(BuildContext context) {
    final items = [
      if (onAttendance != null)
        (Icons.calendar_month_rounded, context.tr('attendance'), onAttendance!),
      if (onExams != null)
        (Icons.workspace_premium_outlined, context.tr('exams'), onExams!),
      if (onStudents != null)
        (Icons.people_alt_outlined, context.tr('students'), onStudents!),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(1);
        final columns = textScale >= 1.5 ? 1 : items.length;
        final width = (constraints.maxWidth - 9 * (columns - 1)) / columns;
        return Wrap(
          spacing: 9,
          runSpacing: 9,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: PremiumCard(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 15,
                    ),
                    onTap: item.$3,
                    child: Column(
                      children: [
                        Icon(
                          item.$1,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          item.$2,
                          textAlign: TextAlign.center,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _StudentRow extends StatelessWidget {
  const _StudentRow({
    required this.student,
    required this.onOpen,
    required this.onRequest,
  });
  final Student student;
  final VoidCallback onOpen;
  final VoidCallback? onRequest;

  @override
  Widget build(BuildContext context) {
    final attendance = student.attendance;
    final attendanceColor = attendance == null
        ? Theme.of(context).colorScheme.onSurfaceVariant
        : attendance >= .9
        ? AppTheme.mint
        : attendance >= .75
        ? AppTheme.gold
        : AppTheme.coral;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onOpen,
      child: Row(
        children: [
          PersonAvatar(name: student.name),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  attendance == null
                      ? context.tr('attendanceNotMarked')
                      : context.l10n.format('attendancePercent', {
                          'percent': (attendance * 100).round(),
                        }),
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: attendanceColor),
                ),
              ],
            ),
          ),
          if (onRequest != null)
            IconButton(
              tooltip: context.tr('requestAction'),
              onPressed: onRequest,
              icon: const Icon(Icons.more_horiz_rounded),
            )
          else
            const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _StudentSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      4,
      (index) => Container(
        height: 72,
        margin: const EdgeInsets.only(bottom: 9),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: .52 - index * .05),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    ),
  );
}

class _GentleError extends StatelessWidget {
  const _GentleError({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: AppTheme.gold.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: AppTheme.gold.withValues(alpha: .2)),
    ),
    child: Row(
      children: [
        const Icon(Icons.wb_sunny_outlined, color: Color(0xFFC47B16)),
        const SizedBox(width: 11),
        Expanded(child: Text(context.tr('groupDetailsNeedMoment'))),
        TextButton(onPressed: onRetry, child: Text(context.tr('tryAgain'))),
      ],
    ),
  );
}

void showStudentRequestSheet(
  BuildContext context, {
  required LearningGroup group,
  required Student student,
}) {
  var selected = 'help';
  var busy = false;
  String? error;
  final descriptionController = TextEditingController();
  showAppSheet<void>(
    context: context,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          2,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  PersonAvatar(name: student.name),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('requestAction'),
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          student.name,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children:
                    [
                          (
                            'help',
                            context.tr('requestHelp'),
                            Icons.support_outlined,
                          ),
                          (
                            'move',
                            context.tr('requestMove'),
                            Icons.swap_horiz_rounded,
                          ),
                          (
                            'kick',
                            context.tr('requestKick'),
                            Icons.person_remove_outlined,
                          ),
                        ]
                        .map(
                          (item) => ChoiceChip(
                            selected: selected == item.$1,
                            onSelected: busy
                                ? null
                                : (_) =>
                                      setSheetState(() => selected = item.$1),
                            avatar: Icon(item.$3, size: 18),
                            label: Text(item.$2),
                          ),
                        )
                        .toList(growable: false),
              ),
              const SizedBox(height: 18),
              TextField(
                controller: descriptionController,
                minLines: 4,
                maxLines: 7,
                decoration: InputDecoration(
                  hintText: context.tr('requestReason'),
                  alignLabelWithHint: true,
                  errorText: error,
                ),
              ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () async {
                          if (descriptionController.text.trim().isEmpty) {
                            setSheetState(
                              () => error = context.tr('descriptionRequired'),
                            );
                            return;
                          }
                          setSheetState(() {
                            busy = true;
                            error = null;
                          });
                          final ok = await AppControllerScope.of(context)
                              .submitStudentRequest(
                                action: selected,
                                group: group,
                                student: student,
                                description: descriptionController.text,
                              );
                          if (!context.mounted) return;
                          if (!ok) {
                            setSheetState(() {
                              busy = false;
                              error = context.tr('requestCouldNotSend');
                            });
                            return;
                          }
                          Navigator.pop(sheetContext);
                          showPremiumToast(
                            context,
                            context.tr('requestSent'),
                            icon: Icons.outbox_rounded,
                          );
                        },
                  icon: busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: Text(context.tr('sendRequest')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  ).whenComplete(descriptionController.dispose);
}

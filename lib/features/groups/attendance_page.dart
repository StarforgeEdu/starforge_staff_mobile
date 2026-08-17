import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/remote_models.dart';

class AttendancePage extends StatefulWidget {
  const AttendancePage({
    super.key,
    required this.group,
    this.initialExamTab = false,
  });

  final LearningGroup group;
  final bool initialExamTab;

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  late bool _showExams = widget.initialExamTab;
  int _monthOffset = 0;
  DateTime? _selectedDay;
  AttendanceMonth? _monthData;
  List<ExamInfo>? _exams;
  bool _loading = false;
  bool _examsLoading = false;
  Object? _error;
  Object? _examError;
  bool _started = false;

  DateTime get _month {
    final now = DateTime.now();
    return DateTime(now.year, now.month + _monthOffset);
  }

  int get _minimumMonthOffset {
    final start = widget.group.startDate?.toLocal();
    if (start == null) return -60;
    final now = DateTime.now();
    final offset = (start.year - now.year) * 12 + start.month - now.month;
    return offset.clamp(-120, 0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (_showExams && !AppControllerScope.of(context).can('academics:read')) {
      _showExams = false;
    }
    _loadMonth();
    if (_showExams) _loadExams();
  }

  Future<void> _loadMonth() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await AppControllerScope.of(
        context,
      ).loadAttendanceMonth(widget.group, _month);
      if (!mounted) return;
      setState(() {
        _monthData = data;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  Future<void> _loadExams() async {
    if (_examsLoading) return;
    setState(() {
      _examsLoading = true;
      _examError = null;
    });
    try {
      final exams = await AppControllerScope.of(
        context,
      ).loadExams(widget.group);
      if (!mounted) return;
      setState(() {
        _exams = exams;
        _examsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _examsLoading = false;
        _examError = error;
      });
    }
  }

  void _changeMonth(int delta) {
    setState(() {
      _monthOffset = (_monthOffset + delta).clamp(_minimumMonthOffset, 0);
      _selectedDay = null;
      _monthData = null;
    });
    _loadMonth();
  }

  String _monthTitle(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    final formatted = DateFormat.yMMMM(locale).format(_month);
    if (formatted.isEmpty) return '';
    return '${formatted[0].toUpperCase()}${formatted.substring(1)}';
  }

  void _toggleTab(bool exams) {
    setState(() => _showExams = exams);
    if (exams &&
        AppControllerScope.of(context).can('academics:read') &&
        _exams == null) {
      _loadExams();
    }
  }

  List<LessonInfo> get _visibleLessons {
    final lessons = [...?_monthData?.lessons]
      ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final day = _selectedDay;
    if (day == null) return lessons;
    return lessons
        .where((lesson) => _sameDay(lesson.startsAt.toLocal(), day))
        .toList();
  }

  LessonInfo? get _todayLesson {
    final now = DateTime.now();
    for (final lesson in _monthData?.lessons ?? const <LessonInfo>[]) {
      if (_sameDay(lesson.startsAt.toLocal(), now) && !lesson.isCancelled) {
        return lesson;
      }
    }
    return null;
  }

  bool _canStartLesson(LessonInfo lesson) =>
      !DateTime.now().isBefore(lesson.startsAt.toLocal());

  void _openTakeAttendance(LessonInfo lesson) async {
    final records = _monthData?.recordsFor(lesson.id) ?? const [];
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => TakeAttendancePage(
          group: widget.group,
          lesson: lesson,
          initialRecords: records,
        ),
      ),
    );
    if (changed == true) await _loadMonth();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('attendanceHistory'))),
      body: SafeArea(
        top: false,
        child: RefreshIndicator.adaptive(
          onRefresh: _showExams ? _loadExams : _loadMonth,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 900,
                  child: Column(
                    children: [
                      _AttendanceHero(
                        group: widget.group,
                        rate: _monthData?.rate,
                      ),
                      const SizedBox(height: 17),
                      Row(
                        children: [
                          IconButton.filledTonal(
                            tooltip: context.tr('previousMonth'),
                            onPressed:
                                _loading || _monthOffset <= _minimumMonthOffset
                                ? null
                                : () => _changeMonth(-1),
                            icon: const Icon(Icons.chevron_left_rounded),
                          ),
                          Expanded(
                            child: AnimatedSwitcher(
                              duration: MediaQuery.disableAnimationsOf(context)
                                  ? Duration.zero
                                  : const Duration(milliseconds: 220),
                              child: Text(
                                _monthTitle(context),
                                key: ValueKey(_monthOffset),
                                style: theme.textTheme.titleLarge,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                          IconButton.filledTonal(
                            tooltip: context.tr('nextMonth'),
                            onPressed: _monthOffset >= 0 || _loading
                                ? null
                                : () => _changeMonth(1),
                            icon: const Icon(Icons.chevron_right_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (AppControllerScope.of(context).can('academics:read'))
                        SizedBox(
                          width: double.infinity,
                          child: SegmentedButton<bool>(
                            segments: [
                              ButtonSegment(
                                value: false,
                                icon: const Icon(Icons.calendar_month_rounded),
                                label: Text(context.tr('attendance')),
                              ),
                              ButtonSegment(
                                value: true,
                                icon: const Icon(
                                  Icons.workspace_premium_outlined,
                                ),
                                label: Text(context.tr('exams')),
                              ),
                            ],
                            selected: {_showExams},
                            showSelectedIcon: false,
                            onSelectionChanged: (value) =>
                                _toggleTab(value.first),
                          ),
                        ),
                      const SizedBox(height: 18),
                    ],
                  ),
                ),
              ),
              if (!_showExams)
                ..._attendanceSlivers(context)
              else
                ..._examSlivers(context),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _attendanceSlivers(BuildContext context) {
    final data = _monthData;
    if (_loading && data == null) {
      return const [SliverToBoxAdapter(child: _AttendanceSkeleton())];
    }
    if (_error != null && data == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _AttendanceLoadState(onRetry: _loadMonth),
        ),
      ];
    }
    final todayLesson = _todayLesson;
    final canMark = AppControllerScope.of(
      context,
    ).canMutate('attendance:write');
    return [
      if (todayLesson != null && _monthOffset == 0)
        SliverToBoxAdapter(
          child: MaxWidthBox(
            maxWidth: 900,
            child: _TodayAttendanceCard(
              lesson: todayLesson,
              canWrite: canMark,
              onStart: () => _openTakeAttendance(todayLesson),
            ),
          ),
        ),
      if (todayLesson != null && _monthOffset == 0)
        const SliverToBoxAdapter(child: SizedBox(height: 18)),
      SliverToBoxAdapter(
        child: MaxWidthBox(
          maxWidth: 900,
          child: _MonthSummary(
            data: data ?? AttendanceMonth.empty(_month),
            expectedRosterCount: widget.group.students.length,
          ),
        ),
      ),
      if (_error != null && data != null) ...[
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
        SliverToBoxAdapter(
          child: MaxWidthBox(
            maxWidth: 900,
            child: _InlineLoadWarning(onRetry: _loadMonth),
          ),
        ),
      ],
      const SliverToBoxAdapter(child: SizedBox(height: 18)),
      SliverToBoxAdapter(
        child: MaxWidthBox(
          maxWidth: 900,
          child: SectionHeader(
            title: context.tr('fullMonthView'),
            subtitle: context.tr('tapDayToFilter'),
            action: _selectedDay == null ? null : context.tr('showAll'),
            onAction: _selectedDay == null
                ? null
                : () => setState(() => _selectedDay = null),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 11)),
      SliverToBoxAdapter(
        child: MaxWidthBox(
          maxWidth: 900,
          child: _MonthCalendar(
            month: _month,
            data: data ?? AttendanceMonth.empty(_month),
            expectedRosterCount: widget.group.students.length,
            selectedDay: _selectedDay,
            onSelected: (date) => setState(
              () => _selectedDay = _sameDay(_selectedDay, date) ? null : date,
            ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 22)),
      SliverToBoxAdapter(
        child: MaxWidthBox(
          maxWidth: 900,
          child: SectionHeader(
            title: _selectedDay == null
                ? context.tr('lessonHistory')
                : DateFormat.yMMMd(
                    AppControllerScope.of(context).locale.languageCode,
                  ).format(_selectedDay!),
            subtitle: context.trCount('lessonsCount', _visibleLessons.length),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 11)),
      if (_visibleLessons.isEmpty)
        SliverToBoxAdapter(
          child: MaxWidthBox(
            maxWidth: 900,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 34),
              child: EmptyState(
                title: context.tr('noLessonsThisPeriod'),
                body: context.tr('noLessonsThisPeriodBody'),
                icon: Icons.event_available_outlined,
              ),
            ),
          ),
        )
      else
        SliverPadding(
          padding: EdgeInsets.fromLTRB(
            MediaQuery.sizeOf(context).width >= 900
                ? (MediaQuery.sizeOf(context).width - 900) / 2 + 20
                : 20,
            0,
            MediaQuery.sizeOf(context).width >= 900
                ? (MediaQuery.sizeOf(context).width - 900) / 2 + 20
                : 20,
            34,
          ),
          sliver: SliverList.separated(
            itemCount: _visibleLessons.length,
            separatorBuilder: (_, _) => const SizedBox(height: 9),
            itemBuilder: (context, index) {
              final lesson = _visibleLessons[index];
              final records = data?.recordsFor(lesson.id) ?? const [];
              return FadeSlideIn(
                delay: Duration(milliseconds: 35 * index),
                child: _LessonHistoryRow(
                  lesson: lesson,
                  records: records,
                  canMark:
                      canMark &&
                      !lesson.isCancelled &&
                      _sameDay(lesson.startsAt.toLocal(), DateTime.now()) &&
                      _canStartLesson(lesson),
                  onOpen: () => _showLessonDetails(context, lesson, records),
                  onMark: () => _openTakeAttendance(lesson),
                ),
              );
            },
          ),
        ),
    ];
  }

  List<Widget> _examSlivers(BuildContext context) {
    if (_examsLoading && _exams == null) {
      return const [SliverToBoxAdapter(child: _AttendanceSkeleton())];
    }
    if (_examError != null && _exams == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _AttendanceLoadState(onRetry: _loadExams, exams: true),
        ),
      ];
    }
    final exams = _exams ?? const <ExamInfo>[];
    final visibleExams = exams
        .where(
          (exam) =>
              exam.date.toLocal().year == _month.year &&
              exam.date.toLocal().month == _month.month,
        )
        .toList(growable: false);
    if (visibleExams.isEmpty) {
      return [
        if (_examError != null) ...[
          SliverToBoxAdapter(
            child: MaxWidthBox(
              maxWidth: 900,
              child: _InlineLoadWarning(onRetry: _loadExams),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 14)),
        ],
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: context.tr('noExamsYet'),
            body: context.tr('noExamsYetBody'),
            icon: Icons.workspace_premium_outlined,
          ),
        ),
      ];
    }
    return [
      if (_examError != null) ...[
        SliverToBoxAdapter(
          child: MaxWidthBox(
            maxWidth: 900,
            child: _InlineLoadWarning(onRetry: _loadExams),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 14)),
      ],
      SliverToBoxAdapter(
        child: MaxWidthBox(
          maxWidth: 900,
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppTheme.gold.withValues(alpha: .1),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.gold.withValues(alpha: .2)),
            ),
            child: Row(
              children: [
                const Icon(Icons.insights_rounded, color: Color(0xFFC47B16)),
                const SizedBox(width: 11),
                Expanded(child: Text(context.tr('examHistoryHint'))),
              ],
            ),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 20)),
      SliverToBoxAdapter(
        child: MaxWidthBox(
          maxWidth: 900,
          child: SectionHeader(
            title: context.tr('examHistory'),
            subtitle: context.trCount('examsCount', visibleExams.length),
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 11)),
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 900
              ? (MediaQuery.sizeOf(context).width - 900) / 2 + 20
              : 20,
          0,
          MediaQuery.sizeOf(context).width >= 900
              ? (MediaQuery.sizeOf(context).width - 900) / 2 + 20
              : 20,
          34,
        ),
        sliver: SliverList.separated(
          itemCount: visibleExams.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) => _ExamCard(
            exam: visibleExams[index],
            canReadResults: AppControllerScope.of(
              context,
            ).can('academics:read'),
          ),
        ),
      ),
    ];
  }

  void _showLessonDetails(
    BuildContext context,
    LessonInfo lesson,
    List<AttendanceRecordInfo> records,
  ) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    final counts = _statusCounts(records);
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 2, 20, 28),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(
                      Icons.school_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.title.isEmpty
                              ? context.tr('lesson')
                              : lesson.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        Text(
                          DateFormat.yMMMEd(
                            locale,
                          ).add_Hm().format(lesson.startsAt.toLocal()),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _CountPill(
                    value: counts['present'] ?? 0,
                    color: AppTheme.mint,
                    icon: Icons.check_rounded,
                    label: context.tr('present'),
                  ),
                  _CountPill(
                    value: counts['absent'] ?? 0,
                    color: AppTheme.coral,
                    icon: Icons.close_rounded,
                    label: context.tr('absent'),
                  ),
                  _CountPill(
                    value: counts['late'] ?? 0,
                    color: AppTheme.gold,
                    icon: Icons.schedule_rounded,
                    label: context.tr('late'),
                  ),
                  _CountPill(
                    value: counts['excused'] ?? 0,
                    color: Theme.of(context).colorScheme.primary,
                    icon: Icons.favorite_outline_rounded,
                    label: context.tr('excused'),
                  ),
                ],
              ),
              if (records.isEmpty) ...[
                const SizedBox(height: 22),
                Text(
                  context.tr('attendanceNotMarked'),
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else ...[
                const SizedBox(height: 18),
                ListView.separated(
                  physics: const NeverScrollableScrollPhysics(),
                  shrinkWrap: true,
                  itemCount: records.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final record = records[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: PersonAvatar(name: record.studentName, size: 40),
                      title: Text(record.studentName),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _AttendanceStatus(status: record.status),
                            if (record.hasIssuedCard)
                              _IssuedCardPill(cardType: record.cardType),
                          ],
                        ),
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

class _AttendanceHero extends StatelessWidget {
  const _AttendanceHero({required this.group, required this.rate});
  final LearningGroup group;
  final double? rate;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(20),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .13),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(Icons.groups_2_outlined, color: Colors.white),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                group.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(color: Colors.white),
              ),
              const SizedBox(height: 3),
              Text(
                [group.level, group.room]
                    .where((value) => value.isNotEmpty && value != '—')
                    .join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Colors.white.withValues(alpha: .68),
                ),
              ),
            ],
          ),
        ),
        if (rate != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              '${rate!.round()}%',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.white),
            ),
          ),
      ],
    ),
  );
}

class _TodayAttendanceCard extends StatefulWidget {
  const _TodayAttendanceCard({
    required this.lesson,
    required this.canWrite,
    required this.onStart,
  });
  final LessonInfo lesson;
  final bool canWrite;
  final VoidCallback onStart;

  @override
  State<_TodayAttendanceCard> createState() => _TodayAttendanceCardState();
}

class _TodayAttendanceCardState extends State<_TodayAttendanceCard> {
  Timer? _timer;

  bool get _hasStarted =>
      !DateTime.now().isBefore(widget.lesson.startsAt.toLocal());

  @override
  void initState() {
    super.initState();
    if (!_hasStarted) {
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (!mounted) return;
        if (_hasStarted) _timer?.cancel();
        setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.today_rounded, color: Colors.white, size: 28),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.tr('today'),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .67),
                      ),
                    ),
                    Text(
                      '${DateFormat.Hm(locale).format(widget.lesson.startsAt.toLocal())} · ${widget.lesson.roomName.isEmpty ? context.tr('lesson') : widget.lesson.roomName}',
                      style: Theme.of(
                        context,
                      ).textTheme.titleMedium?.copyWith(color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Theme.of(context).colorScheme.primary,
              ),
              onPressed: widget.canWrite && _hasStarted ? widget.onStart : null,
              icon: const Icon(Icons.fact_check_outlined),
              label: Text(
                !widget.canWrite
                    ? context.tr('attendanceViewOnly')
                    : _hasStarted
                    ? context.tr('startAttendance')
                    : context.l10n.format('attendanceOpensIn', {
                        'time': _compactCountdown(
                          widget.lesson.startsAt.toLocal().difference(
                            DateTime.now(),
                          ),
                        ),
                      }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  const _MonthSummary({required this.data, required this.expectedRosterCount});
  final AttendanceMonth data;
  final int expectedRosterCount;

  @override
  Widget build(BuildContext context) {
    final recorded = data.records
        .map((record) => record.lessonId)
        .toSet()
        .where(
          (lessonId) => data.isRegisterComplete(
            lessonId,
            expectedRosterCount: expectedRosterCount,
          ),
        )
        .length;
    final absent = data.records
        .where((record) => record.status == 'absent')
        .length;
    final values = [
      (
        '${data.lessons.length}',
        context.tr('lessons'),
        Icons.menu_book_outlined,
      ),
      ('$recorded', context.tr('markedLessons'), Icons.task_alt_rounded),
      ('$absent', context.tr('absences'), Icons.person_off_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = (constraints.maxWidth - 16) / 3;
        return Row(
          children: values
              .map(
                (item) => Padding(
                  padding: EdgeInsetsDirectional.only(
                    end: item == values.last ? 0 : 8,
                  ),
                  child: SizedBox(
                    width: width,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 13,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(
                          color: Theme.of(
                            context,
                          ).colorScheme.outlineVariant.withValues(alpha: .42),
                        ),
                      ),
                      child: Column(
                        children: [
                          Icon(
                            item.$3,
                            size: 19,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            item.$1,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            item.$2,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ),
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

class _MonthCalendar extends StatelessWidget {
  const _MonthCalendar({
    required this.month,
    required this.data,
    required this.expectedRosterCount,
    required this.selectedDay,
    required this.onSelected,
  });
  final DateTime month;
  final AttendanceMonth data;
  final int expectedRosterCount;
  final DateTime? selectedDay;
  final ValueChanged<DateTime> onSelected;

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    final first = DateTime(month.year, month.month);
    final leading = first.weekday - DateTime.monday;
    final days = DateUtils.getDaysInMonth(month.year, month.month);
    final totalCells = ((leading + days + 6) ~/ 7) * 7;
    final weekdayBase = DateTime(2024, 1, 1);
    return PremiumCard(
      padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
      child: Column(
        children: [
          Row(
            children: List.generate(7, (index) {
              final label = DateFormat.E(
                locale,
              ).format(weekdayBase.add(Duration(days: index)));
              return Expanded(
                child: Text(
                  label.substring(0, label.length.clamp(0, 2)).toUpperCase(),
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: totalCells,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 5,
              crossAxisSpacing: 5,
              childAspectRatio: .86,
            ),
            itemBuilder: (context, index) {
              final day = index - leading + 1;
              if (day < 1 || day > days) return const SizedBox.shrink();
              final date = DateTime(month.year, month.month, day);
              final lessons = data.lessons
                  .where((lesson) => _sameDay(lesson.startsAt.toLocal(), date))
                  .toList();
              final lessonIds = lessons.map((lesson) => lesson.id).toSet();
              final records = data.records
                  .where((record) => lessonIds.contains(record.lessonId))
                  .toList();
              final scheduledLessons = lessons
                  .where((lesson) => !lesson.isCancelled)
                  .toList(growable: false);
              final complete =
                  scheduledLessons.isNotEmpty &&
                  scheduledLessons.every(
                    (lesson) => data.isRegisterComplete(
                      lesson.id,
                      expectedRosterCount: expectedRosterCount,
                    ),
                  );
              return _CalendarDay(
                date: date,
                hasLesson: lessons.isNotEmpty,
                isComplete: complete,
                isPartial: records.isNotEmpty && !complete,
                hasAbsence: records.any((record) => record.status == 'absent'),
                isSelected: _sameDay(date, selectedDay),
                isToday: _sameDay(date, DateTime.now()),
                onTap: () => onSelected(date),
              );
            },
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 14,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _CalendarLegendDot(
                color: Theme.of(context).colorScheme.primary,
                label: context.tr('scheduled'),
              ),
              _CalendarLegendDot(
                color: AppTheme.gold,
                label: context.tr('registerIncomplete'),
              ),
              _CalendarLegendDot(
                color: AppTheme.mint,
                label: context.tr('registerComplete'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CalendarDay extends StatelessWidget {
  const _CalendarDay({
    required this.date,
    required this.hasLesson,
    required this.isComplete,
    required this.isPartial,
    required this.hasAbsence,
    required this.isSelected,
    required this.isToday,
    required this.onTap,
  });
  final DateTime date;
  final bool hasLesson;
  final bool isComplete;
  final bool isPartial;
  final bool hasAbsence;
  final bool isSelected;
  final bool isToday;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final fill = isSelected
        ? primary
        : isComplete
        ? (hasAbsence ? AppTheme.gold : AppTheme.mint).withValues(alpha: .13)
        : hasLesson
        ? primary.withValues(alpha: .09)
        : Colors.transparent;
    final locale = AppControllerScope.of(context).locale.languageCode;
    final status = !hasLesson
        ? ''
        : isComplete
        ? context.tr('registerComplete')
        : isPartial
        ? context.tr('registerIncomplete')
        : context.tr('scheduled');
    return Semantics(
      button: hasLesson,
      selected: isSelected,
      label: [
        DateFormat.yMMMMd(locale).format(date),
        status,
      ].where((part) => part.isNotEmpty).join(', '),
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: hasLesson ? onTap : null,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: isToday
                  ? Border.all(
                      color: isSelected ? Colors.white : primary,
                      width: 1.4,
                    )
                  : null,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${date.day}',
                  style: TextStyle(
                    color: isSelected
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                    fontWeight: hasLesson ? FontWeight.w800 : FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 4),
                if (hasLesson)
                  Container(
                    width: isComplete ? 13 : 5,
                    height: 5,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white
                          : isComplete
                          ? (hasAbsence ? AppTheme.gold : AppTheme.mint)
                          : isPartial
                          ? AppTheme.gold
                          : primary,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CalendarLegendDot extends StatelessWidget {
  const _CalendarLegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 9,
        height: 9,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 5),
      Text(label, style: Theme.of(context).textTheme.labelSmall),
    ],
  );
}

class _LessonHistoryRow extends StatelessWidget {
  const _LessonHistoryRow({
    required this.lesson,
    required this.records,
    required this.canMark,
    required this.onOpen,
    required this.onMark,
  });
  final LessonInfo lesson;
  final List<AttendanceRecordInfo> records;
  final bool canMark;
  final VoidCallback onOpen;
  final VoidCallback onMark;

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    final counts = _statusCounts(records);
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onOpen,
      child: Row(
        children: [
          Container(
            width: 47,
            height: 52,
            decoration: BoxDecoration(
              color: lesson.isCancelled
                  ? Theme.of(context).colorScheme.surfaceContainerHighest
                  : Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '${lesson.startsAt.toLocal().day}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                Text(
                  DateFormat.MMM(
                    locale,
                  ).format(lesson.startsAt.toLocal()).toUpperCase(),
                  style: Theme.of(
                    context,
                  ).textTheme.labelSmall?.copyWith(fontSize: 9),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lesson.title.isEmpty ? context.tr('lesson') : lesson.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    decoration: lesson.isCancelled
                        ? TextDecoration.lineThrough
                        : null,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat.Hm(locale).format(lesson.startsAt.toLocal())}${lesson.roomName.isEmpty ? '' : ' · ${lesson.roomName}'}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (records.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      _TinyCount(
                        value: counts['present'] ?? 0,
                        color: AppTheme.mint,
                        icon: Icons.check_rounded,
                        label: context.tr('present'),
                      ),
                      _TinyCount(
                        value: counts['absent'] ?? 0,
                        color: AppTheme.coral,
                        icon: Icons.close_rounded,
                        label: context.tr('absent'),
                      ),
                      if ((counts['late'] ?? 0) > 0) ...[
                        _TinyCount(
                          value: counts['late'] ?? 0,
                          color: AppTheme.gold,
                          icon: Icons.schedule_rounded,
                          label: context.tr('late'),
                        ),
                      ],
                      if (records.any((record) => record.cardType == 'smart'))
                        _TinyCount(
                          value: records
                              .where((record) => record.cardType == 'smart')
                              .length,
                          color: AppTheme.mint,
                          icon: Icons.star_rounded,
                          label: context.tr('smartCard'),
                        ),
                      if (records.any((record) => record.cardType == 'warning'))
                        _TinyCount(
                          value: records
                              .where((record) => record.cardType == 'warning')
                              .length,
                          color: AppTheme.coral,
                          icon: Icons.warning_amber_rounded,
                          label: context.tr('warningCard'),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (canMark)
            IconButton.filledTonal(
              tooltip: context.tr('takeAttendance'),
              onPressed: onMark,
              icon: const Icon(Icons.fact_check_outlined, size: 20),
            )
          else
            const Icon(Icons.chevron_right_rounded),
        ],
      ),
    );
  }
}

class _TinyCount extends StatelessWidget {
  const _TinyCount({
    required this.value,
    required this.color,
    required this.icon,
    required this.label,
  });
  final int value;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label: $value',
    child: ExcludeSemantics(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 2),
            Text(
              '$value',
              style: TextStyle(
                color: color,
                fontSize: 10,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.value,
    required this.color,
    required this.icon,
    required this.label,
  });
  final int value;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(
          '$value $label',
          style: TextStyle(
            color: color,
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _AttendanceStatus extends StatelessWidget {
  const _AttendanceStatus({required this.status});
  final String status;

  @override
  Widget build(BuildContext context) {
    final (color, icon) = switch (status) {
      'present' => (AppTheme.mint, Icons.check_rounded),
      'absent' => (AppTheme.coral, Icons.close_rounded),
      'late' => (AppTheme.gold, Icons.schedule_rounded),
      _ => (
        Theme.of(context).colorScheme.primary,
        Icons.favorite_outline_rounded,
      ),
    };
    return StatusPill(label: context.tr(status), color: color, icon: icon);
  }
}

class _IssuedCardPill extends StatelessWidget {
  const _IssuedCardPill({required this.cardType});

  final String cardType;

  @override
  Widget build(BuildContext context) {
    final warning = cardType == 'warning';
    final label = context.tr(warning ? 'warningCard' : 'smartCard');
    return Semantics(
      container: true,
      label: '${context.tr('feedbackCard')}: $label',
      child: ExcludeSemantics(
        child: _AdaptivePill(
          label: label,
          color: warning ? AppTheme.coral : AppTheme.mint,
          icon: warning ? Icons.warning_amber_rounded : Icons.star_rounded,
        ),
      ),
    );
  }
}

class _AdaptivePill extends StatelessWidget {
  const _AdaptivePill({required this.label, required this.color, this.icon});

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(18),
    ),
    child: Wrap(
      spacing: 5,
      runSpacing: 2,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (icon != null)
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface),
        Text(
          label,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
  );
}

class _ExamCard extends StatefulWidget {
  const _ExamCard({required this.exam, required this.canReadResults});
  final ExamInfo exam;
  final bool canReadResults;

  @override
  State<_ExamCard> createState() => _ExamCardState();
}

class _ExamCardState extends State<_ExamCard> {
  bool _expanded = false;
  Future<List<ExamResultInfo>>? _results;

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      if (_expanded && widget.canReadResults) {
        _results ??= AppControllerScope.of(
          context,
        ).loadExamResults(widget.exam.id);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    return PremiumCard(
      padding: EdgeInsets.zero,
      child: Column(
        children: [
          InkWell(
            onTap: _toggle,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: AppTheme.gold.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: const Icon(
                      Icons.workspace_premium_outlined,
                      color: Color(0xFFC47B16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.exam.title,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${DateFormat.yMMMd(locale).format(widget.exam.date.toLocal())} · ${context.trCount('pointsCount', widget.exam.maxScore.round())}',
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                        if (widget.exam.subjectName.isNotEmpty ||
                            widget.exam.typeName.isNotEmpty ||
                            widget.exam.termName.isNotEmpty) ...[
                          const SizedBox(height: 7),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (widget.exam.subjectName.isNotEmpty)
                                _AdaptivePill(
                                  label: widget.exam.subjectName,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              if (widget.exam.typeName.isNotEmpty)
                                _AdaptivePill(
                                  label: widget.exam.typeName,
                                  color: AppTheme.gold,
                                ),
                              if (widget.exam.termName.isNotEmpty)
                                _AdaptivePill(
                                  label: widget.exam.termName,
                                  color: AppTheme.mint,
                                ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _AdaptivePill(
                            label:
                                widget.exam.published &&
                                    !widget.exam.requiresRepublish
                                ? context.tr('published')
                                : context.tr('resultsPending'),
                            color:
                                widget.exam.published &&
                                    !widget.exam.requiresRepublish
                                ? AppTheme.mint
                                : AppTheme.gold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: _expanded ? .5 : 0,
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    child: const Icon(Icons.expand_more_rounded),
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 280),
            curve: Curves.easeOutCubic,
            child: !_expanded
                ? const SizedBox.shrink()
                : Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: !widget.canReadResults
                        ? Text(
                            context.tr('resultsViewLimited'),
                            style: Theme.of(context).textTheme.bodySmall,
                          )
                        : FutureBuilder<List<ExamResultInfo>>(
                            future: _results,
                            builder: (context, snapshot) {
                              if (snapshot.connectionState ==
                                  ConnectionState.waiting) {
                                return const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: Center(
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.2,
                                    ),
                                  ),
                                );
                              }
                              if (snapshot.hasError) {
                                return Text(context.tr('resultsNeedMoment'));
                              }
                              final results = snapshot.data ?? const [];
                              if (results.isEmpty) {
                                return Text(context.tr('resultsPending'));
                              }
                              return Column(
                                children: results
                                    .map(
                                      (result) => _ExamResultRow(
                                        result: result,
                                        examMaxScore: widget.exam.maxScore,
                                      ),
                                    )
                                    .toList(),
                              );
                            },
                          ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ExamResultRow extends StatelessWidget {
  const _ExamResultRow({required this.result, required this.examMaxScore});

  final ExamResultInfo result;
  final double examMaxScore;

  @override
  Widget build(BuildContext context) {
    final overall =
        '${_formatScore(result.score)} / ${_formatScore(examMaxScore)}';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PersonAvatar(name: result.studentName, size: 38),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  result.studentName,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                const SizedBox(height: 5),
                Semantics(
                  container: true,
                  label: '${context.tr('overallScore')}: $overall',
                  child: ExcludeSemantics(
                    child: _AdaptivePill(
                      label: '${context.tr('overallScore')} · $overall',
                      color: Theme.of(context).colorScheme.primary,
                      icon: Icons.assessment_outlined,
                    ),
                  ),
                ),
                if (result.note.trim().isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    result.note,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (result.components.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    context.tr('skillBreakdown'),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 7),
                  ...result.components.map(
                    (component) => _SkillScoreRow(component: component),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SkillScoreRow extends StatelessWidget {
  const _SkillScoreRow({required this.component});

  final ExamSkillComponentInfo component;

  @override
  Widget build(BuildContext context) {
    final value =
        '${_formatScore(component.score)} / ${_formatScore(component.maxScore)}';
    return Semantics(
      container: true,
      label: '${component.name}: $value',
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.only(bottom: 9),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < 260 ||
                      MediaQuery.textScalerOf(context).scale(1) > 1.4;
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          component.name,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          value,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(
                        child: Text(
                          component.name,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        value,
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 5),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: component.fraction,
                  minHeight: 5,
                  backgroundColor: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceSkeleton extends StatelessWidget {
  const _AttendanceSkeleton();

  @override
  Widget build(BuildContext context) => MaxWidthBox(
    maxWidth: 900,
    child: Column(
      children: [
        Container(
          height: 260,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        const SizedBox(height: 14),
        for (var index = 0; index < 3; index++) ...[
          Container(
            height: 76,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: .7 - index * .1),
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          const SizedBox(height: 9),
        ],
      ],
    ),
  );
}

class _AttendanceLoadState extends StatelessWidget {
  const _AttendanceLoadState({required this.onRetry, this.exams = false});
  final VoidCallback onRetry;
  final bool exams;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              exams
                  ? Icons.workspace_premium_outlined
                  : Icons.calendar_month_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 31,
            ),
          ),
          const SizedBox(height: 17),
          Text(
            context.tr(exams ? 'examsNeedMoment' : 'attendanceNeedMoment'),
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

class _InlineLoadWarning extends StatelessWidget {
  const _InlineLoadWarning({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsetsDirectional.fromSTEB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: AppTheme.gold.withValues(alpha: .1),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppTheme.gold.withValues(alpha: .24)),
    ),
    child: Row(
      children: [
        const Icon(Icons.sync_problem_rounded, color: AppTheme.gold),
        const SizedBox(width: 10),
        Expanded(child: Text(context.tr('showingPreviousData'))),
        TextButton(onPressed: onRetry, child: Text(context.tr('tryAgain'))),
      ],
    ),
  );
}

class TakeAttendancePage extends StatefulWidget {
  const TakeAttendancePage({
    super.key,
    required this.group,
    required this.lesson,
    this.initialRecords = const [],
  });
  final LearningGroup group;
  final LessonInfo lesson;
  final List<AttendanceRecordInfo> initialRecords;

  @override
  State<TakeAttendancePage> createState() => _TakeAttendancePageState();
}

class _TakeAttendancePageState extends State<TakeAttendancePage> {
  late LearningGroup _group = widget.group;
  final Map<String, StudentState> _states = {};
  final Map<String, String> _cards = {};
  bool _loading = false;
  bool _saving = false;
  String? _error;
  bool _started = false;
  bool _saved = false;

  bool get _hasChanges {
    if (_saved) return false;
    final initialByStudent = {
      for (final record in widget.initialRecords)
        '${record.studentId}': _stateFromStatus(record.status),
    };
    final initialCards = {
      for (final record in widget.initialRecords)
        '${record.studentId}': record.cardType,
    };
    return _states.entries.any(
          (entry) =>
              entry.value !=
              (initialByStudent[entry.key] ?? StudentState.unmarked),
        ) ||
        _cards.entries.any(
          (entry) => entry.value != (initialCards[entry.key] ?? ''),
        );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _initialize();
  }

  Future<void> _initialize() async {
    final loadErrorMessage = context.tr('attendanceNeedMoment');
    setState(() => _loading = true);
    try {
      if (_group.students.isEmpty) {
        _group = await AppControllerScope.of(context).loadGroupDetails(_group);
      }
      final recordByStudent = {
        for (final record in widget.initialRecords)
          '${record.studentId}': record,
      };
      for (final student in _group.students) {
        final existing = recordByStudent[student.id];
        _states[student.id] = existing == null
            ? StudentState.unmarked
            : _stateFromStatus(existing.status);
        _cards[student.id] = existing?.cardType ?? '';
      }
    } catch (_) {
      _error = loadErrorMessage;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _save() async {
    if (_saving || _group.students.isEmpty) return;
    final unmarked = _states.values
        .where((state) => state == StudentState.unmarked)
        .length;
    if (unmarked > 0) {
      setState(
        () => _error = context.l10n.format('studentsStillUnmarked', {
          'count': unmarked,
        }),
      );
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final records = <Map<String, Object?>>[];
    for (final student in _group.students) {
      final id = int.tryParse(student.id);
      if (id == null) continue;
      final state = _states[student.id] ?? StudentState.unmarked;
      if (state == StudentState.unmarked) continue;
      records.add({
        'student': id,
        'status': _statusFromState(state),
        // Sending blank is intentional: it clears a previously issued card.
        'card_type': _cards[student.id] ?? '',
      });
    }
    try {
      await AppControllerScope.of(
        context,
      ).saveAttendance(widget.lesson.id, records);
      if (!mounted) return;
      _saved = true;
      showPremiumToast(context, context.tr('attendanceSaved'));
      Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = context.tr('attendanceSaveFailed');
      });
    }
  }

  void _markAllPresent() {
    setState(() {
      for (final student in _group.students) {
        _states[student.id] = StudentState.present;
      }
    });
  }

  Future<bool> _confirmDiscard() async {
    if (!_hasChanges || _saving) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(context.tr('unsavedAttendanceTitle')),
        content: Text(context.tr('unsavedAttendanceBody')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(context.tr('continueEditing')),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(context.tr('discardChanges')),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    final markedCount = _states.values
        .where((state) => state != StudentState.unmarked)
        .length;
    return PopScope<Object?>(
      canPop: !_hasChanges || _saving,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.tr('takeAttendance')),
          actions: [
            IconButton(
              tooltip: context.tr('allPresent'),
              onPressed: _loading || _saving ? null : _markAllPresent,
              icon: const Icon(Icons.done_all_rounded),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(
                            Icons.fact_check_outlined,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Text(
                              widget.group.name,
                              style: Theme.of(context).textTheme.titleMedium
                                  ?.copyWith(color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 9),
                      Text(
                        DateFormat.yMMMEd(
                          locale,
                        ).add_Hm().format(widget.lesson.startsAt.toLocal()),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .76),
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 9),
                      Semantics(
                        label:
                            '${context.tr('students')}: $markedCount / ${_group.students.length}',
                        child: ExcludeSemantics(
                          child: Text(
                            '$markedCount / ${_group.students.length}',
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppTheme.coral.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Text(
                      _error!,
                      style: const TextStyle(color: AppTheme.coral),
                    ),
                  ),
                ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _group.students.isEmpty
                    ? EmptyState(
                        title: context.tr('noStudentsYet'),
                        body: context.tr('noStudentsYetBody'),
                        icon: Icons.groups_outlined,
                      )
                    : ListView.separated(
                        physics: const BouncingScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(20, 4, 20, 22),
                        itemCount: _group.students.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 9),
                        itemBuilder: (context, index) {
                          final student = _group.students[index];
                          return _AttendanceStudentCard(
                            student: student,
                            state: _states[student.id] ?? StudentState.unmarked,
                            cardType: _cards[student.id] ?? '',
                            onChanged: (state) => setState(() {
                              _states[student.id] = state;
                              _error = null;
                            }),
                            onCardChanged: (cardType) => setState(() {
                              _cards[student.id] = cardType;
                              _error = null;
                            }),
                          );
                        },
                      ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  20,
                  10,
                  20,
                  12 + MediaQuery.paddingOf(context).bottom,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        _loading ||
                            _saving ||
                            _group.students.isEmpty ||
                            markedCount != _group.students.length
                        ? null
                        : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 19,
                            height: 19,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_done_outlined),
                    label: Text(context.tr('saveAttendance')),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceStudentCard extends StatelessWidget {
  const _AttendanceStudentCard({
    required this.student,
    required this.state,
    required this.cardType,
    required this.onChanged,
    required this.onCardChanged,
  });
  final Student student;
  final StudentState state;
  final String cardType;
  final ValueChanged<StudentState> onChanged;
  final ValueChanged<String> onCardChanged;

  @override
  Widget build(BuildContext context) => PremiumCard(
    padding: const EdgeInsets.all(13),
    child: Column(
      children: [
        Row(
          children: [
            PersonAvatar(name: student.name, size: 42),
            const SizedBox(width: 11),
            Expanded(
              child: Text(
                student.name,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            _StateIcon(state: state),
          ],
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: StudentState.values
                .where((value) => value != StudentState.unmarked)
                .map(
                  (value) => ChoiceChip(
                    selected: state == value,
                    onSelected: (_) => onChanged(value),
                    avatar: Icon(_stateIcon(value), size: 16),
                    label: Text(context.tr(_statusFromState(value))),
                  ),
                )
                .toList(),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Text(
            context.tr('feedbackCard'),
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: 7),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: Wrap(
            spacing: 7,
            runSpacing: 7,
            children: ['', 'smart', 'warning'].map((value) {
              final warning = value == 'warning';
              final smart = value == 'smart';
              return ChoiceChip(
                selected: cardType == value,
                onSelected: (_) => onCardChanged(value),
                avatar: Icon(
                  warning
                      ? Icons.warning_amber_rounded
                      : smart
                      ? Icons.star_rounded
                      : Icons.remove_circle_outline_rounded,
                  size: 16,
                ),
                label: Text(
                  context.tr(
                    warning
                        ? 'warningCard'
                        : smart
                        ? 'smartCard'
                        : 'noCard',
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    ),
  );
}

class _StateIcon extends StatelessWidget {
  const _StateIcon({required this.state});
  final StudentState state;

  @override
  Widget build(BuildContext context) {
    final color = switch (state) {
      StudentState.unmarked => Theme.of(context).colorScheme.outline,
      StudentState.present => AppTheme.mint,
      StudentState.absent => AppTheme.coral,
      StudentState.late => AppTheme.gold,
      StudentState.excused => Theme.of(context).colorScheme.primary,
    };
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .11),
        shape: BoxShape.circle,
      ),
      child: Icon(_stateIcon(state), color: color, size: 18),
    );
  }
}

Map<String, int> _statusCounts(List<AttendanceRecordInfo> records) {
  final result = <String, int>{};
  for (final record in records) {
    result[record.status] = (result[record.status] ?? 0) + 1;
  }
  return result;
}

bool _sameDay(DateTime? first, DateTime? second) =>
    first != null &&
    second != null &&
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String _statusFromState(StudentState state) => switch (state) {
  StudentState.unmarked => 'unmarked',
  StudentState.present => 'present',
  StudentState.absent => 'absent',
  StudentState.late => 'late',
  StudentState.excused => 'excused',
};

StudentState _stateFromStatus(String status) => switch (status) {
  'present' => StudentState.present,
  'absent' => StudentState.absent,
  'late' => StudentState.late,
  'excused' => StudentState.excused,
  _ => StudentState.unmarked,
};

IconData _stateIcon(StudentState state) => switch (state) {
  StudentState.unmarked => Icons.radio_button_unchecked_rounded,
  StudentState.present => Icons.check_rounded,
  StudentState.absent => Icons.close_rounded,
  StudentState.late => Icons.schedule_rounded,
  StudentState.excused => Icons.favorite_outline_rounded,
};

String _compactCountdown(Duration value) {
  if (value.isNegative) return '0:00';
  final hours = value.inHours;
  final minutes = value.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = value.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

String _formatScore(double value) =>
    value.toStringAsFixed(value % 1 == 0 ? 0 : 1);

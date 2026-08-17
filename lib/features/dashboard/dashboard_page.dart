import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/remote_models.dart';
import '../groups/attendance_page.dart';
import '../library/library_page.dart';
import '../print/print_page.dart';
import 'notifications_page.dart';

class _LoadResult<T> {
  const _LoadResult.value(this.value) : error = null;
  const _LoadResult.error(this.error) : value = null;

  final T? value;
  final Object? error;
}

Future<_LoadResult<T>> _capture<T>(Future<T> Function() operation) async {
  try {
    return _LoadResult<T>.value(await operation());
  } catch (error) {
    return _LoadResult<T>.error(error);
  }
}

class DashboardPage extends StatefulWidget {
  const DashboardPage({super.key, required this.onNavigate});
  final ValueChanged<int> onNavigate;

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  TeacherDashboardData? _dashboard;
  List<LearningGroup> _groups = const [];
  List<NotificationInfo>? _notifications;
  int? _unreadCount;
  List<FeatureAvailabilityInfo>? _availability;
  bool _loading = false;
  bool _started = false;
  Object? _dashboardError;
  Object? _groupsError;
  Object? _notificationsError;
  Object? _availabilityError;
  int _motivationIndex = DateTime.now().millisecondsSinceEpoch % 4;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _loading = true;
      _motivationIndex = (_motivationIndex + 1) % 4;
    });
    final controller = AppControllerScope.of(context);
    final dashboardCall = _capture(controller.loadTeacherDashboard);
    final groupsCall = _capture(() => controller.loadGroups(refresh: true));
    final notificationsCall = _capture(controller.loadNotifications);
    final unreadCall = _capture(controller.loadUnreadNotificationCount);
    final availabilityCall = _capture(controller.loadFeatureAvailability);
    final results = await Future.wait<Object?>([
      dashboardCall,
      groupsCall,
      notificationsCall,
      unreadCall,
      availabilityCall,
    ]);
    if (!mounted) return;
    final dashboard = results[0] as _LoadResult<TeacherDashboardData?>;
    final groups = results[1] as _LoadResult<List<LearningGroup>>;
    final notifications = results[2] as _LoadResult<List<NotificationInfo>>;
    final unread = results[3] as _LoadResult<int>;
    final availability =
        results[4] as _LoadResult<List<FeatureAvailabilityInfo>>;
    setState(() {
      if (dashboard.error == null) _dashboard = dashboard.value;
      _dashboardError = dashboard.error;
      if (groups.error == null) _groups = groups.value ?? const [];
      _groupsError = groups.error;
      if (notifications.error == null) {
        _notifications = notifications.value ?? const [];
      }
      _notificationsError = notifications.error;
      if (unread.error == null) _unreadCount = unread.value;
      if (availability.error == null) {
        _availability = availability.value ?? const [];
      }
      _availabilityError = availability.error;
      _loading = false;
    });
  }

  String _greeting(BuildContext context) {
    final hour = DateTime.now().hour;
    if (hour < 12) return context.tr('goodMorning');
    if (hour < 18) return context.tr('goodAfternoon');
    return context.tr('goodEvening');
  }

  String _motivation(BuildContext context) {
    return context.tr('motivation${_motivationIndex + 1}');
  }

  LearningGroup? _groupFor(LessonInfo lesson) {
    for (final group in _groups) {
      if (lesson.cohortId != 0 && group.remoteId == lesson.cohortId) {
        return group;
      }
      if (lesson.cohortName.isNotEmpty && group.name == lesson.cohortName) {
        return group;
      }
    }
    return null;
  }

  void _openAttendanceFor(LessonInfo lesson) {
    final group = _groupFor(lesson);
    if (group == null) {
      widget.onNavigate(1);
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => AttendancePage(group: group)));
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  FeatureAvailabilityInfo? _feature(String name) {
    for (final feature in _availability ?? const <FeatureAvailabilityInfo>[]) {
      if (feature.feature == name) return feature;
    }
    return null;
  }

  FeatureAvailabilityStatus? _featureStatus(String name) =>
      _feature(name)?.status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppControllerScope.of(context);
    final firstName = controller.displayName.split(' ').first;
    final nextLessons = _dashboard?.nextLessons ?? const <LessonInfo>[];
    final nextLesson = nextLessons.isEmpty ? null : nextLessons.first;
    final announcements = (_notifications ?? const <NotificationInfo>[])
        .where((item) => item.eventType.toLowerCase().contains('announcement'))
        .toList(growable: false);
    final announcement = announcements.isEmpty ? null : announcements.first;
    final unread =
        _unreadCount ??
        (_notifications ?? const <NotificationInfo>[])
            .where((item) => !item.isRead)
            .length;
    final hasDashboardData = _dashboard != null;
    final dashboardNeedsAttention =
        _dashboardError != null || _groupsError != null;
    final canReadAttendance = controller.can('attendance:read');
    final canReadTasks = controller.can('tasks:read');
    final canReadLibrary = controller.can('content:read');
    final canReadPrinting = controller.can('printing:read');
    final hasQuickActions =
        canReadAttendance || canReadTasks || canReadLibrary || canReadPrinting;
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator.adaptive(
          onRefresh: _refresh,
          child: CustomScrollView(
            key: const PageStorageKey('dashboardScroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_greeting(context)}, $firstName',
                                style: theme.textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                DateFormat(
                                  'EEEE, d MMMM',
                                  controller.locale.languageCode,
                                ).format(DateTime.now()),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton.filledTonal(
                          tooltip: context.tr('notifications'),
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => const NotificationsPage(),
                              ),
                            );
                            if (mounted) _refresh();
                          },
                          icon: Badge.count(
                            count: unread,
                            isLabelVisible: unread > 0,
                            child: const Icon(Icons.notifications_none_rounded),
                          ),
                        ),
                        const SizedBox(width: 10),
                        IconButton(
                          tooltip: context.tr('profile'),
                          onPressed: () => widget.onNavigate(4),
                          iconSize: 45,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 48,
                            height: 48,
                          ),
                          icon: PersonAvatar(
                            name: controller.displayName,
                            size: 45,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: FadeSlideIn(
                    child: _MotivationCard(
                      quote: _motivation(context),
                      role:
                          controller.role == StaffRole.staff &&
                              controller.roleDisplayName.isNotEmpty
                          ? controller.roleDisplayName
                          : context.tr(controller.localizedRoleKey),
                    ),
                  ),
                ),
              ),
              if (_notificationsError != null && _notifications != null) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 13)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: _CompactSyncNotice(
                      text: context.tr('notificationsStale'),
                      onTap: () => _open(const NotificationsPage()),
                    ),
                  ),
                ),
              ],
              if (dashboardNeedsAttention) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 13)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: _DashboardNotice(onRetry: _refresh),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              if (_loading && !hasDashboardData)
                const SliverToBoxAdapter(
                  child: MaxWidthBox(child: _DashboardSkeleton()),
                )
              else if (nextLesson != null)
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: FadeSlideIn(
                      delay: const Duration(milliseconds: 70),
                      child: _NextLessonCard(
                        lesson: nextLesson,
                        group: _groupFor(nextLesson),
                        onTap: () => _openAttendanceFor(nextLesson),
                      ),
                    ),
                  ),
                )
              else if (hasDashboardData)
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: _CalmScheduleState(
                      onOpenGroups: () => widget.onNavigate(1),
                    ),
                  ),
                ),
              if (hasQuickActions) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 25)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: SectionHeader(title: context.tr('quickActions')),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: _QuickActions(
                      onAttendance: canReadAttendance
                          ? nextLesson == null
                                ? () => widget.onNavigate(1)
                                : () => _openAttendanceFor(nextLesson)
                          : null,
                      onTasks: canReadTasks ? () => widget.onNavigate(2) : null,
                      onLibrary: canReadLibrary
                          ? () => _open(const LibraryPage())
                          : null,
                      onPrint: canReadPrinting
                          ? () => _open(const PrintPage())
                          : null,
                      attendanceStatus: _featureStatus('attendance'),
                      tasksStatus: _featureStatus('tasks'),
                      libraryStatus: _featureStatus('library'),
                      printingStatus: _featureStatus('printing'),
                    ),
                  ),
                ),
              ],
              if (hasDashboardData) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 26)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: _OverviewMetrics(
                      groups: _dashboard!.groupsCount,
                      students: _dashboard!.studentsCount,
                      upcomingLessons: nextLessons.length,
                    ),
                  ),
                ),
              ],
              if ((_dashboard?.nextMeeting ?? const {}).isNotEmpty) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 26)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: _MeetingCard(meeting: _dashboard!.nextMeeting),
                  ),
                ),
              ],
              if (hasDashboardData) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 26)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: SectionHeader(
                      title: context.tr('upcomingSchedule'),
                      action: context.tr('seeAll'),
                      onAction: () => widget.onNavigate(1),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: nextLessons.isEmpty
                        ? _InlineEmpty(text: context.tr('noUpcomingLessons'))
                        : _ScheduleCard(
                            lessons: nextLessons,
                            onLesson: _openAttendanceFor,
                          ),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: _AiInsightCard(
                    availability: _feature('ai'),
                    statusUnavailable: _availabilityError != null,
                    onRetry: _refresh,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: SectionHeader(title: context.tr('announcements')),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: announcement == null
                      ? _notifications == null && _notificationsError != null
                            ? _InlineActionState(
                                text: context.tr('notificationsLoadFailed'),
                                action: context.tr('tryAgain'),
                                onAction: _refresh,
                              )
                            : _notifications == null
                            ? const _AnnouncementSkeleton()
                            : _InlineEmpty(text: context.tr('noAnnouncements'))
                      : _AnnouncementCard(
                          notification: announcement,
                          onTap: () => _open(const NotificationsPage()),
                        ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 34)),
            ],
          ),
        ),
      ),
    );
  }
}

class _MotivationCard extends StatelessWidget {
  const _MotivationCard({required this.quote, required this.role});
  final String quote;
  final String role;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return Container(
      decoration: BoxDecoration(
        color: primary,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          PositionedDirectional(
            end: -45,
            top: -64,
            child: Container(
              width: 175,
              height: 175,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: .09),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .15),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 15),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        quote,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: Colors.white,
                          height: 1.35,
                        ),
                      ),
                      if (role.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .13),
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            role,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: Colors.white.withValues(alpha: .86),
                              fontWeight: FontWeight.w700,
                            ),
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
      ),
    );
  }
}

class _NextLessonCard extends StatelessWidget {
  const _NextLessonCard({
    required this.lesson,
    required this.group,
    required this.onTap,
  });
  final LessonInfo lesson;
  final LearningGroup? group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = AppControllerScope.of(context).locale.languageCode;
    final difference = lesson.startsAt.difference(DateTime.now());
    final startsIn = difference.isNegative
        ? context.tr('inProgress')
        : difference.inHours > 0
        ? context.l10n.format('durationHoursMinutes', {
            'hours': difference.inHours,
            'minutes': difference.inMinutes.remainder(60),
          })
        : context.l10n.format('durationMinutes', {
            'minutes': difference.inMinutes.clamp(1, 59),
          });
    return PremiumCard(
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: Stack(
        children: [
          Positioned(
            right: -28,
            top: -30,
            child: Container(
              width: 160,
              height: 160,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer.withValues(alpha: .6),
                shape: BoxShape.circle,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    StatusPill(
                      label: context.tr('nextLesson'),
                      color: theme.colorScheme.primary,
                      icon: Icons.schedule_rounded,
                    ),
                    const Spacer(),
                    Text(
                      context.l10n.format('startsIn', {'time': startsIn}),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 19),
                Text(
                  lesson.cohortName.isEmpty
                      ? group?.name ?? context.tr('lesson')
                      : lesson.cohortName,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  lesson.title.isEmpty ? context.tr('lesson') : lesson.title,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 18),
                Wrap(
                  spacing: 9,
                  runSpacing: 9,
                  children: [
                    _InfoChip(
                      icon: Icons.access_time_rounded,
                      text:
                          '${DateFormat.Hm(locale).format(lesson.startsAt.toLocal())} – ${DateFormat.Hm(locale).format(lesson.endsAt.toLocal())}',
                    ),
                    if ((lesson.roomName.isNotEmpty ||
                        group?.room.isNotEmpty == true))
                      _InfoChip(
                        icon: Icons.meeting_room_outlined,
                        text: lesson.roomName.isEmpty
                            ? group!.room
                            : lesson.roomName,
                      ),
                    if (group != null && group!.students.isNotEmpty)
                      _InfoChip(
                        icon: Icons.groups_outlined,
                        text: context.trCount(
                          'studentsCount',
                          group!.students.length,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 19),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: onTap,
                    icon: const Icon(Icons.calendar_month_outlined),
                    label: Text(context.tr('openAttendance')),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
    decoration: BoxDecoration(
      color: Theme.of(
        context,
      ).colorScheme.surfaceContainerHighest.withValues(alpha: .55),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 6),
        Text(text, style: Theme.of(context).textTheme.labelMedium),
      ],
    ),
  );
}

class _QuickActions extends StatelessWidget {
  const _QuickActions({
    required this.onAttendance,
    required this.onTasks,
    required this.onLibrary,
    required this.onPrint,
    required this.attendanceStatus,
    required this.tasksStatus,
    required this.libraryStatus,
    required this.printingStatus,
  });
  final VoidCallback? onAttendance;
  final VoidCallback? onTasks;
  final VoidCallback? onLibrary;
  final VoidCallback? onPrint;
  final FeatureAvailabilityStatus? attendanceStatus;
  final FeatureAvailabilityStatus? tasksStatus;
  final FeatureAvailabilityStatus? libraryStatus;
  final FeatureAvailabilityStatus? printingStatus;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final actions =
        <(IconData, String, Color, VoidCallback, FeatureAvailabilityStatus?)>[
          if (onAttendance != null)
            (
              Icons.fact_check_outlined,
              context.tr('takeAttendance'),
              primary,
              onAttendance!,
              attendanceStatus,
            ),
          if (onTasks != null)
            (
              Icons.task_alt_rounded,
              context.tr('openTasks'),
              const Color(0xFF238B75),
              onTasks!,
              tasksStatus,
            ),
          if (onLibrary != null)
            (
              Icons.local_library_outlined,
              context.tr('library'),
              const Color(0xFF1F6B66),
              onLibrary!,
              libraryStatus,
            ),
          if (onPrint != null)
            (
              Icons.print_outlined,
              context.tr('printCenter'),
              const Color(0xFFC57D35),
              onPrint!,
              printingStatus,
            ),
        ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final preferredColumns = constraints.maxWidth >= 700 ? 4 : 2;
        final columns = actions.length < preferredColumns
            ? actions.length
            : preferredColumns;
        final width = (constraints.maxWidth - (columns - 1) * 12) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: actions
              .map(
                (action) => SizedBox(
                  width: width,
                  child: PremiumCard(
                    padding: const EdgeInsets.all(15),
                    onTap: () {
                      if (action.$5 == FeatureAvailabilityStatus.unavailable) {
                        showPremiumToast(
                          context,
                          context.tr('featureUnavailablePolite'),
                          icon: Icons.pause_circle_outline_rounded,
                          color: AppTheme.coral,
                        );
                        return;
                      }
                      action.$4();
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: action.$3.withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(13),
                              ),
                              child: Icon(
                                action.$1,
                                color: action.$3,
                                size: 21,
                              ),
                            ),
                            const Spacer(),
                            if (action.$5 == FeatureAvailabilityStatus.degraded)
                              Icon(
                                Icons.timelapse_rounded,
                                size: 19,
                                color: AppTheme.gold,
                                semanticLabel: context.tr('featureDegraded'),
                              )
                            else if (action.$5 ==
                                FeatureAvailabilityStatus.unavailable)
                              Icon(
                                Icons.pause_circle_outline_rounded,
                                size: 19,
                                color: AppTheme.coral,
                                semanticLabel: context.tr('featureUnavailable'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 13),
                        Text(
                          action.$2,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge,
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

class _OverviewMetrics extends StatelessWidget {
  const _OverviewMetrics({
    required this.groups,
    required this.students,
    required this.upcomingLessons,
  });
  final int groups;
  final int? students;
  final int upcomingLessons;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final metrics = [
      ('$groups', context.tr('groups'), Icons.groups_outlined, primary),
      (
        students?.toString() ?? '—',
        context.tr('students'),
        Icons.people_alt_outlined,
        const Color(0xFF258C76),
      ),
      (
        '$upcomingLessons',
        context.tr('upcoming'),
        Icons.event_available_outlined,
        AppTheme.gold,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 620 ? 3 : 1;
        final width = (constraints.maxWidth - (columns - 1) * 10) / columns;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
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
              .toList(growable: false),
        );
      },
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.meeting});
  final Map<String, dynamic> meeting;

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    final starts = jsonDate(meeting['starts_at']);
    final detail = [
      if (starts != null)
        DateFormat.yMMMEd(locale).add_Hm().format(starts.toLocal()),
      jsonString(meeting['location']),
    ].where((value) => value.isNotEmpty).join(' · ');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.coral.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: AppTheme.coral.withValues(alpha: .22)),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: AppTheme.coral.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.campaign_outlined, color: AppTheme.coral),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StatusPill(
                  label: context.tr('important'),
                  color: AppTheme.coral,
                ),
                const SizedBox(height: 8),
                Text(
                  jsonString(meeting['title'], context.tr('meeting')),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                if (detail.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(
                    detail,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
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

class _ScheduleCard extends StatelessWidget {
  const _ScheduleCard({required this.lessons, required this.onLesson});
  final List<LessonInfo> lessons;
  final ValueChanged<LessonInfo> onLesson;

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    return PremiumCard(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Column(
        children: lessons.take(5).map((lesson) {
          final color = [
            Theme.of(context).colorScheme.primary,
            const Color(0xFF1F6B66),
            AppTheme.gold,
          ][lesson.id.abs() % 3];
          return InkWell(
            onTap: () => onLesson(lesson),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
              child: Row(
                children: [
                  SizedBox(
                    width: 52,
                    child: Text(
                      DateFormat.Hm(locale).format(lesson.startsAt.toLocal()),
                      style: Theme.of(
                        context,
                      ).textTheme.labelLarge?.copyWith(color: color),
                    ),
                  ),
                  Container(
                    width: 3,
                    height: 48,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          lesson.cohortName.isEmpty
                              ? lesson.title
                              : lesson.cohortName,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                            lesson.title,
                            lesson.roomName,
                          ].where((value) => value.isNotEmpty).join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right_rounded),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _AiInsightCard extends StatelessWidget {
  const _AiInsightCard({
    required this.availability,
    required this.statusUnavailable,
    required this.onRetry,
  });

  final FeatureAvailabilityInfo? availability;
  final bool statusUnavailable;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = availability?.status;
    final statusColor = switch (status) {
      FeatureAvailabilityStatus.available => const Color(0xFF237A68),
      FeatureAvailabilityStatus.degraded => const Color(0xFFA96916),
      FeatureAvailabilityStatus.unavailable => AppTheme.coral,
      null => theme.colorScheme.onSurfaceVariant,
    };
    final statusLabel = switch (status) {
      FeatureAvailabilityStatus.available => context.tr('featureAvailable'),
      FeatureAvailabilityStatus.degraded => context.tr('featureDegraded'),
      FeatureAvailabilityStatus.unavailable => context.tr('featureUnavailable'),
      null => context.tr('featureStatusUnknown'),
    };
    final message = switch (status) {
      FeatureAvailabilityStatus.available => context.tr('aiNoRecommendations'),
      FeatureAvailabilityStatus.degraded => context.tr('aiDegraded'),
      FeatureAvailabilityStatus.unavailable => context.tr('aiUnavailable'),
      null =>
        statusUnavailable
            ? context.tr('aiStatusUnavailable')
            : context.tr('aiStatusChecking'),
    };
    return PremiumCard(
      color: Color.alphaBlend(
        theme.colorScheme.primary.withValues(alpha: .035),
        theme.colorScheme.surface,
      ),
      border: BorderSide(
        color: theme.colorScheme.primary.withValues(alpha: .22),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final compact =
                  constraints.maxWidth < 330 ||
                  MediaQuery.textScalerOf(context).scale(1) > 1.4;
              final heading = Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome_rounded,
                      color: Colors.white,
                      size: 21,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('aiInsight'),
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              );
              final pill = StatusPill(
                label: statusLabel,
                color: statusColor,
                icon: compact
                    ? null
                    : switch (status) {
                        FeatureAvailabilityStatus.available =>
                          Icons.check_circle_outline_rounded,
                        FeatureAvailabilityStatus.degraded =>
                          Icons.timelapse_rounded,
                        FeatureAvailabilityStatus.unavailable =>
                          Icons.pause_circle_outline_rounded,
                        null => Icons.help_outline_rounded,
                      },
              );
              if (compact) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [heading, const SizedBox(height: 12), pill],
                );
              }
              return Row(
                children: [
                  Expanded(child: heading),
                  const SizedBox(width: 12),
                  pill,
                ],
              );
            },
          ),
          const SizedBox(height: 16),
          if (status == FeatureAvailabilityStatus.available)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline_rounded, color: statusColor),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Text(
                      message,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            )
          else
            Stack(
              alignment: Alignment.center,
              children: [
                ExcludeSemantics(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                    child: Opacity(
                      opacity: .24,
                      child: Column(
                        children: const [
                          _InsightPlaceholderBar(widthFactor: 1),
                          SizedBox(height: 9),
                          _InsightPlaceholderBar(widthFactor: .82),
                          SizedBox(height: 9),
                          _InsightPlaceholderBar(widthFactor: .58),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface.withValues(alpha: .9),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    message,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          if (status == null ||
              status == FeatureAvailabilityStatus.unavailable) ...[
            const SizedBox(height: 12),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(context.tr('tryAgain')),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _InsightPlaceholderBar extends StatelessWidget {
  const _InsightPlaceholderBar({required this.widthFactor});

  final double widthFactor;

  @override
  Widget build(BuildContext context) => FractionallySizedBox(
    alignment: AlignmentDirectional.centerStart,
    widthFactor: widthFactor,
    child: Container(
      height: 17,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(99),
      ),
    ),
  );
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.notification, required this.onTap});

  final NotificationInfo notification;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
    onTap: onTap,
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 58,
          decoration: BoxDecoration(
            color: const Color(0xFF4F6DB8).withValues(alpha: .13),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.campaign_outlined, color: Color(0xFF4F6DB8)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                notification.title.isEmpty
                    ? notification.body
                    : notification.title,
                style: Theme.of(
                  context,
                ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                notification.title.isEmpty || notification.body.isEmpty
                    ? DateFormat.yMMMd(
                        Localizations.localeOf(context).toLanguageTag(),
                      ).format(notification.createdAt.toLocal())
                    : notification.body,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        Icon(
          Icons.arrow_forward_rounded,
          size: 20,
          color: Theme.of(context).colorScheme.primary,
        ),
      ],
    ),
  );
}

class _CalmScheduleState extends StatelessWidget {
  const _CalmScheduleState({required this.onOpenGroups});
  final VoidCallback onOpenGroups;

  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Row(
      children: [
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: AppTheme.mint.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(17),
          ),
          child: const Icon(Icons.wb_sunny_outlined, color: Color(0xFF278B72)),
        ),
        const SizedBox(width: 13),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('noUpcomingLessons'),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 3),
              Text(
                context.tr('noUpcomingLessonsBody'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: onOpenGroups,
          icon: const Icon(Icons.arrow_forward_rounded),
        ),
      ],
    ),
  );
}

class _InlineEmpty extends StatelessWidget {
  const _InlineEmpty({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Row(
      children: [
        Icon(
          Icons.event_available_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 11),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

class _InlineActionState extends StatelessWidget {
  const _InlineActionState({
    required this.text,
    required this.action,
    required this.onAction,
  });

  final String text;
  final String action;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Row(
      children: [
        Icon(
          Icons.notifications_paused_outlined,
          color: Theme.of(context).colorScheme.primary,
        ),
        const SizedBox(width: 11),
        Expanded(child: Text(text)),
        TextButton(onPressed: onAction, child: Text(action)),
      ],
    ),
  );
}

class _CompactSyncNotice extends StatelessWidget {
  const _CompactSyncNotice({required this.text, required this.onTap});

  final String text;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
    color: AppTheme.gold.withValues(alpha: .09),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(16),
      side: BorderSide(color: AppTheme.gold.withValues(alpha: .2)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.sync_problem_rounded,
              size: 19,
              color: Color(0xFF9A641C),
            ),
            const SizedBox(width: 9),
            Expanded(
              child: Text(text, style: Theme.of(context).textTheme.bodySmall),
            ),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    ),
  );
}

class _AnnouncementSkeleton extends StatelessWidget {
  const _AnnouncementSkeleton();

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: PremiumCard(
      child: Row(
        children: [
          Container(
            width: 48,
            height: 54,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(99),
                  ),
                ),
                const SizedBox(height: 9),
                FractionallySizedBox(
                  widthFactor: .62,
                  child: Container(
                    height: 11,
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}

class _DashboardNotice extends StatelessWidget {
  const _DashboardNotice({required this.onRetry});
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
        const SizedBox(width: 10),
        Expanded(child: Text(context.tr('dashboardNeedsMoment'))),
        TextButton(onPressed: onRetry, child: Text(context.tr('tryAgain'))),
      ],
    ),
  );
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        height: 230,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      const SizedBox(height: 12),
      Row(
        children: List.generate(
          3,
          (index) => Expanded(
            child: Container(
              height: 90,
              margin: EdgeInsetsDirectional.only(end: index == 2 ? 0 : 8),
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: .7),
                borderRadius: BorderRadius.circular(18),
              ),
            ),
          ),
        ),
      ),
    ],
  );
}

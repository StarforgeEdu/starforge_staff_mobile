import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/remote_models.dart';
import '../dashboard/notifications_page.dart';
import '../library/library_page.dart';
import '../print/print_page.dart';

class RoleDashboardPage extends StatefulWidget {
  const RoleDashboardPage({
    super.key,
    required this.onOpenWorkspace,
    this.onOpenProfile,
  });

  final VoidCallback onOpenWorkspace;
  final VoidCallback? onOpenProfile;

  @override
  State<RoleDashboardPage> createState() => _RoleDashboardPageState();
}

class _RoleDashboardPageState extends State<RoleDashboardPage> {
  _RoleSnapshot? _data;
  Object? _error;
  bool _loading = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null && !_loading && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = AppControllerScope.of(context);
      final data = await _RoleSnapshot.load(controller, controller.role);
      if (mounted) {
        setState(() {
          _data = data;
          _error = data.hadLoadError ? const _PartialLoadFailure() : null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final firstName = controller.displayName.split(' ').first;
    final palette = _RolePalette.forRole(controller.role, context);
    final data = _data ?? const _RoleSnapshot.empty();
    final primary = data.primaryCount(controller.role);
    final focus = data.focus(controller.role, context);
    final previewRows = data.previewRows(controller.role, context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          child: CustomScrollView(
            key: const PageStorageKey('roleDashboardScroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 960,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 20, bottom: 16),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${_greeting(context)}, $firstName',
                                style: Theme.of(
                                  context,
                                ).textTheme.headlineMedium,
                              ),
                              const SizedBox(height: 5),
                              Text(
                                context.tr('roleReady'),
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (controller.can('notifications:read')) ...[
                          IconButton.filledTonal(
                            tooltip: context.tr('notifications'),
                            onPressed: () async {
                              await Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const NotificationsPage(),
                                ),
                              );
                              if (mounted) _load();
                            },
                            icon: Badge.count(
                              count: data.notifications
                                  .where((item) => !item.isRead)
                                  .length,
                              isLabelVisible: data.notifications.any(
                                (item) => !item.isRead,
                              ),
                              child: const Icon(
                                Icons.notifications_none_rounded,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        IconButton(
                          tooltip: context.tr('profile'),
                          onPressed: widget.onOpenProfile,
                          padding: EdgeInsets.zero,
                          icon: PersonAvatar(
                            name: controller.displayName,
                            size: 48,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 960,
                  child: _RoleHero(
                    palette: palette,
                    focus: focus,
                    loading: _loading && _data == null,
                    onOpen: widget.onOpenWorkspace,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    maxWidth: 960,
                    child: _ErrorCard(onRetry: _load),
                  ),
                ),
              ],
              if (data.hasFreshData)
                const SliverToBoxAdapter(child: SizedBox(height: 24)),
              if (data.hasFreshData)
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    maxWidth: 960,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final metrics = [
                          (
                            '$primary',
                            palette.workspaceLabel,
                            palette.icon,
                            palette.color,
                          ),
                          (
                            '${data.tasks.where((item) => item.rawStatus != 'done' && item.rawStatus != 'cancelled').length}',
                            context.tr('tasks'),
                            Icons.task_alt_outlined,
                            const Color(0xFF365F9E),
                          ),
                          (
                            '${data.notifications.where((item) => !item.isRead).length}',
                            context.tr('notifications'),
                            Icons.notifications_none_rounded,
                            const Color(0xFF9A641C),
                          ),
                        ];
                        final textScale =
                            MediaQuery.textScalerOf(context).scale(14) / 14;
                        final columns =
                            textScale >= 1.5 && constraints.maxWidth < 600
                            ? (constraints.maxWidth >= 420 ? 2 : 1)
                            : 3;
                        const spacing = 9.0;
                        final width =
                            (constraints.maxWidth - spacing * (columns - 1)) /
                            columns;
                        return Wrap(
                          key: const ValueKey('role-metrics'),
                          spacing: spacing,
                          runSpacing: spacing,
                          children: metrics
                              .map(
                                (metric) => Semantics(
                                  label: '${metric.$1}, ${metric.$2}',
                                  excludeSemantics: true,
                                  child: SizedBox(
                                    width: width,
                                    child: MetricTile(
                                      value: metric.$1,
                                      label: metric.$2,
                                      icon: metric.$3,
                                      color: metric.$4,
                                    ),
                                  ),
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 26)),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 960,
                  child: SectionHeader(
                    title: context.tr('upcoming'),
                    action: context.tr('seeAll'),
                    onAction: widget.onOpenWorkspace,
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 11)),
              if (previewRows.isEmpty)
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    maxWidth: 960,
                    child: EmptyState(
                      title: context.tr('noItems'),
                      body: context.tr('emptyBody'),
                      icon: palette.icon,
                    ),
                  ),
                )
              else
                SliverList.separated(
                  itemCount: previewRows.length.clamp(0, 4),
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) => MaxWidthBox(
                    maxWidth: 960,
                    child: _OperationalRow(
                      row: previewRows[index],
                      color: palette.color,
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

class RoleWorkspacePage extends StatefulWidget {
  const RoleWorkspacePage({super.key});

  @override
  State<RoleWorkspacePage> createState() => _RoleWorkspacePageState();
}

class _RoleWorkspacePageState extends State<RoleWorkspacePage> {
  final _searchController = TextEditingController();
  _RoleSnapshot? _data;
  Object? _error;
  bool _loading = false;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_data == null && !_loading && _error == null) _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final controller = AppControllerScope.of(context);
      final result = await _RoleSnapshot.load(controller, controller.role);
      if (mounted) {
        setState(() {
          _data = result;
          _error = result.hadLoadError ? const _PartialLoadFailure() : null;
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _open(Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final palette = _RolePalette.forRole(controller.role, context);
    final rows = (_data ?? const _RoleSnapshot.empty())
        .allRows(controller.role, context)
        .where((row) {
          final query = _query.trim().toLowerCase();
          return query.isEmpty ||
              row.title.toLowerCase().contains(query) ||
              row.subtitle.toLowerCase().contains(query) ||
              row.meta.toLowerCase().contains(query);
        })
        .toList(growable: false);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          child: CustomScrollView(
            key: const PageStorageKey('roleWorkspaceScroll'),
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 960,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18, bottom: 14),
                    child: PageIntro(
                      title: palette.workspaceLabel,
                      subtitle: context.tr('roleReady'),
                      trailing: _WorkspaceShortcut(
                        role: controller.role,
                        controller: controller,
                        onLibrary: () => _open(const LibraryPage()),
                        onPrint: () => _open(const PrintPage()),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 960,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: context.tr('search'),
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: context.tr('clear'),
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SliverToBoxAdapter(child: SizedBox(height: 12)),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    maxWidth: 960,
                    child: _ErrorCard(onRetry: _load),
                  ),
                ),
              ],
              const SliverToBoxAdapter(child: SizedBox(height: 22)),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 960,
                  child: SectionHeader(title: context.tr('queue')),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 11)),
              if (_loading && _data == null)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (rows.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: context.tr('noItems'),
                    body: context.tr('emptyBody'),
                    icon: palette.icon,
                  ),
                )
              else
                SliverList.separated(
                  itemCount: rows.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 9),
                  itemBuilder: (context, index) => MaxWidthBox(
                    maxWidth: 960,
                    child: _OperationalRow(
                      row: rows[index],
                      color: palette.color,
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 110)),
            ],
          ),
        ),
      ),
    );
  }
}

class _RoleSnapshot {
  const _RoleSnapshot({
    required this.tasks,
    required this.notifications,
    required this.meetings,
    required this.leads,
    required this.invoices,
    required this.shifts,
    required this.printWorkspace,
    required this.library,
    required this.hadLoadError,
    required this.hasFreshData,
  });

  const _RoleSnapshot.empty()
    : tasks = const [],
      notifications = const [],
      meetings = const [],
      leads = const [],
      invoices = const [],
      shifts = const [],
      printWorkspace = const PrintWorkspace.empty(),
      library = const LibraryWorkspace.empty(),
      hadLoadError = false,
      hasFreshData = false;

  final List<StaffTask> tasks;
  final List<NotificationInfo> notifications;
  final List<MeetingInfo> meetings;
  final List<CrmLeadInfo> leads;
  final List<FinanceInvoiceInfo> invoices;
  final List<CashierShiftInfo> shifts;
  final PrintWorkspace printWorkspace;
  final LibraryWorkspace library;
  final bool hadLoadError;
  final bool hasFreshData;

  static Future<_RoleSnapshot> load(
    AppController controller,
    StaffRole role,
  ) async {
    var failures = 0;
    var successes = 0;
    Future<T> safe<T>(Future<T> Function() request, T fallback) async {
      try {
        final value = await request();
        successes++;
        return value;
      } catch (_) {
        failures++;
        return fallback;
      }
    }

    final results = await Future.wait<Object?>([
      if (controller.can('tasks:read'))
        safe(() => controller.loadTasks(mineOnly: true), const <StaffTask>[])
      else
        Future.value(const <StaffTask>[]),
      if (controller.can('notifications:read'))
        safe(controller.loadNotifications, const <NotificationInfo>[])
      else
        Future.value(const <NotificationInfo>[]),
      if (controller.can('meetings:read'))
        safe(controller.loadUpcomingMeetings, const <MeetingInfo>[])
      else
        Future.value(const <MeetingInfo>[]),
      if (role == StaffRole.sales || role == StaffRole.reception)
        safe(controller.loadCrmLeads, const <CrmLeadInfo>[])
      else
        Future.value(const <CrmLeadInfo>[]),
      if (role == StaffRole.cashier)
        safe(controller.loadFinanceInvoices, const <FinanceInvoiceInfo>[])
      else
        Future.value(const <FinanceInvoiceInfo>[]),
      if (role == StaffRole.cashier)
        safe(controller.loadOwnCashierShifts, const <CashierShiftInfo>[])
      else
        Future.value(const <CashierShiftInfo>[]),
      if (role == StaffRole.printer)
        safe(controller.loadPrintWorkspace, const PrintWorkspace.empty())
      else
        Future.value(const PrintWorkspace.empty()),
      if (role == StaffRole.media)
        safe(controller.loadLibrary, const LibraryWorkspace.empty())
      else
        Future.value(const LibraryWorkspace.empty()),
    ]);
    return _RoleSnapshot(
      tasks: results[0] as List<StaffTask>,
      notifications: results[1] as List<NotificationInfo>,
      meetings: results[2] as List<MeetingInfo>,
      leads: results[3] as List<CrmLeadInfo>,
      invoices: results[4] as List<FinanceInvoiceInfo>,
      shifts: results[5] as List<CashierShiftInfo>,
      printWorkspace: results[6] as PrintWorkspace,
      library: results[7] as LibraryWorkspace,
      hadLoadError: failures > 0,
      hasFreshData: successes > 0,
    );
  }

  int primaryCount(StaffRole role) => switch (role) {
    StaffRole.sales || StaffRole.reception => leads.length,
    StaffRole.cashier => invoices.where((item) => item.outstanding > 0).length,
    StaffRole.printer =>
      printWorkspace.jobs.where((item) => item.status != 'done').length,
    StaffRole.media => library.resources.length,
    _ => tasks.length,
  };

  _OperationalData? focus(StaffRole role, BuildContext context) {
    final rows = previewRows(role, context);
    return rows.isEmpty ? null : rows.first;
  }

  List<_OperationalData> previewRows(StaffRole role, BuildContext context) {
    final primary = _roleRows(role, context);
    if (primary.isNotEmpty) return primary;
    return _commonRows(context);
  }

  List<_OperationalData> allRows(StaffRole role, BuildContext context) => [
    ..._roleRows(role, context),
    ..._commonRows(context),
  ];

  List<_OperationalData> _roleRows(StaffRole role, BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    switch (role) {
      case StaffRole.sales:
      case StaffRole.reception:
        return leads
            .map(
              (item) => _OperationalData(
                title: item.studentName,
                subtitle: [
                  item.stageName,
                  item.departmentName,
                ].where((value) => value.isNotEmpty).join(' · '),
                meta: item.nextFollowUpAt == null
                    ? item.branchName
                    : DateFormat.MMMd(
                        locale,
                      ).add_Hm().format(item.nextFollowUpAt!.toLocal()),
                icon: Icons.person_search_outlined,
                urgent: item.nextFollowUpAt?.isBefore(DateTime.now()) == true,
              ),
            )
            .toList(growable: false);
      case StaffRole.cashier:
        return [
          ...shifts.map(
            (item) => _OperationalData(
              title: item.branchName,
              subtitle: _localizedOperationalStatus(context, item.status),
              meta: item.openedAt == null
                  ? ''
                  : DateFormat.MMMd(
                      locale,
                    ).add_Hm().format(item.openedAt!.toLocal()),
              icon: Icons.point_of_sale_outlined,
              urgent: item.discrepancy != 0,
            ),
          ),
          ...invoices.map(
            (item) => _OperationalData(
              title: item.studentName.isEmpty ? item.number : item.studentName,
              subtitle: item.number,
              meta:
                  '${NumberFormat.decimalPattern().format(item.outstanding.round())} ${item.currency}',
              icon: Icons.receipt_long_outlined,
              urgent:
                  item.outstanding > 0 &&
                  item.dueDate?.isBefore(DateTime.now()) == true,
            ),
          ),
        ];
      case StaffRole.printer:
        return [
          ...printWorkspace.jobs.map(
            (item) => _OperationalData(
              title: '#${item.id} · ${item.source}',
              subtitle:
                  '${context.trCount('pagesCount', item.pages)} · ${context.trCount('copiesCount', item.copies)}',
              meta: _localizedOperationalStatus(context, item.status),
              icon: Icons.print_outlined,
              urgent:
                  item.status == 'failed' ||
                  item.status == 'reconciliation_required',
            ),
          ),
          ...printWorkspace.printers.map(
            (item) => _OperationalData(
              title: item.name,
              subtitle: item.location,
              meta: item.isBusy ? context.tr('busy') : context.tr('available'),
              icon: Icons.print_rounded,
              urgent: item.isOffline,
            ),
          ),
        ];
      case StaffRole.media:
        return library.resources
            .map(
              (item) => _OperationalData(
                title: item.title,
                subtitle: item.author,
                meta: _localizedOperationalStatus(context, item.status),
                icon: item.icon,
                urgent: item.status == 'rejected',
              ),
            )
            .toList(growable: false);
      default:
        return const [];
    }
  }

  List<_OperationalData> _commonRows(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    return [
      ...tasks.map(
        (item) => _OperationalData(
          title: item.title,
          subtitle: item.description,
          meta: item.due.isEmpty ? context.tr('noDueDate') : item.due,
          icon: Icons.task_alt_outlined,
          urgent: item.highPriority,
        ),
      ),
      ...meetings.map(
        (item) => _OperationalData(
          title: item.title,
          subtitle: item.location,
          meta: DateFormat.MMMd(
            locale,
          ).add_Hm().format(item.startsAt.toLocal()),
          icon: Icons.groups_outlined,
          urgent: item.startsAt.difference(DateTime.now()).inHours < 24,
        ),
      ),
      ...notifications
          .where((item) => !item.isRead)
          .map(
            (item) => _OperationalData(
              title: item.title,
              subtitle: item.body,
              meta: DateFormat.MMMd(
                locale,
              ).add_Hm().format(item.createdAt.toLocal()),
              icon: Icons.notifications_outlined,
            ),
          ),
    ];
  }
}

class _PartialLoadFailure implements Exception {
  const _PartialLoadFailure();
}

class _RoleHero extends StatelessWidget {
  const _RoleHero({
    required this.palette,
    required this.focus,
    required this.loading,
    required this.onOpen,
  });

  final _RolePalette palette;
  final _OperationalData? focus;
  final bool loading;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [palette.color, Color.lerp(palette.color, Colors.black, .4)!],
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: palette.color.withValues(alpha: .2),
            blurRadius: 30,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(palette.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('todaysFocus'),
                  style: Theme.of(
                    context,
                  ).textTheme.labelMedium?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 5),
                if (loading)
                  const LinearProgressIndicator(color: Colors.white)
                else
                  Text(
                    focus?.title ?? context.tr('noItems'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.titleLarge?.copyWith(color: Colors.white),
                  ),
                if (focus?.subtitle.isNotEmpty == true) ...[
                  const SizedBox(height: 4),
                  Text(
                    focus!.subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            onPressed: onOpen,
            tooltip: palette.workspaceLabel,
            style: IconButton.styleFrom(
              foregroundColor: Colors.white,
              backgroundColor: Colors.white.withValues(alpha: .15),
            ),
            icon: const Icon(Icons.arrow_forward_rounded),
          ),
        ],
      ),
    );
  }
}

class _OperationalRow extends StatelessWidget {
  const _OperationalRow({required this.row, required this.color});

  final _OperationalData row;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final semanticLabel = [
      if (row.urgent) context.tr('urgent'),
      row.title,
      row.subtitle,
      row.meta,
    ].where((value) => value.isNotEmpty).join(', ');
    return Semantics(
      container: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PremiumCard(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
            final compact = constraints.maxWidth < 360 || textScale >= 1.5;
            final metaStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
              color: row.urgent
                  ? AppTheme.coral
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 45,
                  height: 45,
                  decoration: BoxDecoration(
                    color: (row.urgent ? AppTheme.coral : color).withValues(
                      alpha: .12,
                    ),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    row.icon,
                    color: row.urgent ? AppTheme.coral : color,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                      if (row.subtitle.isNotEmpty) ...[
                        const SizedBox(height: 3),
                        Text(
                          row.subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                        ),
                      ],
                      if (compact && row.meta.isNotEmpty) ...[
                        const SizedBox(height: 7),
                        Text(
                          row.meta,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: metaStyle,
                        ),
                      ],
                    ],
                  ),
                ),
                if (!compact && row.meta.isNotEmpty) ...[
                  const SizedBox(width: 9),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 120),
                    child: Text(
                      row.meta,
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: metaStyle,
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.onRetry});
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => PremiumCard(
    color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: .36),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
        final compact = constraints.maxWidth < 380 || textScale >= 1.5;
        final message = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.cloud_off_outlined,
              color: Theme.of(context).colorScheme.error,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(context.tr('tasksNeedMoment'))),
          ],
        );
        if (compact) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              message,
              const SizedBox(height: 8),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: onRetry,
                  child: Text(context.tr('tryAgain')),
                ),
              ),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: message),
            TextButton(onPressed: onRetry, child: Text(context.tr('tryAgain'))),
          ],
        );
      },
    ),
  );
}

class _WorkspaceShortcut extends StatelessWidget {
  const _WorkspaceShortcut({
    required this.role,
    required this.controller,
    required this.onLibrary,
    required this.onPrint,
  });

  final StaffRole role;
  final AppController controller;
  final VoidCallback onLibrary;
  final VoidCallback onPrint;

  @override
  Widget build(BuildContext context) {
    if (role == StaffRole.media && controller.can('content:read')) {
      return IconButton.filledTonal(
        onPressed: onLibrary,
        tooltip: context.tr('library'),
        icon: const Icon(Icons.local_library_outlined),
      );
    }
    if (role == StaffRole.printer && controller.can('printing:read')) {
      return IconButton.filledTonal(
        onPressed: onPrint,
        tooltip: context.tr('printCenter'),
        icon: const Icon(Icons.print_outlined),
      );
    }
    return const SizedBox.shrink();
  }
}

class _OperationalData {
  const _OperationalData({
    required this.title,
    required this.subtitle,
    required this.meta,
    required this.icon,
    this.urgent = false,
  });

  final String title;
  final String subtitle;
  final String meta;
  final IconData icon;
  final bool urgent;
}

class _RolePalette {
  const _RolePalette({
    required this.icon,
    required this.color,
    required this.workspaceLabel,
  });

  final IconData icon;
  final Color color;
  final String workspaceLabel;

  static _RolePalette forRole(StaffRole role, BuildContext context) =>
      switch (role) {
        StaffRole.media => _RolePalette(
          icon: Icons.camera_alt_outlined,
          color: const Color(0xFFB34C68),
          workspaceLabel: context.tr('studio'),
        ),
        StaffRole.reception => _RolePalette(
          icon: Icons.desk_outlined,
          color: const Color(0xFF217563),
          workspaceLabel: context.tr('frontDesk'),
        ),
        StaffRole.sales => _RolePalette(
          icon: Icons.handshake_outlined,
          color: const Color(0xFF365F9E),
          workspaceLabel: context.tr('leads'),
        ),
        StaffRole.printer => _RolePalette(
          icon: Icons.print_outlined,
          color: const Color(0xFF9A641C),
          workspaceLabel: context.tr('printCenter'),
        ),
        StaffRole.cashier => _RolePalette(
          icon: Icons.payments_outlined,
          color: const Color(0xFF684A97),
          workspaceLabel: context.tr('finance'),
        ),
        _ => _RolePalette(
          icon: Icons.work_outline_rounded,
          color: Theme.of(context).colorScheme.primary,
          workspaceLabel: context.tr('workspace'),
        ),
      };
}

String _greeting(BuildContext context) {
  final hour = DateTime.now().hour;
  if (hour < 12) return context.tr('goodMorning');
  if (hour < 18) return context.tr('goodAfternoon');
  return context.tr('goodEvening');
}

String _localizedOperationalStatus(BuildContext context, String status) =>
    switch (status.trim().toLowerCase()) {
      'open' => context.tr('statusOpen'),
      'closed' => context.tr('statusClosed'),
      'issued' => context.tr('statusIssued'),
      'partially_paid' => context.tr('statusPartiallyPaid'),
      'paid' => context.tr('statusPaid'),
      'void' => context.tr('statusVoid'),
      'overdue' => context.tr('statusOverdue'),
      'pending' => context.tr('statusPending'),
      'clean' => context.tr('statusClean'),
      'published' => context.tr('published'),
      'draft' => context.tr('draft'),
      'rejected' => context.tr('rejected'),
      'queued' => context.tr('queued'),
      'picked' => context.tr('picked'),
      'printing' => context.tr('printing'),
      'done' => context.tr('done'),
      'failed' => context.tr('failed'),
      'reconciliation_required' => context.tr('needsReview'),
      _ => status.replaceAll('_', ' '),
    };

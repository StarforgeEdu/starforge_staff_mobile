import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import 'group_detail_page.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key});

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

class _GroupsPageState extends State<GroupsPage> {
  final _searchController = TextEditingController();
  Future<List<LearningGroup>>? _loadFuture;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadFuture ??= AppControllerScope.of(context).loadGroups();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = AppControllerScope.of(context).loadGroups(refresh: true);
    setState(() => _loadFuture = future);
    await future;
  }

  List<LearningGroup> _filter(List<LearningGroup> groups) {
    final query = _query.toLowerCase().trim();
    if (query.isEmpty) return groups;
    return groups
        .where((group) {
          return [
            group.name,
            group.course,
            group.level,
            group.branch,
            group.department,
            group.mainTeacher,
          ].any((value) => value.toLowerCase().contains(query));
        })
        .toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: FutureBuilder<List<LearningGroup>>(
          future: _loadFuture,
          builder: (context, snapshot) {
            final loaded =
                snapshot.data ?? AppControllerScope.of(context).groups;
            final groups = _filter(loaded);
            return RefreshIndicator.adaptive(
              onRefresh: _refresh,
              child: CustomScrollView(
                key: const PageStorageKey('groupsScroll'),
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                slivers: [
                  SliverToBoxAdapter(
                    child: MaxWidthBox(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 22),
                        child: _GroupsHeader(
                          groupCount: loaded.length,
                          onRefresh: _refresh,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: MaxWidthBox(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 18, bottom: 18),
                        child: TextField(
                          controller: _searchController,
                          onChanged: (value) => setState(() => _query = value),
                          decoration: InputDecoration(
                            hintText: context.tr('searchGroups'),
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    tooltip: MaterialLocalizations.of(
                                      context,
                                    ).closeButtonTooltip,
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
                  ),
                  if (snapshot.connectionState == ConnectionState.waiting &&
                      loaded.isEmpty)
                    const SliverToBoxAdapter(child: _GroupsSkeleton())
                  else if (snapshot.hasError && loaded.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _GroupLoadState(onRetry: _refresh),
                    )
                  else if (groups.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: EmptyState(
                        title: context.tr(
                          _query.isEmpty ? 'noAssignedGroups' : 'emptyTitle',
                        ),
                        body: context.tr(
                          _query.isEmpty ? 'noAssignedGroupsBody' : 'emptyBody',
                        ),
                        icon: _query.isEmpty
                            ? Icons.auto_stories_outlined
                            : Icons.search_off_rounded,
                      ),
                    )
                  else
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        MediaQuery.sizeOf(context).width >= 1080
                            ? (MediaQuery.sizeOf(context).width - 1080) / 2 + 20
                            : 20,
                        0,
                        MediaQuery.sizeOf(context).width >= 1080
                            ? (MediaQuery.sizeOf(context).width - 1080) / 2 + 20
                            : 20,
                        36,
                      ),
                      sliver: SliverLayoutBuilder(
                        builder: (context, constraints) {
                          final columns = constraints.crossAxisExtent >= 700
                              ? 2
                              : 1;
                          final textScale =
                              MediaQuery.textScalerOf(context).scale(14) / 14;
                          final cardExtent =
                              286 + 92 * (textScale.clamp(1.0, 2.4) - 1.0);
                          return SliverGrid(
                            gridDelegate:
                                SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: columns,
                                  crossAxisSpacing: 14,
                                  mainAxisSpacing: 14,
                                  mainAxisExtent: cardExtent,
                                ),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) => FadeSlideIn(
                                delay: Duration(milliseconds: 55 * index),
                                child: _GroupCard(
                                  group: groups[index],
                                  onReturn: _refresh,
                                ),
                              ),
                              childCount: groups.length,
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _GroupsHeader extends StatelessWidget {
  const _GroupsHeader({required this.groupCount, required this.onRefresh});
  final int groupCount;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(22, 21, 18, 21),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('yourGroups'),
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Colors.white,
                    letterSpacing: -.8,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  controller.branchName.isEmpty
                      ? context.tr('groupsSubtitle')
                      : controller.branchName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Colors.white.withValues(alpha: .7),
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.layers_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 7),
                      Flexible(
                        child: Text(
                          context.trCount('groupsCount', groupCount),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(21),
              border: Border.all(color: Colors.white.withValues(alpha: .13)),
            ),
            child: IconButton(
              tooltip: context.tr('refresh'),
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onReturn});
  final LearningGroup group;
  final Future<void> Function() onReturn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cycle = group.lessonCycleLength == null
        ? ''
        : context.l10n.format('lessonCycleShort', {
            'count': group.lessonCycleLength!,
          });
    final detail = [
      group.department,
      group.level,
      if (group.studyMonth != null)
        context.l10n.format('studyMonthValue', {'month': group.studyMonth!}),
      cycle,
    ].where((value) => value.isNotEmpty && value != '—').join(' · ');
    Future<void> openGroup() async {
      final moved = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => GroupDetailPage(group: group)),
      );
      if (moved == true) await onReturn();
    }

    return Semantics(
      key: ValueKey('group-${group.id}'),
      button: true,
      label: [
        group.name,
        if (detail.isNotEmpty) detail,
        if (group.mainTeacher.isNotEmpty) group.mainTeacher,
      ].join(', '),
      onTap: openGroup,
      excludeSemantics: true,
      child: PremiumCard(
        padding: EdgeInsets.zero,
        onTap: openGroup,
        child: Column(
          children: [
            Container(
              height: 6,
              decoration: BoxDecoration(color: theme.colorScheme.primary),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(19, 17, 19, 15),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 47,
                          height: 47,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(15),
                          ),
                          child: Icon(
                            Icons.auto_stories_rounded,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        const Spacer(),
                        Flexible(
                          child: _GroupStatusPill(
                            label:
                                group.endDate != null &&
                                    group.endDate!.isBefore(DateTime.now())
                                ? context.tr('completed')
                                : context.tr('active'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 15),
                    Text(
                      group.name,
                      style: theme.textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      detail.isEmpty ? context.tr('groupPortfolio') : detail,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 15),
                    _GroupDetailLine(
                      icon: Icons.person_outline_rounded,
                      text: group.mainTeacher,
                    ),
                    const SizedBox(height: 8),
                    _GroupDetailLine(
                      icon: Icons.location_on_outlined,
                      text: '${group.branch} · ${group.room}',
                    ),
                    const Spacer(),
                    Row(
                      children: [
                        Expanded(
                          child: _MiniStat(
                            icon: Icons.people_outline_rounded,
                            value: group.capacity == null
                                ? '—'
                                : '${group.capacity}',
                            label: context.tr('capacity'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(
                          Icons.arrow_forward_rounded,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GroupStatusPill extends StatelessWidget {
  const _GroupStatusPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppTheme.mint.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(99),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _GroupDetailLine extends StatelessWidget {
  const _GroupDetailLine({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(
        icon,
        size: 17,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
      const SizedBox(width: 7),
      Expanded(
        child: Text(
          text.isEmpty ? '—' : text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.icon,
    required this.value,
    required this.label,
  });
  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Icon(icon, size: 17, color: Theme.of(context).colorScheme.primary),
      const SizedBox(width: 6),
      Flexible(
        child: Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.labelLarge,
        ),
      ),
      const SizedBox(width: 5),
      Flexible(
        flex: 3,
        child: Text(
          label.toLowerCase(),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    ],
  );
}

class _GroupsSkeleton extends StatelessWidget {
  const _GroupsSkeleton();

  @override
  Widget build(BuildContext context) => MaxWidthBox(
    child: Column(
      children: List.generate(
        3,
        (index) => Container(
          height: 154,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: .55 - index * .08),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    ),
  );
}

class _GroupLoadState extends StatelessWidget {
  const _GroupLoadState({required this.onRetry});
  final VoidCallback onRetry;

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
              Icons.cloud_off_outlined,
              color: Theme.of(context).colorScheme.primary,
              size: 31,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.tr('groupsLoadFailed'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 7),
          Text(
            context.tr('groupsLoadFailedBody'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
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

import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../dashboard/meetings_page.dart';
import '../dashboard/notifications_page.dart';
import '../groups/assigned_students_page.dart';
import '../library/library_page.dart';
import '../print/print_page.dart';
import '../profile/employment_pages.dart';
import '../profile/profile_page.dart';
import '../profile/rules_page.dart';
import 'achievements_page.dart';
import 'forms_page.dart';
import 'reports_page.dart';
import 'requests_page.dart';

class WorkHubPage extends StatelessWidget {
  const WorkHubPage({super.key});

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final tools = <_WorkTool>[
      if (controller.can('students:read') && controller.hasTeachingWorkspace)
        _WorkTool(
          title: context.tr('assignedStudents'),
          detail: context.tr('assignedStudentsSubtitle'),
          icon: Icons.school_outlined,
          color: const Color(0xFF4F6A3A),
          group: _WorkGroup.resources,
          page: const AssignedStudentsPage(),
        ),
      if (controller.can('content:read'))
        _WorkTool(
          title: context.tr('library'),
          detail: context.tr('librarySubtitle'),
          icon: Icons.folder_copy_outlined,
          color: const Color(0xFF2A3D8F),
          group: _WorkGroup.resources,
          page: const LibraryPage(),
        ),
      if (controller.can('forms:read'))
        _WorkTool(
          title: context.tr('formsSurveys'),
          detail: context.tr('formsSurveysSubtitle'),
          icon: Icons.ballot_outlined,
          color: Theme.of(context).colorScheme.primary,
          group: _WorkGroup.resources,
          page: const StaffFormsPage(),
        ),
      if (controller.can('printing:read'))
        _WorkTool(
          title: context.tr('printCenter'),
          detail: context.tr('printerSubtitle'),
          icon: Icons.print_outlined,
          color: AppTheme.gold,
          group: _WorkGroup.resources,
          page: const PrintPage(),
        ),
      if (controller.can('approvals:read'))
        _WorkTool(
          title: context.tr('requests'),
          detail: context.tr('requestsSubtitle'),
          icon: Icons.fact_check_outlined,
          color: Theme.of(context).colorScheme.primary,
          group: _WorkGroup.now,
          page: const StaffRequestsPage(),
        ),
      if (controller.can('achievements:read'))
        _WorkTool(
          title: context.tr('achievements'),
          detail: context.tr('achievementsSubtitle'),
          icon: Icons.workspace_premium_outlined,
          color: AppTheme.gold,
          group: _WorkGroup.resources,
          page: const StaffAchievementsPage(),
        ),
      if (controller.can('reports:read'))
        _WorkTool(
          title: context.tr('reports'),
          detail: context.tr('reportsSubtitle'),
          icon: Icons.description_outlined,
          color: const Color(0xFF1F6B66),
          group: _WorkGroup.resources,
          page: const StaffReportsPage(),
        ),
      if (controller.can('notifications:read'))
        _WorkTool(
          title: context.tr('notifications'),
          detail: context.tr('notificationsEmptyBody'),
          icon: Icons.notifications_none_rounded,
          color: Theme.of(context).colorScheme.primary,
          group: _WorkGroup.now,
          page: const NotificationsPage(),
        ),
      if (controller.isSignedIn)
        _WorkTool(
          title: context.tr('meetingsTitle'),
          detail: context.tr('meetingsSubtitle'),
          icon: Icons.event_outlined,
          color: const Color(0xFF1F6B66),
          group: _WorkGroup.now,
          page: const MeetingsPage(),
        ),
      if (controller.account?.principalKind == 'teacher')
        _WorkTool(
          title: context.tr('salaryHistory'),
          detail: context.tr('salaryPrivate'),
          icon: Icons.receipt_long_outlined,
          color: const Color(0xFF4F6A3A),
          group: _WorkGroup.account,
          page: const SalaryHistoryPage(),
        ),
      if (controller.isSignedIn)
        _WorkTool(
          title: context.tr('rules'),
          detail: context.tr('privacyAccountabilityBody'),
          icon: Icons.policy_outlined,
          color: AppTheme.gold,
          group: _WorkGroup.account,
          page: const RulesPage(),
        ),
      _WorkTool(
        title: context.tr('profile'),
        detail: controller.displayName,
        icon: Icons.person_outline_rounded,
        color: Theme.of(context).colorScheme.primary,
        group: _WorkGroup.account,
        page: const ProfilePage(),
      ),
    ];
    final sections = <Widget>[];
    for (final group in _WorkGroup.values) {
      final groupTools = tools
          .where((tool) => tool.group == group)
          .toList(growable: false);
      if (groupTools.isEmpty) continue;
      sections.add(
        _WorkSectionHeader(
          title: switch (group) {
            _WorkGroup.now => context.tr('workNowTitle'),
            _WorkGroup.resources => context.tr('workResourcesTitle'),
            _WorkGroup.account => context.tr('workAccountTitle'),
          },
          count: groupTools.length,
        ),
      );
      sections.addAll(
        groupTools.map(
          (tool) => Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: _WorkToolRow(
              tool: tool,
              onTap: () => _open(context, tool.page),
            ),
          ),
        ),
      );
      sections.add(const SizedBox(height: 8));
    }
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('workHubScroll'),
          slivers: [
            SliverToBoxAdapter(
              child: MaxWidthBox(
                child: Padding(
                  padding: const EdgeInsets.only(top: 22),
                  child: _WorkHero(toolCount: tools.length),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(
                MediaQuery.sizeOf(context).width >= 840
                    ? (MediaQuery.sizeOf(context).width - 840) / 2 + 20
                    : 20,
                0,
                MediaQuery.sizeOf(context).width >= 840
                    ? (MediaQuery.sizeOf(context).width - 840) / 2 + 20
                    : 20,
                36,
              ),
              sliver: SliverList(delegate: SliverChildListDelegate(sections)),
            ),
          ],
        ),
      ),
    );
  }
}

class _WorkHero extends StatelessWidget {
  const _WorkHero({required this.toolCount});

  final int toolCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final copy = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('workHubTitle'),
          style: theme.textTheme.headlineSmall?.copyWith(
            color: theme.colorScheme.onSurface,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          context.tr('workHubSubtitle'),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
    final count = Container(
      constraints: const BoxConstraints(minWidth: 42, minHeight: 42),
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        '$toolCount',
        style: theme.textTheme.titleMedium?.copyWith(
          color: theme.colorScheme.onPrimaryContainer,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
    return PremiumCard(
      padding: const EdgeInsets.all(22),
      color: theme.colorScheme.surfaceContainerLow,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stackCopy =
              constraints.maxWidth < 290 ||
              MediaQuery.textScalerOf(context).scale(1) > 1.35;
          if (stackCopy) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const StarforgeMark(size: 42),
                    const Spacer(),
                    count,
                  ],
                ),
                const SizedBox(height: 16),
                copy,
              ],
            );
          }
          return Row(
            children: [
              const StarforgeMark(size: 46),
              const SizedBox(width: 17),
              Expanded(child: copy),
              const SizedBox(width: 12),
              count,
            ],
          );
        },
      ),
    );
  }
}

class _WorkSectionHeader extends StatelessWidget {
  const _WorkSectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(2, 10, 2, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleMedium),
        ),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    ),
  );
}

class _WorkToolRow extends StatelessWidget {
  const _WorkToolRow({required this.tool, required this.onTap});

  final _WorkTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
    onTap: onTap,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    child: Row(
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: tool.color.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(tool.icon, color: tool.color),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(tool.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 3),
              Text(
                tool.detail,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Icon(
          Icons.chevron_right_rounded,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ],
    ),
  );
}

class _WorkTool {
  const _WorkTool({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.group,
    required this.page,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final _WorkGroup group;
  final Widget page;
}

enum _WorkGroup { now, resources, account }

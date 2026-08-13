import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../groups/assigned_students_page.dart';
import '../library/library_page.dart';
import '../print/print_page.dart';
import '../profile/profile_page.dart';
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
          color: const Color(0xFF2D8B73),
          page: const AssignedStudentsPage(),
        ),
      if (controller.can('content:read'))
        _WorkTool(
          title: context.tr('library'),
          detail: context.tr('librarySubtitle'),
          icon: Icons.folder_copy_outlined,
          color: const Color(0xFF5867C9),
          page: const LibraryPage(),
        ),
      if (controller.can('forms:read'))
        _WorkTool(
          title: context.tr('formsSurveys'),
          detail: context.tr('formsSurveysSubtitle'),
          icon: Icons.ballot_outlined,
          color: const Color(0xFF8C5CC4),
          page: const StaffFormsPage(),
        ),
      if (controller.can('printing:read'))
        _WorkTool(
          title: context.tr('printCenter'),
          detail: context.tr('printerSubtitle'),
          icon: Icons.print_outlined,
          color: AppTheme.gold,
          page: const PrintPage(),
        ),
      if (controller.can('approvals:read'))
        _WorkTool(
          title: context.tr('requests'),
          detail: context.tr('requestsSubtitle'),
          icon: Icons.fact_check_outlined,
          color: const Color(0xFFE26D5A),
          page: const StaffRequestsPage(),
        ),
      if (controller.can('achievements:read'))
        _WorkTool(
          title: context.tr('achievements'),
          detail: context.tr('achievementsSubtitle'),
          icon: Icons.workspace_premium_outlined,
          color: const Color(0xFFCB8E31),
          page: const StaffAchievementsPage(),
        ),
      if (controller.can('reports:read'))
        _WorkTool(
          title: context.tr('reports'),
          detail: context.tr('reportsSubtitle'),
          icon: Icons.description_outlined,
          color: const Color(0xFF277DA1),
          page: const StaffReportsPage(),
        ),
      _WorkTool(
        title: context.tr('profile'),
        detail: controller.displayName,
        icon: Icons.person_outline_rounded,
        color: Theme.of(context).colorScheme.primary,
        page: const ProfilePage(),
      ),
    ];
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('workHubScroll'),
          physics: const BouncingScrollPhysics(),
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
                  final columns = constraints.crossAxisExtent >= 820
                      ? 3
                      : constraints.crossAxisExtent >= 520
                      ? 2
                      : 1;
                  return SliverGrid(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      crossAxisSpacing: 13,
                      mainAxisSpacing: 13,
                      mainAxisExtent: 168,
                    ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => FadeSlideIn(
                        delay: Duration(milliseconds: index * 45),
                        child: _WorkToolCard(
                          tool: tools[index],
                          onTap: () => _open(context, tools[index].page),
                        ),
                      ),
                      childCount: tools.length,
                    ),
                  );
                },
              ),
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
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(24),
    decoration: BoxDecoration(
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [Color(0xFF163D3A), Color(0xFF34366F)],
      ),
      borderRadius: BorderRadius.circular(28),
    ),
    child: Row(
      children: [
        Container(
          width: 58,
          height: 58,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Icon(Icons.grid_view_rounded, color: Colors.white),
        ),
        const SizedBox(width: 17),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('workHubTitle'),
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.tr('workHubSubtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .75),
                ),
              ),
            ],
          ),
        ),
        StatusPill(label: '$toolCount', color: const Color(0xFF85D8CD)),
      ],
    ),
  );
}

class _WorkToolCard extends StatelessWidget {
  const _WorkToolCard({required this.tool, required this.onTap});

  final _WorkTool tool;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PremiumCard(
    onTap: onTap,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: tool.color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(tool.icon, color: tool.color),
            ),
            const Spacer(),
            Icon(
              Icons.arrow_forward_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
        const Spacer(),
        Text(tool.title, style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 5),
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
  );
}

class _WorkTool {
  const _WorkTool({
    required this.title,
    required this.detail,
    required this.icon,
    required this.color,
    required this.page,
  });

  final String title;
  final String detail;
  final IconData icon;
  final Color color;
  final Widget page;
}

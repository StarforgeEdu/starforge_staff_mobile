import 'package:flutter/material.dart';

import '../../core/app_localizations.dart';
import '../../core/app_controller.dart';
import '../../core/app_widgets.dart';
import '../dashboard/dashboard_page.dart';
import '../groups/groups_page.dart';
import '../messages/messages_page.dart';
import '../role_workspace/role_workspace_page.dart';
import '../tasks/tasks_page.dart';
import '../work/work_hub_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  int _unreadNotifications = 0;
  bool _notificationCountRequested = false;
  final Set<_ShellPage> _visitedPages = {_ShellPage.home};

  void _selectPage(_ShellPage page) {
    if (page == _pages[_index] && _visitedPages.contains(page)) return;
    setState(() {
      _index = _pages.indexOf(page);
      _visitedPages.add(page);
    });
    if (page == _ShellPage.home || page == _ShellPage.work) {
      _refreshUnreadNotifications();
    }
  }

  late List<_ShellPage> _pages;

  void _syncPages(AppController controller) {
    final pages = <_ShellPage>[
      _ShellPage.home,
      _ShellPage.workspace,
      if (controller.can('tasks:read')) _ShellPage.tasks,
      if (controller.can('messaging:read')) _ShellPage.messages,
      _ShellPage.work,
    ];
    final current = _pages.isEmpty ? _ShellPage.home : _pages[_index];
    _pages = pages;
    _index = pages.contains(current) ? pages.indexOf(current) : 0;
  }

  void _selectLegacyDestination(int legacyIndex) {
    final page = switch (legacyIndex) {
      0 => _ShellPage.home,
      1 => _ShellPage.workspace,
      2 => _ShellPage.tasks,
      3 => _ShellPage.messages,
      _ => _ShellPage.work,
    };
    if (_pages.contains(page)) _selectPage(page);
  }

  @override
  void initState() {
    super.initState();
    _pages = const [];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showPremiumToast(context, context.tr('warmLogin'));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_notificationCountRequested) return;
    _notificationCountRequested = true;
    _refreshUnreadNotifications();
  }

  Future<void> _refreshUnreadNotifications() async {
    final controller = AppControllerScope.of(context);
    if (!controller.can('notifications:read')) return;
    try {
      final count = await controller.loadUnreadNotificationCount();
      if (mounted && count != _unreadNotifications) {
        setState(() => _unreadNotifications = count);
      }
    } catch (_) {
      // A badge is supporting context; page-level loading and recovery remain
      // available if the count endpoint is temporarily unavailable.
    }
  }

  Widget _destinationIcon(
    _ShellDestination destination, {
    required bool selected,
  }) {
    final icon = Icon(selected ? destination.selectedIcon : destination.icon);
    if (destination.page != _ShellPage.home || _unreadNotifications <= 0) {
      return icon;
    }
    return Badge.count(
      count: _unreadNotifications,
      isLabelVisible: true,
      child: icon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    _syncPages(controller);
    final role = controller.role;
    final isTeachingRole = controller.hasTeachingWorkspace;
    final workspaceLabel = switch (role) {
      StaffRole.media => context.tr('studio'),
      StaffRole.reception => context.tr('frontDesk'),
      StaffRole.sales => context.tr('leads'),
      StaffRole.printer => context.tr('printCenter'),
      StaffRole.cashier => context.tr('finance'),
      _ => context.tr('groups'),
    };
    final workspaceIcons = switch (role) {
      StaffRole.media => (Icons.camera_alt_rounded, Icons.camera_alt_outlined),
      StaffRole.reception => (Icons.desk_rounded, Icons.desk_outlined),
      StaffRole.sales => (Icons.handshake_rounded, Icons.handshake_outlined),
      StaffRole.printer => (Icons.print_rounded, Icons.print_outlined),
      StaffRole.cashier => (Icons.payments_rounded, Icons.payments_outlined),
      _ => (Icons.groups_rounded, Icons.groups_outlined),
    };
    Widget pageAt(_ShellPage page) => switch (page) {
      _ShellPage.home =>
        isTeachingRole
            ? DashboardPage(onNavigate: _selectLegacyDestination)
            : RoleDashboardPage(
                onOpenWorkspace: () => _selectPage(_ShellPage.workspace),
                onOpenProfile: () => _selectPage(_ShellPage.work),
              ),
      _ShellPage.workspace =>
        isTeachingRole ? const GroupsPage() : const RoleWorkspacePage(),
      _ShellPage.tasks => const TasksPage(),
      _ShellPage.messages => const MessagesPage(),
      _ShellPage.work => const WorkHubPage(),
    };
    final pages = List<Widget>.generate(
      _pages.length,
      (index) => _visitedPages.contains(_pages[index])
          ? KeyedSubtree(
              key: ValueKey('shell-page-${_pages[index].name}'),
              child: pageAt(_pages[index]),
            )
          : const SizedBox.shrink(),
    );
    final destinations = <_ShellDestination>[
      _ShellDestination(
        page: _ShellPage.home,
        selectedIcon: Icons.home_rounded,
        icon: Icons.home_outlined,
        label: context.tr('home'),
      ),
      _ShellDestination(
        page: _ShellPage.workspace,
        selectedIcon: workspaceIcons.$1,
        icon: workspaceIcons.$2,
        label: workspaceLabel,
      ),
      if (controller.can('tasks:read'))
        _ShellDestination(
          page: _ShellPage.tasks,
          selectedIcon: Icons.check_circle_rounded,
          icon: Icons.check_circle_outline_rounded,
          label: context.tr('tasks'),
        ),
      if (controller.can('messaging:read'))
        _ShellDestination(
          page: _ShellPage.messages,
          selectedIcon: Icons.chat_bubble_rounded,
          icon: Icons.chat_bubble_outline_rounded,
          label: context.tr('messages'),
        ),
      _ShellDestination(
        page: _ShellPage.work,
        selectedIcon: Icons.grid_view_rounded,
        icon: Icons.grid_view_outlined,
        label: context.tr('workHub'),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRail = constraints.maxWidth >= 820;
        final content = IndexedStack(index: _index, children: pages);
        if (useRail) {
          return Scaffold(
            body: Row(
              children: [
                SafeArea(
                  right: false,
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      border: BorderDirectional(
                        end: BorderSide(
                          color: Theme.of(context).colorScheme.outlineVariant,
                        ),
                      ),
                    ),
                    child: NavigationRail(
                      selectedIndex: _index,
                      onDestinationSelected: (index) =>
                          _selectPage(_pages[index]),
                      backgroundColor: Colors.transparent,
                      labelType: constraints.maxWidth >= 1050
                          ? NavigationRailLabelType.all
                          : NavigationRailLabelType.selected,
                      leading: const Padding(
                        padding: EdgeInsets.only(top: 16, bottom: 24),
                        child: StarforgeMark(size: 40),
                      ),
                      destinations: destinations
                          .map(
                            (destination) => NavigationRailDestination(
                              icon: _destinationIcon(
                                destination,
                                selected: false,
                              ),
                              selectedIcon: _destinationIcon(
                                destination,
                                selected: true,
                              ),
                              label: Text(destination.label),
                            ),
                          )
                          .toList(),
                    ),
                  ),
                ),
                Expanded(child: content),
              ],
            ),
          );
        }
        return Scaffold(
          body: content,
          bottomNavigationBar: NavigationBar(
            selectedIndex: _index,
            onDestinationSelected: (index) => _selectPage(_pages[index]),
            destinations: destinations
                .map(
                  (destination) => NavigationDestination(
                    icon: _destinationIcon(destination, selected: false),
                    selectedIcon: _destinationIcon(destination, selected: true),
                    label: destination.label,
                  ),
                )
                .toList(),
          ),
        );
      },
    );
  }
}

enum _ShellPage { home, workspace, tasks, messages, work }

class _ShellDestination {
  const _ShellDestination({
    required this.page,
    required this.selectedIcon,
    required this.icon,
    required this.label,
  });

  final _ShellPage page;
  final IconData selectedIcon;
  final IconData icon;
  final String label;
}

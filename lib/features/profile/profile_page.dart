import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../library/library_page.dart';
import '../print/print_page.dart';
import 'employment_pages.dart';
import 'rules_page.dart';
import 'settings_page.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  bool _groupsRequested = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_groupsRequested) return;
    _groupsRequested = true;
    final controller = AppControllerScope.of(context);
    if (controller.hasTeachingWorkspace && !controller.groupsLoaded) {
      controller.loadGroups().catchError((_) => controller.groups);
    }
  }

  void _open(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  void _editName(BuildContext context) {
    final controller = AppControllerScope.of(context);
    showAppSheet<void>(
      context: context,
      builder: (_) => _EditNameSheet(
        controller: controller,
        onSaved: () {
          if (context.mounted) {
            showPremiumToast(context, context.tr('changesSaved'));
          }
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppControllerScope.of(context);
    final canViewOwnPayslips = controller.account?.principalKind == 'teacher';
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: CustomScrollView(
          key: const PageStorageKey('profileScroll'),
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 900,
                child: Padding(
                  padding: const EdgeInsets.only(top: 18),
                  child: _ProfileHero(
                    name: controller.displayName,
                    role:
                        controller.role == StaffRole.staff &&
                            controller.roleDisplayName.isNotEmpty
                        ? controller.roleDisplayName
                        : context.tr(controller.localizedRoleKey),
                    branch: controller.branchName,
                    onEdit: controller.account?.readOnly == true
                        ? null
                        : () => _editName(context),
                    onSettings: () => _open(context, const SettingsPage()),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 14)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 900,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final compact =
                        MediaQuery.textScalerOf(context).scale(1) >= 1.45;
                    final memberships = controller.account?.memberships ?? [];
                    final roleCount = memberships
                        .map((item) => item.id)
                        .toSet()
                        .length;
                    final branchCount = memberships
                        .map((item) => item.branchName)
                        .where((value) => value.isNotEmpty)
                        .toSet()
                        .length;
                    final departmentCount = memberships
                        .map((item) => item.departmentName)
                        .where((value) => value.isNotEmpty)
                        .toSet()
                        .length;
                    final teachingWorkspace = controller.hasTeachingWorkspace;
                    final stats = [
                      (
                        teachingWorkspace && !controller.groupsLoaded
                            ? '—'
                            : '${teachingWorkspace ? controller.groups.length : departmentCount}',
                        context.tr(teachingWorkspace ? 'groups' : 'department'),
                        teachingWorkspace
                            ? Icons.groups_outlined
                            : Icons.account_tree_outlined,
                        theme.colorScheme.primary,
                      ),
                      (
                        '$roleCount',
                        context.tr('role'),
                        Icons.badge_outlined,
                        const Color(0xFF2D9079),
                      ),
                      (
                        '$branchCount',
                        context.tr('branch'),
                        Icons.location_on_outlined,
                        AppTheme.gold,
                      ),
                    ];
                    final columns = compact ? 1 : 3;
                    final width =
                        (constraints.maxWidth - 9 * (columns - 1)) / columns;
                    return Wrap(
                      spacing: 9,
                      runSpacing: 9,
                      crossAxisAlignment: WrapCrossAlignment.start,
                      children: stats
                          .map(
                            (stat) => SizedBox(
                              width: width,
                              child: MetricTile(
                                value: stat.$1,
                                label: stat.$2,
                                icon: stat.$3,
                                color: stat.$4,
                              ),
                            ),
                          )
                          .toList(),
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 25)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 900,
                child: SectionHeader(title: context.tr('quickActions')),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 11)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 900,
                child: _WorkspaceGrid(
                  onLibrary: controller.can('content:read')
                      ? () => _open(context, const LibraryPage())
                      : null,
                  onPrint: controller.can('printing:read')
                      ? () => _open(context, const PrintPage())
                      : null,
                  onRules: () => _open(context, const RulesPage()),
                  onSettings: () => _open(context, const SettingsPage()),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 25)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 900,
                child: SectionHeader(title: context.tr('employment')),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 11)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 900,
                child: PremiumCard(
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      _ProfileMenuRow(
                        icon: Icons.payments_outlined,
                        color: const Color(0xFF2D9079),
                        title: context.tr('salaryHistory'),
                        subtitle: context.tr(
                          canViewOwnPayslips
                              ? 'salaryPrivate'
                              : 'employmentDataUnavailableBody',
                        ),
                        onTap: canViewOwnPayslips
                            ? () => _open(context, const SalaryHistoryPage())
                            : null,
                      ),
                      const Divider(indent: 64),
                      _ProfileMenuRow(
                        icon: Icons.description_outlined,
                        color: const Color(0xFF4D73B7),
                        title: context.tr('contract'),
                        subtitle: context.tr('contractUnavailableBody'),
                        onTap: () => _open(context, const ContractPage()),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }
}

class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.controller, required this.onSaved});

  final AppController controller;
  final VoidCallback onSaved;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final TextEditingController _firstController;
  late final TextEditingController _middleController;
  late final TextEditingController _lastController;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final account = widget.controller.account;
    final fallback = widget.controller.displayName.trim().split(RegExp(r'\s+'));
    _firstController = TextEditingController(
      text: account?.firstName.isNotEmpty == true
          ? account!.firstName
          : fallback.first,
    );
    _middleController = TextEditingController(text: account?.middleName ?? '');
    _lastController = TextEditingController(
      text: account?.lastName.isNotEmpty == true
          ? account!.lastName
          : (fallback.length > 1 ? fallback.last : ''),
    );
  }

  @override
  void dispose() {
    _firstController.dispose();
    _middleController.dispose();
    _lastController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final saved = await widget.controller.updateName(
      firstName: _firstController.text,
      middleName: _middleController.text,
      lastName: _lastController.text,
    );
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context);
      widget.onSaved();
      return;
    }
    setState(() => _saving = false);
    showPremiumToast(
      context,
      context.tr('changesCouldNotSave'),
      icon: Icons.info_outline_rounded,
      color: AppTheme.coral,
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.fromLTRB(
      24,
      2,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: AutofillGroup(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('editName'),
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _firstController,
            autofocus: true,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.givenName],
            decoration: InputDecoration(labelText: context.tr('firstName')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _middleController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.middleName],
            decoration: InputDecoration(labelText: context.tr('middleName')),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _lastController,
            enabled: !_saving,
            textCapitalization: TextCapitalization.words,
            autofillHints: const [AutofillHints.familyName],
            decoration: InputDecoration(labelText: context.tr('lastName')),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(context.tr('save')),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ProfileHero extends StatelessWidget {
  const _ProfileHero({
    required this.name,
    required this.role,
    required this.branch,
    required this.onEdit,
    required this.onSettings,
  });
  final String name;
  final String role;
  final String branch;
  final VoidCallback? onEdit;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: .2),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          children: [
            Positioned.fill(
              child: DecoratedBox(decoration: BoxDecoration(color: primary)),
            ),
            Positioned(
              right: -54,
              top: -75,
              child: ExcludeSemantics(
                child: Container(
                  width: 190,
                  height: 190,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .08),
                  ),
                ),
              ),
            ),
            Positioned(
              left: 65,
              bottom: -105,
              child: ExcludeSemantics(
                child: Container(
                  width: 210,
                  height: 210,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.mint.withValues(alpha: .09),
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(22),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < 430 ||
                      MediaQuery.textScalerOf(context).scale(1) >= 1.45;
                  final details = Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                      const SizedBox(height: 9),
                      Wrap(
                        spacing: 8,
                        runSpacing: 7,
                        children: [
                          _ProfileIdentityPill(
                            icon: Icons.badge_outlined,
                            text: role,
                          ),
                          if (branch.isNotEmpty)
                            _ProfileIdentityPill(
                              icon: Icons.location_on_outlined,
                              text: branch,
                            ),
                        ],
                      ),
                      const SizedBox(height: 13),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (onEdit != null)
                            _WhiteIconButton(
                              icon: Icons.edit_outlined,
                              tooltip: context.tr('editProfile'),
                              onTap: onEdit!,
                            ),
                          _WhiteIconButton(
                            icon: Icons.settings_outlined,
                            tooltip: context.tr('openSettings'),
                            onTap: onSettings,
                          ),
                        ],
                      ),
                    ],
                  );
                  if (compact) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            PersonAvatar(
                              name: name,
                              size: 70,
                              color: Colors.white,
                            ),
                            const StarforgeMark(size: 38, onDark: true),
                          ],
                        ),
                        const SizedBox(height: 15),
                        details,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      PersonAvatar(name: name, size: 78, color: Colors.white),
                      const SizedBox(width: 17),
                      Expanded(child: details),
                      const StarforgeMark(size: 38, onDark: true),
                    ],
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

class _ProfileIdentityPill extends StatelessWidget {
  const _ProfileIdentityPill({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(99),
        border: Border.all(color: Colors.white.withValues(alpha: .1)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: Colors.white70),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WhiteIconButton extends StatelessWidget {
  const _WhiteIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      style: IconButton.styleFrom(
        foregroundColor: Colors.white,
        backgroundColor: Colors.white.withValues(alpha: .14),
        minimumSize: const Size.square(48),
      ),
      icon: Icon(icon, size: 20),
    );
  }
}

class _WorkspaceGrid extends StatelessWidget {
  const _WorkspaceGrid({
    required this.onLibrary,
    required this.onPrint,
    required this.onRules,
    required this.onSettings,
  });
  final VoidCallback? onLibrary;
  final VoidCallback? onPrint;
  final VoidCallback onRules;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final items = <(String, IconData, Color, VoidCallback)>[
      if (onLibrary != null)
        (
          context.tr('library'),
          Icons.local_library_outlined,
          const Color(0xFF4D73B7),
          onLibrary!,
        ),
      if (onPrint != null)
        (
          context.tr('printCenter'),
          Icons.print_outlined,
          const Color(0xFFC17B37),
          onPrint!,
        ),
      (
        context.tr('rules'),
        Icons.policy_outlined,
        const Color(0xFF2D9079),
        onRules,
      ),
      (
        context.tr('settings'),
        Icons.tune_rounded,
        const Color(0xFFE07387),
        onSettings,
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = scale >= 1.6
            ? 1
            : constraints.maxWidth >= 700
            ? 4
            : 2;
        final width = (constraints.maxWidth - 11 * (columns - 1)) / columns;
        return Wrap(
          spacing: 11,
          runSpacing: 11,
          children: items
              .map(
                (item) => SizedBox(
                  width: width,
                  child: PremiumCard(
                    padding: const EdgeInsets.all(16),
                    onTap: item.$4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 40,
                          height: 40,
                          decoration: BoxDecoration(
                            color: item.$3.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(13),
                          ),
                          child: Icon(item.$2, color: item.$3),
                        ),
                        const SizedBox(height: 13),
                        Text(
                          item.$1,
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

class _ProfileMenuRow extends StatelessWidget {
  const _ProfileMenuRow({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: .12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
      trailing: onTap == null ? null : const Icon(Icons.chevron_right_rounded),
    );
  }
}

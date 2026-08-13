import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/remote_models.dart';

class RulesPage extends StatefulWidget {
  const RulesPage({super.key});

  @override
  State<RulesPage> createState() => _RulesPageState();
}

class _RulesPageState extends State<RulesPage> {
  List<ComplianceRuleInfo>? _rules;
  Object? _error;
  final Set<int> _saving = {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_rules == null && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final rules = await AppControllerScope.of(context).loadOwnRules();
      if (mounted) setState(() => _rules = rules);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _acknowledge(ComplianceRuleInfo rule) async {
    if (!_saving.add(rule.id)) return;
    setState(() {});
    try {
      await AppControllerScope.of(context).acknowledgeRule(rule.id);
      if (!mounted) return;
      setState(() {
        _rules = _rules
            ?.map(
              (item) =>
                  item.id == rule.id ? item.copyWith(acknowledged: true) : item,
            )
            .toList(growable: false);
      });
      showPremiumToast(context, context.tr('ruleAcknowledged'));
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          context.tr('changesCouldNotSave'),
          icon: Icons.info_outline_rounded,
          color: AppTheme.coral,
        );
      }
    } finally {
      _saving.remove(rule.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('rules'))),
      body: SafeArea(
        top: false,
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(child: _header(context)),
              const SliverToBoxAdapter(child: SizedBox(height: 17)),
              ..._content(context),
              const SliverToBoxAdapter(child: SizedBox(height: 32)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context) => MaxWidthBox(
    maxWidth: 800,
    child: Container(
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Theme.of(context).colorScheme.primary,
            const Color(0xFF373870),
          ],
        ),
        borderRadius: BorderRadius.circular(26),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .14),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.policy_outlined,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 15),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('rules'),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  context.tr('rulesSubtitle'),
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium?.copyWith(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  List<Widget> _content(BuildContext context) {
    if (_rules == null && _error == null) {
      return const [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      ];
    }
    if (_error != null && _rules == null) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: context.tr('rulesLoadFailed'),
            body: context.tr('employmentDataUnavailableBody'),
            icon: Icons.policy_outlined,
            action: context.tr('tryAgain'),
            onAction: _load,
          ),
        ),
      ];
    }
    final rules = _rules ?? const <ComplianceRuleInfo>[];
    if (rules.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: EmptyState(
            title: context.tr('noItems'),
            body: context.tr('rulesSubtitle'),
            icon: Icons.verified_user_outlined,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: EdgeInsets.fromLTRB(
          MediaQuery.sizeOf(context).width >= 800
              ? (MediaQuery.sizeOf(context).width - 800) / 2 + 20
              : 20,
          0,
          MediaQuery.sizeOf(context).width >= 800
              ? (MediaQuery.sizeOf(context).width - 800) / 2 + 20
              : 20,
          0,
        ),
        sliver: SliverList.separated(
          itemCount: rules.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final rule = rules[index];
            return PremiumCard(
              padding: EdgeInsets.zero,
              child: ExpansionTile(
                leading: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    rule.acknowledged
                        ? Icons.verified_user_outlined
                        : Icons.policy_outlined,
                    color: Theme.of(context).colorScheme.primary,
                    size: 21,
                  ),
                ),
                title: Text(
                  rule.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  context.l10n.format('ruleVersion', {'version': rule.version}),
                ),
                shape: const RoundedRectangleBorder(),
                collapsedShape: const RoundedRectangleBorder(),
                childrenPadding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
                expandedCrossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SelectableText(
                    rule.body,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(height: 1.55),
                  ),
                  const SizedBox(height: 16),
                  if (rule.acknowledged)
                    StatusPill(
                      label: context.tr('acknowledged'),
                      color: AppTheme.mint,
                      icon: Icons.verified_outlined,
                    )
                  else
                    FilledButton.icon(
                      onPressed: _saving.contains(rule.id)
                          ? null
                          : () => _acknowledge(rule),
                      icon: _saving.contains(rule.id)
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.fact_check_outlined),
                      label: Text(context.tr('acknowledge')),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }
}

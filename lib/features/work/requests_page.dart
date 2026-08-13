import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/workflow_models.dart';

class StaffRequestsPage extends StatefulWidget {
  const StaffRequestsPage({super.key});

  @override
  State<StaffRequestsPage> createState() => _StaffRequestsPageState();
}

class _StaffRequestsPageState extends State<StaffRequestsPage> {
  Future<List<StaffRequestInfo>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppControllerScope.of(context).loadStaffRequests();
  }

  Future<void> _refresh() async {
    final future = AppControllerScope.of(context).loadStaffRequests();
    setState(() => _future = future);
    await future;
  }

  Future<void> _create() async {
    final created = await showAppSheet<bool>(
      context: context,
      builder: (_) => const _CreateRequestSheet(),
    );
    if (created == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final canCreate = AppControllerScope.of(
      context,
    ).canMutate('approvals:write');
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('requests')),
        actions: [
          if (canCreate)
            IconButton(
              tooltip: 'New request',
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
            ),
        ],
      ),
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: _create,
              icon: const Icon(Icons.add_rounded),
              label: const Text('New request'),
            )
          : null,
      body: FutureBuilder<List<StaffRequestInfo>>(
        future: _future,
        builder: (context, snapshot) => RefreshIndicator.adaptive(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 860,
                  child: PageIntro(
                    title: context.tr('requests'),
                    subtitle: context.tr('requestsSubtitle'),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 18)),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'Requests need another moment',
                    body: 'Your request history could not be refreshed.',
                    action: context.tr('tryAgain'),
                    onAction: _refresh,
                    icon: Icons.cloud_off_outlined,
                  ),
                )
              else if ((snapshot.data ?? const []).isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: context.tr('noItems'),
                    body: context.tr('requestsSubtitle'),
                    action: canCreate ? 'Create request' : null,
                    onAction: canCreate ? _create : null,
                    icon: Icons.fact_check_outlined,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 90),
                  sliver: SliverList.separated(
                    itemCount: snapshot.data!.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 11),
                    itemBuilder: (context, index) => MaxWidthBox(
                      maxWidth: 860,
                      padding: EdgeInsets.zero,
                      child: _RequestCard(
                        request: snapshot.data![index],
                        onCancelled: _refresh,
                      ),
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

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onCancelled});

  final StaffRequestInfo request;
  final Future<void> Function() onCancelled;

  Color get _color => switch (request.status) {
    'approved' || 'disbursed' => const Color(0xFF2D8B73),
    'rejected' || 'cancelled' => AppTheme.coral,
    _ => AppTheme.gold,
  };

  @override
  Widget build(BuildContext context) => PremiumCard(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 45,
              height: 45,
              decoration: BoxDecoration(
                color: _color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.fact_check_outlined, color: _color),
            ),
            const SizedBox(width: 13),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    request.title,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    request.kind.replaceAll('_', ' '),
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            StatusPill(label: request.status, color: _color),
          ],
        ),
        if (request.description.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text(request.description),
        ],
        if (request.decisionNote.isNotEmpty) ...[
          const SizedBox(height: 13),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: _color.withValues(alpha: .08),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Text(request.decisionNote),
          ),
        ],
        const SizedBox(height: 14),
        Row(
          children: [
            if (request.amount > 0)
              Text(
                '${NumberFormat.decimalPattern().format(request.amount)} UZS',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            const Spacer(),
            if (request.createdAt != null)
              Text(
                DateFormat.yMMMd(
                  Localizations.localeOf(context).toLanguageTag(),
                ).format(request.createdAt!.toLocal()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            if (request.status == 'pending' &&
                AppControllerScope.of(
                  context,
                ).canMutate('approvals:write')) ...[
              const SizedBox(width: 6),
              TextButton(
                onPressed: () async {
                  try {
                    await AppControllerScope.of(
                      context,
                    ).cancelStaffRequest(request.id);
                    if (context.mounted) await onCancelled();
                  } catch (_) {
                    if (context.mounted) {
                      showPremiumToast(
                        context,
                        'The request could not be cancelled.',
                        color: AppTheme.coral,
                      );
                    }
                  }
                },
                child: Text(context.tr('cancel')),
              ),
            ],
          ],
        ),
      ],
    ),
  );
}

class _CreateRequestSheet extends StatefulWidget {
  const _CreateRequestSheet();

  @override
  State<_CreateRequestSheet> createState() => _CreateRequestSheetState();
}

class _CreateRequestSheetState extends State<_CreateRequestSheet> {
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _amount = TextEditingController();
  String _kind = 'leave_request';
  bool _saving = false;

  static const _types = <(String, String, IconData)>[
    ('leave_request', 'Leave request', Icons.beach_access_outlined),
    ('salary_advance', 'Salary advance', Icons.payments_outlined),
    ('schedule_change', 'Schedule change', Icons.calendar_month_outlined),
    ('loan', 'Staff loan', Icons.account_balance_wallet_outlined),
    ('procurement', 'Purchase request', Icons.shopping_bag_outlined),
    ('other', 'Other request', Icons.more_horiz_rounded),
  ];

  bool get _needsAmount =>
      const {'salary_advance', 'loan', 'procurement'}.contains(_kind);

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_title.text.trim().isEmpty || _description.text.trim().isEmpty) {
      showPremiumToast(
        context,
        'Add a clear title and details.',
        color: AppTheme.gold,
      );
      return;
    }
    final amount = _needsAmount ? double.tryParse(_amount.text.trim()) : null;
    if (_needsAmount && (amount == null || amount <= 0)) {
      showPremiumToast(context, 'Enter a valid amount.', color: AppTheme.gold);
      return;
    }
    setState(() => _saving = true);
    try {
      await AppControllerScope.of(context).createStaffRequest(
        kind: _kind,
        title: _title.text,
        description: _description.text,
        amount: amount,
      );
      if (!mounted) return;
      showPremiumToast(context, 'Your request was sent.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          'The request could not be sent.',
          color: AppTheme.coral,
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      24,
      0,
      24,
      24 + MediaQuery.viewInsetsOf(context).bottom,
    ),
    child: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'New request',
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Choose a category and explain what you need. No technical forms or codes.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _types
                .map(
                  (type) => ChoiceChip(
                    avatar: Icon(type.$3, size: 18),
                    label: Text(type.$2),
                    selected: _kind == type.$1,
                    onSelected: (_) => setState(() => _kind = type.$1),
                  ),
                )
                .toList(growable: false),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _title,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          const SizedBox(height: 12),
          if (_needsAmount) ...[
            TextField(
              controller: _amount,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'Amount (UZS)'),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _description,
            minLines: 4,
            maxLines: 7,
            decoration: const InputDecoration(
              labelText: 'Details',
              hintText: 'Explain the request and when you need it.',
            ),
          ),
          const SizedBox(height: 20),
          FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: const Text('Send request'),
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

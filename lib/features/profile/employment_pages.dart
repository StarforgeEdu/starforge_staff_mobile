import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/remote_models.dart';

class SalaryHistoryPage extends StatefulWidget {
  const SalaryHistoryPage({super.key});

  @override
  State<SalaryHistoryPage> createState() => _SalaryHistoryPageState();
}

class _SalaryHistoryPageState extends State<SalaryHistoryPage> {
  List<PayrollPayslipInfo>? _items;
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && _error == null) _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final result = await AppControllerScope.of(context).loadOwnPayslips();
      if (mounted) setState(() => _items = result);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('salaryHistory'))),
      body: SafeArea(
        top: false,
        child: RefreshIndicator.adaptive(
          onRefresh: _load,
          child: _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_items == null && _error == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _items == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .16),
          EmptyState(
            title: context.tr('employmentDataUnavailable'),
            body: context.tr('employmentDataUnavailableBody'),
            icon: Icons.lock_clock_outlined,
            action: context.tr('tryAgain'),
            onAction: _load,
          ),
        ],
      );
    }
    final items = _items ?? const <PayrollPayslipInfo>[];
    if (items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .16),
          EmptyState(
            title: context.tr('noPayslips'),
            body: context.tr('noPayslipsBody'),
            icon: Icons.payments_outlined,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
      itemCount: items.length + 2,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) return _PayslipSummary(item: items.first);
        if (index == items.length + 1) {
          return Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              context.tr('salaryPrivate'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        return _PayslipCard(item: items[index - 1]);
      },
    );
  }
}

class _PayslipSummary extends StatelessWidget {
  const _PayslipSummary({required this.item});
  final PayrollPayslipInfo item;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF176B5B), Color(0xFF243F49)],
        ),
        borderRadius: BorderRadius.circular(27),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            context.tr('salaryCurrent').toUpperCase(),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Colors.white70,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _money(item.netAmount, item.currency),
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 11),
          StatusPill(
            label: _status(context, item.periodStatus),
            color: _statusColor(item.periodStatus),
            icon: Icons.verified_user_outlined,
          ),
          if (item.periodLabel.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              item.periodLabel,
              style: const TextStyle(color: Colors.white70),
            ),
          ],
        ],
      ),
    );
  }
}

class _PayslipCard extends StatelessWidget {
  const _PayslipCard({required this.item});
  final PayrollPayslipInfo item;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final date = item.payDate ?? item.periodEnd ?? item.generatedAt;
    return PremiumCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact =
              constraints.maxWidth < 360 ||
              MediaQuery.textScalerOf(context).scale(1) >= 1.45;
          final icon = Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: _statusColor(item.periodStatus).withValues(alpha: .13),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Icon(
              Icons.receipt_long_outlined,
              color: _statusColor(item.periodStatus),
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.periodLabel.isNotEmpty
                    ? item.periodLabel
                    : item.documentNumber,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                [
                  if (date != null) DateFormat.yMMMd(locale).format(date),
                  if (item.branchName.isNotEmpty) item.branchName,
                ].join(' · '),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          );
          final amount = Column(
            crossAxisAlignment: compact
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              Text(
                _money(item.netAmount, item.currency),
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 4),
              Text(
                _status(context, item.periodStatus),
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _statusColor(item.periodStatus),
                ),
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    icon,
                    const SizedBox(width: 13),
                    Expanded(child: details),
                  ],
                ),
                const SizedBox(height: 14),
                amount,
              ],
            );
          }
          return Row(
            children: [
              icon,
              const SizedBox(width: 13),
              Expanded(child: details),
              const SizedBox(width: 10),
              amount,
            ],
          );
        },
      ),
    );
  }
}

String _money(double amount, String currency) {
  final formatted = NumberFormat.decimalPattern().format(amount.round());
  return '$formatted ${currency.isEmpty ? 'UZS' : currency}';
}

String _status(BuildContext context, String value) => switch (value) {
  'paid' => context.tr('payslipPaid'),
  'rejected' => context.tr('failed'),
  _ => context.tr('payslipPending'),
};

Color _statusColor(String value) => switch (value) {
  'paid' => AppTheme.mint,
  'rejected' => AppTheme.coral,
  _ => AppTheme.gold,
};

class ContractPage extends StatelessWidget {
  const ContractPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('contract'))),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * .16),
            EmptyState(
              title: context.tr('contractUnavailable'),
              body: context.tr('contractUnavailableBody'),
              icon: Icons.description_outlined,
            ),
          ],
        ),
      ),
    );
  }
}

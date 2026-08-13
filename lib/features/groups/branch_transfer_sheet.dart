import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/workflow_models.dart';

Future<bool> showGroupBranchTransferSheet(
  BuildContext context,
  LearningGroup group,
) async {
  final branchId = group.branchId;
  if (branchId == null) return false;
  return await showAppSheet<bool>(
        context: context,
        builder: (_) => _BranchTransferSheet(
          title: context.tr('moveGroupBranch'),
          subjectName: group.name,
          currentBranchId: branchId,
          currentBranchName: group.branch,
          impact: context.tr('groupTransferImpact'),
          onTransfer: (destination, reason) =>
              AppControllerScope.of(context).transferGroupBranch(
                group: group,
                destinationBranchId: destination,
                reason: reason,
              ),
        ),
      ) ??
      false;
}

Future<bool> showStudentBranchTransferSheet(
  BuildContext context, {
  required Student student,
  required LearningGroup group,
}) async {
  final branchId = group.branchId;
  if (branchId == null) return false;
  return await showAppSheet<bool>(
        context: context,
        builder: (_) => _BranchTransferSheet(
          title: context.tr('moveStudentBranch'),
          subjectName: student.name,
          currentBranchId: branchId,
          currentBranchName: group.branch,
          impact: context.tr('studentTransferImpact'),
          onTransfer: (destination, reason) =>
              AppControllerScope.of(context).transferStudentBranch(
                student: student,
                group: group,
                destinationBranchId: destination,
                reason: reason,
              ),
        ),
      ) ??
      false;
}

class _BranchTransferSheet extends StatefulWidget {
  const _BranchTransferSheet({
    required this.title,
    required this.subjectName,
    required this.currentBranchId,
    required this.currentBranchName,
    required this.impact,
    required this.onTransfer,
  });

  final String title;
  final String subjectName;
  final int currentBranchId;
  final String currentBranchName;
  final String impact;
  final Future<void> Function(int destination, String reason) onTransfer;

  @override
  State<_BranchTransferSheet> createState() => _BranchTransferSheetState();
}

class _BranchTransferSheetState extends State<_BranchTransferSheet> {
  final _reason = TextEditingController();
  Future<List<BranchChoiceInfo>>? _branches;
  int? _destination;
  bool _confirmed = false;
  bool _busy = false;
  bool _reasonReady = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _branches ??= AppControllerScope.of(
      context,
    ).loadTransferBranches(currentBranchId: widget.currentBranchId);
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final destination = _destination;
    final reason = _reason.text.trim();
    if (destination == null || reason.isEmpty || !_confirmed || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.onTransfer(destination, reason);
      if (!mounted) return;
      showPremiumToast(
        context,
        context.tr('transferComplete'),
        icon: Icons.compare_arrows_rounded,
        color: AppTheme.mint,
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = context.tr('transferCouldNotComplete');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ready = _destination != null && _reasonReady && _confirmed && !_busy;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * .84,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
          child: MaxWidthBox(
            maxWidth: 620,
            padding: EdgeInsets.zero,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(15),
                      ),
                      child: Icon(
                        Icons.compare_arrows_rounded,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(widget.title, style: theme.textTheme.titleLarge),
                          const SizedBox(height: 3),
                          Text(
                            widget.subjectName,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _BranchLine(
                  label: context.tr('currentBranch'),
                  value: widget.currentBranchName,
                  icon: Icons.location_on_outlined,
                ),
                const SizedBox(height: 13),
                FutureBuilder<List<BranchChoiceInfo>>(
                  future: _branches,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const SizedBox(
                        height: 58,
                        child: Center(
                          child: CircularProgressIndicator.adaptive(),
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return _InlineNotice(
                        icon: Icons.cloud_off_outlined,
                        text: context.tr('branchesLoadFailed'),
                      );
                    }
                    final branches = snapshot.data ?? const [];
                    if (branches.isEmpty) {
                      return _InlineNotice(
                        icon: Icons.info_outline_rounded,
                        text: context.tr('noTransferBranches'),
                      );
                    }
                    return DropdownButtonFormField<int>(
                      initialValue: _destination,
                      decoration: InputDecoration(
                        labelText: context.tr('destinationBranch'),
                        prefixIcon: const Icon(Icons.alt_route_rounded),
                      ),
                      items: branches
                          .map(
                            (branch) => DropdownMenuItem(
                              value: branch.id,
                              child: Text(branch.name),
                            ),
                          )
                          .toList(growable: false),
                      onChanged: _busy
                          ? null
                          : (value) => setState(() => _destination = value),
                    );
                  },
                ),
                const SizedBox(height: 13),
                TextField(
                  controller: _reason,
                  enabled: !_busy,
                  minLines: 2,
                  maxLines: 3,
                  maxLength: 64,
                  onChanged: (value) {
                    final next = value.trim().isNotEmpty;
                    if (next != _reasonReady) {
                      setState(() => _reasonReady = next);
                    }
                  },
                  decoration: InputDecoration(
                    labelText: context.tr('transferReason'),
                    hintText: context.tr('transferReasonHint'),
                    alignLabelWithHint: true,
                    prefixIcon: const Padding(
                      padding: EdgeInsets.only(bottom: 42),
                      child: Icon(Icons.edit_note_rounded),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppTheme.gold.withValues(alpha: .1),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: AppTheme.gold.withValues(alpha: .22),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.shield_outlined,
                        color: Color(0xFFC47B16),
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              context.tr('transferImpact'),
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 4),
                            Text(widget.impact),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                CheckboxListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  value: _confirmed,
                  onChanged: _busy
                      ? null
                      : (value) => setState(() => _confirmed = value ?? false),
                  title: Text(context.tr('confirmTransferImpact')),
                  subtitle: Text(context.tr('transferAuditNotice')),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    _error!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: ready ? _submit : null,
                  icon: _busy
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.compare_arrows_rounded),
                  label: Text(
                    _busy
                        ? context.tr('movingBranch')
                        : context.tr('confirmBranchTransfer'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BranchLine extends StatelessWidget {
  const _BranchLine({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: Theme.of(context).textTheme.labelSmall),
              Text(value.isEmpty ? '—' : value),
            ],
          ),
        ),
      ],
    ),
  );
}

class _InlineNotice extends StatelessWidget {
  const _InlineNotice({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Row(
      children: [
        Icon(icon),
        const SizedBox(width: 10),
        Expanded(child: Text(text)),
      ],
    ),
  );
}

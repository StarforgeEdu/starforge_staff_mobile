import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/workflow_models.dart';

class StaffReportsPage extends StatefulWidget {
  const StaffReportsPage({super.key});

  @override
  State<StaffReportsPage> createState() => _StaffReportsPageState();
}

class _StaffReportsPageState extends State<StaffReportsPage> {
  Future<(List<StaffReportInfo>, List<StaffReportRunInfo>)>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  Future<(List<StaffReportInfo>, List<StaffReportRunInfo>)> _load() async {
    final controller = AppControllerScope.of(context);
    final results = await Future.wait<Object>([
      controller.loadStaffReports(),
      controller.loadStaffReportRuns(),
    ]);
    return (
      results[0] as List<StaffReportInfo>,
      results[1] as List<StaffReportRunInfo>,
    );
  }

  Future<void> _refresh() async {
    final future = _load();
    setState(() => _future = future);
    await future;
  }

  Future<void> _prepare(StaffReportInfo report) async {
    final created = await showAppSheet<bool>(
      context: context,
      builder: (_) => _PrepareReportSheet(report: report),
    );
    if (created == true && mounted) await _refresh();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('reports'))),
    body: FutureBuilder<(List<StaffReportInfo>, List<StaffReportRunInfo>)>(
      future: _future,
      builder: (context, snapshot) {
        final library = snapshot.data?.$1 ?? const <StaffReportInfo>[];
        final runs = snapshot.data?.$2 ?? const <StaffReportRunInfo>[];
        return RefreshIndicator.adaptive(
          onRefresh: _refresh,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: PageIntro(
                    title: context.tr('reports'),
                    subtitle: context.tr('reportsSubtitle'),
                    trailing: runs.isEmpty
                        ? null
                        : StatusPill(
                            label:
                                '${runs.where((run) => run.status == 'done').length} ready',
                            color: const Color(0xFF2D8B73),
                          ),
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 20)),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'Reports need another moment',
                    body: 'The report library could not be refreshed.',
                    action: context.tr('tryAgain'),
                    onAction: _refresh,
                    icon: Icons.cloud_off_outlined,
                  ),
                )
              else ...[
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: SectionHeader(
                      title: 'Report library',
                      subtitle:
                          'Choose a report, scope it to one of your groups, and send it to a manager.',
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 11)),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 26),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.crossAxisExtent >= 720
                          ? 3
                          : 1;
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 11,
                          mainAxisSpacing: 11,
                          mainAxisExtent: 202,
                        ),
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final report = library[index];
                          return PremiumCard(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF277DA1,
                                    ).withValues(alpha: .12),
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: const Icon(
                                    Icons.description_outlined,
                                    color: Color(0xFF277DA1),
                                  ),
                                ),
                                const SizedBox(height: 13),
                                Text(
                                  report.title,
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                const SizedBox(height: 5),
                                Expanded(
                                  child: Text(
                                    report.description,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: Theme.of(context).textTheme.bodySmall
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.onSurfaceVariant,
                                        ),
                                  ),
                                ),
                                FilledButton.tonalIcon(
                                  onPressed:
                                      AppControllerScope.of(
                                        context,
                                      ).canMutate('reports:write')
                                      ? () => _prepare(report)
                                      : null,
                                  icon: const Icon(Icons.auto_fix_high_rounded),
                                  label: const Text('Prepare'),
                                ),
                              ],
                            ),
                          );
                        }, childCount: library.length),
                      );
                    },
                  ),
                ),
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: SectionHeader(
                      title: 'Prepared reports',
                      subtitle:
                          'Open completed files or follow reports still being prepared.',
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 11)),
                if (runs.isEmpty)
                  SliverToBoxAdapter(
                    child: MaxWidthBox(
                      child: PremiumCard(
                        child: EmptyState(
                          title: 'No prepared reports yet',
                          body:
                              'Choose a report above to create the first shareable copy.',
                          icon: Icons.description_outlined,
                        ),
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 38),
                    sliver: SliverList.separated(
                      itemCount: runs.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) => MaxWidthBox(
                        padding: EdgeInsets.zero,
                        child: _ReportRunCard(run: runs[index]),
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      },
    ),
  );
}

class _ReportRunCard extends StatelessWidget {
  const _ReportRunCard({required this.run});

  final StaffReportRunInfo run;

  @override
  Widget build(BuildContext context) {
    final color = switch (run.status) {
      'done' => const Color(0xFF2D8B73),
      'failed' => AppTheme.coral,
      _ => AppTheme.gold,
    };
    return PremiumCard(
      onTap: run.downloadUrl.isEmpty
          ? null
          : () async {
              final uri = Uri.tryParse(run.downloadUrl);
              if (uri == null || !await launchUrl(uri)) {
                if (context.mounted) {
                  showPremiumToast(
                    context,
                    'The report file could not be opened.',
                    color: AppTheme.coral,
                  );
                }
              }
            },
      padding: const EdgeInsets.all(15),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              run.status == 'done'
                  ? Icons.file_download_done_rounded
                  : run.status == 'failed'
                  ? Icons.error_outline_rounded
                  : Icons.hourglass_top_rounded,
              color: color,
            ),
          ),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  run.reportKey.replaceAll('_', ' '),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 3),
                Text(
                  '${run.format.toUpperCase()}${run.createdAt == null ? '' : ' · ${DateFormat.yMMMd(Localizations.localeOf(context).toLanguageTag()).add_Hm().format(run.createdAt!.toLocal())}'}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          StatusPill(label: run.status, color: color),
          if (run.downloadUrl.isNotEmpty) ...[
            const SizedBox(width: 7),
            const Icon(Icons.open_in_new_rounded),
          ],
        ],
      ),
    );
  }
}

class _PrepareReportSheet extends StatefulWidget {
  const _PrepareReportSheet({required this.report});

  final StaffReportInfo report;

  @override
  State<_PrepareReportSheet> createState() => _PrepareReportSheetState();
}

class _PrepareReportSheetState extends State<_PrepareReportSheet> {
  List<LearningGroup> _groups = const [];
  List<ChatContact> _managers = const [];
  int? _groupId;
  int? _recipientId;
  String _format = 'pdf';
  late DateTime _from = DateTime.now().subtract(const Duration(days: 30));
  late DateTime _to = DateTime.now();
  bool _loading = true;
  bool _saving = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_loading) _loadOptions();
  }

  Future<void> _loadOptions() async {
    final controller = AppControllerScope.of(context);
    final responses = await Future.wait<Object>([
      controller.loadGroups(),
      if (controller.can('messaging:read'))
        controller.loadMessagingWorkspace()
      else
        Future.value(const MessagingWorkspace.empty()),
    ]);
    if (!mounted) return;
    final groups = responses[0] as List<LearningGroup>;
    final workspace = responses[1] as MessagingWorkspace;
    final managers = workspace.contacts
        .where((contact) {
          final role = contact.role.toLowerCase();
          return role.contains('manager') ||
              role.contains('director') ||
              role.contains('head') ||
              role.contains('ceo');
        })
        .toList(growable: false);
    setState(() {
      _groups = groups.where((group) => group.remoteId != null).toList();
      _groupId = _groups.firstOrNull?.remoteId;
      _managers = managers;
      _format = widget.report.defaultFormat;
      _loading = false;
    });
  }

  Future<void> _pickDate(bool from) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 2),
      lastDate: DateTime(DateTime.now().year + 1),
      initialDate: from ? _from : _to,
    );
    if (selected != null) {
      setState(() => from ? _from = selected : _to = selected);
    }
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await AppControllerScope.of(context).createStaffReportRun(
        reportKey: widget.report.key,
        format: _format,
        params: {
          if (_groupId != null &&
              const {'attendance', 'enrollment'}.contains(widget.report.key))
            'cohort_id': _groupId,
          if (widget.report.key == 'attendance') ...{
            'date_from': _from.toIso8601String().split('T').first,
            'date_to': _to.toIso8601String().split('T').first,
          },
        },
        recipientIds: _recipientId == null ? const [] : [_recipientId!],
      );
      if (!mounted) return;
      showPremiumToast(
        context,
        _recipientId == null
            ? 'Your report is being prepared.'
            : 'Your report is being prepared and will be shared when ready.',
      );
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          'The report could not be prepared.',
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
            widget.report.title,
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 6),
          Text(
            'Choose the exact teaching scope and an optional recipient.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          if (_loading)
            const Center(child: CircularProgressIndicator.adaptive())
          else ...[
            if (const {'attendance', 'enrollment'}.contains(widget.report.key))
              DropdownButtonFormField<int>(
                initialValue: _groupId,
                decoration: const InputDecoration(labelText: 'Group'),
                items: _groups
                    .map(
                      (group) => DropdownMenuItem(
                        value: group.remoteId,
                        child: Text(group.name),
                      ),
                    )
                    .toList(growable: false),
                onChanged: (value) => setState(() => _groupId = value),
              ),
            if (widget.report.key == 'attendance') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(true),
                      icon: const Icon(Icons.calendar_today_outlined),
                      label: Text(DateFormat.yMMMd().format(_from)),
                    ),
                  ),
                  const SizedBox(width: 9),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _pickDate(false),
                      icon: const Icon(Icons.event_available_outlined),
                      label: Text(DateFormat.yMMMd().format(_to)),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'pdf', label: Text('PDF')),
                ButtonSegment(value: 'xlsx', label: Text('Excel')),
              ],
              selected: {_format},
              onSelectionChanged: (value) =>
                  setState(() => _format = value.first),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _recipientId,
              decoration: const InputDecoration(
                labelText: 'Send to',
                helperText: 'Optional — you always receive the completed copy.',
              ),
              items: [
                const DropdownMenuItem<int?>(
                  value: null,
                  child: Text('Only me'),
                ),
                ..._managers.map(
                  (contact) => DropdownMenuItem<int?>(
                    value: contact.remoteUserId,
                    child: Text(contact.name),
                  ),
                ),
              ],
              onChanged: (value) => setState(() => _recipientId = value),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.auto_fix_high_rounded),
              label: const Text('Prepare report'),
            ),
          ],
        ],
      ),
    ),
  );
}

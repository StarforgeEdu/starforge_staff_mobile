import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';

class PrintPage extends StatefulWidget {
  const PrintPage({super.key});

  @override
  State<PrintPage> createState() => _PrintPageState();
}

class _PrintPageState extends State<PrintPage> {
  PrintWorkspace _workspace = const PrintWorkspace.empty();
  PrinterDevice? _printer;
  String _material = '';
  String? _filePath;
  String? _contentType;
  int? _fileSize;
  LibraryResource? _libraryResource;
  int _copies = 1;
  bool _color = false;
  bool _doubleSided = true;
  bool _loading = true;
  bool _failed = false;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final workspace = await AppControllerScope.of(
        context,
      ).loadPrintWorkspace();
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _printer = workspace.printers.isEmpty
            ? null
            : workspace.printers.firstWhere(
                (printer) => printer.id == _printer?.id,
                orElse: () => workspace.printers.firstWhere(
                  (printer) => !printer.isOffline,
                  orElse: () => workspace.printers.first,
                ),
              );
        if (_printer?.supportsColor != true) _color = false;
        if (_printer?.supportsDuplex != true) _doubleSided = false;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _chooseDeviceFile() async {
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'jpg', 'jpeg', 'png', 'webp'],
    );
    if (!mounted || result == null) return;
    final file = result.files.single;
    final path = file.path;
    final extension = file.extension?.toLowerCase() ?? '';
    final contentType = switch (extension) {
      'pdf' => 'application/pdf',
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      _ => null,
    };
    if (path == null || path.isEmpty || file.size < 1 || contentType == null) {
      showPremiumToast(
        context,
        context.tr('printFileUnsupported'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
      return;
    }
    setState(() {
      _material = file.name;
      _filePath = path;
      _contentType = contentType;
      _fileSize = file.size;
      _libraryResource = null;
    });
  }

  Future<void> _chooseLibraryFile() async {
    try {
      final workspace = await AppControllerScope.of(context).loadLibrary();
      if (!mounted) return;
      final resources = workspace.resources
          .where(
            (resource) =>
                resource.remoteFileId != null &&
                resource.downloadable &&
                resource.status == 'clean' &&
                const {
                  'application/pdf',
                  'image/jpeg',
                  'image/png',
                  'image/webp',
                }.contains(resource.contentType.toLowerCase()),
          )
          .toList(growable: false);
      final selected = await showAppSheet<LibraryResource>(
        context: context,
        builder: (sheetContext) => FractionallySizedBox(
          heightFactor: .78,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('printLibraryTitle'),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 6),
                Text(
                  context.tr('printLibrarySourceNote'),
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: resources.isEmpty
                      ? EmptyState(
                          title: context.tr('noPrintableMaterials'),
                          body: context.tr('noPrintableMaterialsBody'),
                          icon: Icons.library_books_outlined,
                        )
                      : ListView.separated(
                          itemCount: resources.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 8),
                          itemBuilder: (context, index) {
                            final resource = resources[index];
                            return PremiumCard(
                              onTap: () =>
                                  Navigator.pop(sheetContext, resource),
                              child: Row(
                                children: [
                                  Icon(resource.icon, color: resource.color),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          resource.title,
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        if (resource.subtitle.isNotEmpty) ...[
                                          const SizedBox(height: 3),
                                          Text(
                                            resource.subtitle,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.bodySmall,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const Icon(Icons.chevron_right_rounded),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      );
      if (!mounted || selected == null) return;
      setState(() {
        _material = selected.title;
        _libraryResource = selected;
        _filePath = null;
        _contentType = null;
        _fileSize = null;
      });
    } catch (_) {
      if (!mounted) return;
      showPremiumToast(
        context,
        context.tr('changesCouldNotSave'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  void _chooseMaterial() {
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('selectMaterial'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            PremiumCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.local_library_outlined),
                    title: Text(context.tr('fromLibrary')),
                    subtitle: Text(context.tr('printLibrarySourceNote')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _chooseLibraryFile();
                    },
                  ),
                  const Divider(indent: 54),
                  ListTile(
                    leading: const Icon(Icons.phone_iphone_rounded),
                    title: Text(context.tr('fromDevice')),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _chooseDeviceFile();
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _schedule() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: context.tr('schedulePrint'),
    );
    if (!mounted || date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(now.add(const Duration(minutes: 15))),
      helpText: context.tr('schedulePrint'),
    );
    if (!mounted || time == null) return;
    final scheduledFor = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (!scheduledFor.isAfter(DateTime.now())) {
      showPremiumToast(
        context,
        context.tr('printScheduleFuture'),
        icon: Icons.schedule_rounded,
        color: AppTheme.coral,
      );
      return;
    }
    await _submit(scheduledFor: scheduledFor);
  }

  Future<void> _submit({DateTime? scheduledFor}) async {
    final printer = _printer;
    if (_submitting || printer == null || printer.isOffline) return;
    final controller = AppControllerScope.of(context);
    setState(() => _submitting = true);
    try {
      final resource = _libraryResource;
      if (resource != null) {
        await controller.submitLibraryPrintJob(
          resource: resource,
          printer: printer,
          copies: _copies,
          color: _color,
          duplex: _doubleSided,
          scheduledFor: scheduledFor,
        );
      } else {
        final path = _filePath;
        final contentType = _contentType;
        final size = _fileSize;
        if (path == null || contentType == null || size == null) return;
        await controller.submitPrintJob(
          filePath: path,
          filename: _material,
          contentType: contentType,
          sizeBytes: size,
          printer: printer,
          copies: _copies,
          color: _color,
          duplex: _doubleSided,
          scheduledFor: scheduledFor,
        );
      }
      if (!mounted) return;
      showPremiumToast(
        context,
        context.tr(scheduledFor == null ? 'printQueued' : 'jobScheduled'),
        icon: scheduledFor == null
            ? Icons.print_rounded
            : Icons.schedule_rounded,
      );
      setState(() {
        _material = '';
        _filePath = null;
        _contentType = null;
        _fileSize = null;
        _libraryResource = null;
        _copies = 1;
      });
      await _load();
    } catch (_) {
      if (!mounted) return;
      showPremiumToast(
        context,
        context.tr('printSubmitFailed'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textScale = MediaQuery.textScalerOf(context).scale(1);
    final printerStripHeight = (176 + (textScale - 1).clamp(0, 1.5) * 270)
        .clamp(176, 581)
        .toDouble();
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('printCenter'))),
      body: SafeArea(
        top: false,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 860,
                child: PageIntro(
                  title: context.tr('availablePrinters'),
                  subtitle: context.tr('printerSubtitle'),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 15)),
            SliverToBoxAdapter(
              child: SizedBox(
                height: printerStripHeight,
                child: _loading
                    ? const _PrinterSkeleton()
                    : _failed
                    ? Center(
                        child: FilledButton.tonalIcon(
                          onPressed: _load,
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(context.tr('tryAgain')),
                        ),
                      )
                    : _workspace.printers.isEmpty
                    ? Center(
                        child: Text(
                          context.tr('noPrinters'),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      )
                    : ListView.separated(
                        scrollDirection: Axis.horizontal,
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          MediaQuery.sizeOf(context).width >= 860
                              ? (MediaQuery.sizeOf(context).width - 860) / 2 +
                                    20
                              : 20,
                          0,
                          20,
                          0,
                        ),
                        itemCount: _workspace.printers.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 11),
                        itemBuilder: (context, index) => SizedBox(
                          width: 280,
                          child: _PrinterCard(
                            printer: _workspace.printers[index],
                            selected:
                                _printer?.id == _workspace.printers[index].id,
                            onTap: () => setState(() {
                              _printer = _workspace.printers[index];
                              if (!_printer!.supportsColor) _color = false;
                              if (!_printer!.supportsDuplex) {
                                _doubleSided = false;
                              }
                            }),
                          ),
                        ),
                      ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 860,
                child: SectionHeader(title: context.tr('selectMaterial')),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 11)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 860,
                child: PremiumCard(
                  onTap: _chooseMaterial,
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 58,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE66C72).withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: const Icon(
                          Icons.picture_as_pdf_rounded,
                          color: Color(0xFFE0525B),
                        ),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _material.isEmpty
                                  ? context.tr('chooseFile')
                                  : _material,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _material.isEmpty
                                  ? context.tr('selectMaterial')
                                  : context.tr('readyToConfigure'),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.swap_horiz_rounded),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 860,
                child: PremiumCard(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 11, 10, 11),
                        child: _CountControl(
                          icon: Icons.copy_all_outlined,
                          label: context.tr('copies'),
                          value: _copies,
                          decreaseLabel: context.tr('decreaseCopies'),
                          increaseLabel: context.tr('increaseCopies'),
                          onDecrease: _copies <= 1
                              ? null
                              : () => setState(() => _copies--),
                          onIncrease: _copies >= 100
                              ? null
                              : () => setState(() => _copies++),
                        ),
                      ),
                      const Divider(indent: 50),
                      SwitchListTile.adaptive(
                        secondary: const Icon(Icons.palette_outlined),
                        title: Text(context.tr('color')),
                        subtitle: Text(
                          _color
                              ? context.tr('color')
                              : context.tr('blackWhite'),
                        ),
                        value: _color,
                        onChanged: _printer?.supportsColor == true
                            ? (value) => setState(() => _color = value)
                            : null,
                      ),
                      const Divider(indent: 50),
                      SwitchListTile.adaptive(
                        secondary: const Icon(Icons.flip_to_back_rounded),
                        title: Text(context.tr('doubleSided')),
                        value: _doubleSided,
                        onChanged: _printer?.supportsDuplex == true
                            ? (value) => setState(() => _doubleSided = value)
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 20)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 860,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final actions = [
                      OutlinedButton.icon(
                        onPressed:
                            _submitting ||
                                _printer == null ||
                                _printer!.isOffline ||
                                _material.isEmpty
                            ? null
                            : _schedule,
                        icon: const Icon(Icons.schedule_send_outlined),
                        label: Text(context.tr('schedulePrint')),
                      ),
                      FilledButton.icon(
                        onPressed:
                            _submitting ||
                                _printer == null ||
                                _printer!.isOffline ||
                                _printer!.isBusy ||
                                _material.isEmpty
                            ? null
                            : _submit,
                        icon: _submitting
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.print_rounded),
                        label: Text(
                          context.tr(
                            _submitting ? 'submittingPrint' : 'printNow',
                          ),
                        ),
                      ),
                    ];
                    if (constraints.maxWidth < 430) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          actions[0],
                          const SizedBox(height: 10),
                          actions[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: actions[0]),
                        const SizedBox(width: 10),
                        Expanded(child: actions[1]),
                      ],
                    );
                  },
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 27)),
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 860,
                child: SectionHeader(title: context.tr('scheduledJobs')),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 11)),
            if (_workspace.jobs.isEmpty)
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 860,
                  child: EmptyState(
                    title: context.tr('noPrintJobs'),
                    body: context.tr('noPrintJobsBody'),
                    icon: Icons.print_disabled_outlined,
                  ),
                ),
              )
            else
              SliverList.separated(
                itemCount: _workspace.jobs.length.clamp(0, 12),
                separatorBuilder: (_, _) => const SizedBox(height: 9),
                itemBuilder: (context, index) => MaxWidthBox(
                  maxWidth: 860,
                  child: _PrintJobCard(job: _workspace.jobs[index]),
                ),
              ),
            const SliverToBoxAdapter(child: SizedBox(height: 34)),
          ],
        ),
      ),
    );
  }
}

class _PrinterSkeleton extends StatelessWidget {
  const _PrinterSkeleton();

  @override
  Widget build(BuildContext context) => ListView.separated(
    scrollDirection: Axis.horizontal,
    padding: const EdgeInsets.symmetric(horizontal: 20),
    itemCount: 3,
    separatorBuilder: (_, _) => const SizedBox(width: 11),
    itemBuilder: (context, index) => Container(
      width: 280,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(
          alpha: .6 - index * .08,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
    ),
  );
}

class _CountControl extends StatelessWidget {
  const _CountControl({
    required this.icon,
    required this.label,
    required this.value,
    required this.decreaseLabel,
    required this.increaseLabel,
    required this.onDecrease,
    required this.onIncrease,
  });

  final IconData icon;
  final String label;
  final int value;
  final String decreaseLabel;
  final String increaseLabel;
  final VoidCallback? onDecrease;
  final VoidCallback? onIncrease;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Icon(icon),
        const SizedBox(width: 12),
        Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
        IconButton.filledTonal(
          tooltip: decreaseLabel,
          onPressed: onDecrease,
          icon: const Icon(Icons.remove_rounded),
        ),
        SizedBox(
          width: 52,
          child: Semantics(
            liveRegion: true,
            label: '$label: $value',
            child: Text(
              '$value',
              style: theme.textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
          ),
        ),
        IconButton.filledTonal(
          tooltip: increaseLabel,
          onPressed: onIncrease,
          icon: const Icon(Icons.add_rounded),
        ),
      ],
    );
  }
}

class _PrintJobCard extends StatelessWidget {
  const _PrintJobCard({required this.job});

  final StaffPrintJob job;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final status = switch (job.status) {
      'queued' => context.tr('queued'),
      'picked' => context.tr('picked'),
      'printing' => context.tr('printing'),
      'done' => context.tr('done'),
      'failed' => context.tr('failed'),
      'reconciliation_required' => context.tr('needsReview'),
      _ => job.status,
    };
    final source = switch (job.source) {
      'assignment' => context.tr('assignment'),
      'transcript' => context.tr('transcript'),
      'report' => context.tr('report'),
      'receipt' => context.tr('receipt'),
      _ => context.tr('document'),
    };
    final color = switch (job.status) {
      'done' => AppTheme.mint,
      'failed' || 'reconciliation_required' => AppTheme.coral,
      _ => AppTheme.gold,
    };
    return PremiumCard(
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .13),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(Icons.print_outlined, color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$source · #${job.id}',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  '${DateFormat.MMMd(locale).add_Hm().format((job.scheduledFor ?? job.createdAt).toLocal())} · ${context.trCount('pagesCount', job.pages)} · ${context.trCount('copiesCount', job.copies)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          StatusPill(label: status, color: color),
        ],
      ),
    );
  }
}

class _PrinterCard extends StatelessWidget {
  const _PrinterCard({
    required this.printer,
    required this.selected,
    required this.onTap,
  });
  final PrinterDevice printer;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = printer.isOffline
        ? AppTheme.coral
        : printer.isBusy
        ? AppTheme.gold
        : AppTheme.mint;
    final status = printer.isOffline
        ? context.tr('printerOffline')
        : printer.isBusy
        ? context.tr('busy')
        : context.tr('available');
    return Semantics(
      selected: selected,
      button: true,
      enabled: !printer.isOffline,
      label: '${printer.name}, $status',
      child: PremiumCard(
        onTap: printer.isOffline ? null : onTap,
        border: BorderSide(
          color: selected
              ? theme.colorScheme.primary
              : theme.colorScheme.outlineVariant.withValues(alpha: .42),
          width: selected ? 1.7 : 1,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(
                    Icons.print_rounded,
                    color: theme.colorScheme.primary,
                  ),
                ),
                StatusPill(
                  label: status,
                  color: color,
                  icon: MediaQuery.textScalerOf(context).scale(1) >= 1.5
                      ? null
                      : Icons.circle,
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              printer.name,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              printer.location.isEmpty
                  ? context.tr('printerReady')
                  : printer.location,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const Spacer(),
            Row(
              children: [
                Icon(
                  printer.supportsColor
                      ? Icons.palette_outlined
                      : Icons.tonality_outlined,
                  size: 17,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    printer.supportsColor
                        ? context.tr('color')
                        : context.tr('blackWhite'),
                    style: theme.textTheme.labelSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  printer.paper.isEmpty ? 'A4' : printer.paper,
                  style: theme.textTheme.labelSmall,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

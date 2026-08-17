import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../services/content_protection.dart';
import 'library_upload_filename.dart';

class LibraryPage extends StatefulWidget {
  const LibraryPage({super.key});

  @override
  State<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends State<LibraryPage> {
  final _searchController = TextEditingController();
  LibraryWorkspace _workspace = const LibraryWorkspace.empty();
  LibraryKind? _kind;
  String _query = '';
  bool _loading = true;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({bool quietly = false}) async {
    if (!quietly && mounted) {
      setState(() {
        _loading = true;
        _failed = false;
      });
    }
    try {
      final workspace = await AppControllerScope.of(context).loadLibrary();
      if (!mounted) return;
      setState(() {
        _workspace = workspace;
        _loading = false;
        _failed = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _openResource(LibraryResource resource) async {
    if (resource.remoteFileId != null &&
        const {'pending', 'rejected'}.contains(resource.status)) {
      showPremiumToast(
        context,
        resource.status == 'pending'
            ? context.tr('resourceBeingPrepared')
            : (resource.rejectReason.isEmpty
                  ? context.tr('resourceUnavailable')
                  : resource.rejectReason),
        icon: resource.status == 'pending'
            ? Icons.hourglass_top_rounded
            : Icons.report_outlined,
        color: resource.status == 'pending' ? AppTheme.gold : AppTheme.coral,
      );
      return;
    }
    try {
      final ready = await AppControllerScope.of(
        context,
      ).prepareLibraryResource(resource);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => LibraryViewerPage(resource: ready)),
      );
    } catch (_) {
      if (!mounted) return;
      showPremiumToast(
        context,
        resource.status == 'pending'
            ? context.tr('resourceBeingPrepared')
            : context.tr('resourceUnavailable'),
        icon: Icons.auto_stories_outlined,
        color: AppTheme.gold,
      );
    }
  }

  void _showUpload() {
    if (_workspace.folders.isEmpty) {
      showPremiumToast(
        context,
        context.tr('noUploadLocation'),
        icon: Icons.folder_off_outlined,
        color: AppTheme.gold,
      );
      return;
    }
    final titleController = TextEditingController();
    String? filePath;
    String? fileName;
    String? contentType;
    var audience = 'own_students';
    var downloadable = true;
    List<LibraryFolder> eligibleFolders(String value) => _workspace.folders
        .where(
          (folder) => value == 'global'
              ? folder.visibility == 'tenant'
              : folder.visibility == 'cohort' && folder.cohortId != null,
        )
        .toList(growable: false);
    var selectableFolders = eligibleFolders(audience);
    if (selectableFolders.isEmpty) {
      selectableFolders = _workspace.folders;
      audience = '';
    }
    var folderId = selectableFolders.first.id;
    var uploading = false;
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            24,
            2,
            24,
            24 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('uploadResource'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 22),
                TextField(
                  controller: titleController,
                  onChanged: (_) => setSheetState(() {}),
                  decoration: InputDecoration(
                    labelText: context.tr('resourceTitle'),
                  ),
                ),
                const SizedBox(height: 13),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 56),
                  ),
                  onPressed: () async {
                    final result = await FilePicker.pickFiles(
                      type: FileType.custom,
                      allowedExtensions: libraryUploadExtensions,
                    );
                    if (result != null && result.files.single.path != null) {
                      final selected = result.files.single;
                      setSheetState(() {
                        filePath = selected.path;
                        fileName = selected.name;
                        contentType = libraryUploadContentType(selected.name);
                        if (titleController.text.trim().isEmpty) {
                          titleController.text = selected.name
                              .replaceFirst(RegExp(r'\.[^.]+$'), '')
                              .replaceAll('_', ' ');
                        }
                      });
                    }
                  },
                  icon: const Icon(Icons.upload_file_rounded),
                  label: Text(fileName ?? context.tr('chooseFile')),
                ),
                const SizedBox(height: 15),
                if (audience.isNotEmpty) ...[
                  Text(
                    context.tr('resourceAudience'),
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 8),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'own_students',
                        icon: const Icon(Icons.groups_outlined),
                        label: Text(context.tr('ownStudentsAudience')),
                      ),
                      ButtonSegment(
                        value: 'global',
                        icon: const Icon(Icons.public_outlined),
                        label: Text(context.tr('globalAudience')),
                      ),
                    ],
                    selected: {audience},
                    showSelectedIcon: false,
                    onSelectionChanged: uploading
                        ? null
                        : (value) {
                            final selectedAudience = value.first;
                            final folders = eligibleFolders(selectedAudience);
                            if (folders.isEmpty) {
                              showPremiumToast(
                                context,
                                context.tr('audienceLocationUnavailable'),
                                icon: Icons.folder_off_outlined,
                                color: AppTheme.gold,
                              );
                              return;
                            }
                            setSheetState(() {
                              audience = selectedAudience;
                              selectableFolders = folders;
                              folderId = folders.first.id;
                            });
                          },
                  ),
                  const SizedBox(height: 13),
                ],
                DropdownButtonFormField<int>(
                  initialValue: folderId,
                  decoration: InputDecoration(
                    labelText: context.tr('contentLocation'),
                    prefixIcon: const Icon(Icons.folder_outlined),
                  ),
                  items: selectableFolders
                      .map(
                        (folder) => DropdownMenuItem(
                          value: folder.id,
                          child: Text(
                            folder.displayPath,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: uploading
                      ? null
                      : (value) {
                          if (value != null) {
                            setSheetState(() => folderId = value);
                          }
                        },
                ),
                const SizedBox(height: 12),
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  secondary: Icon(
                    downloadable
                        ? Icons.download_outlined
                        : Icons.visibility_outlined,
                  ),
                  title: Text(context.tr('allowDownloads')),
                  subtitle: Text(
                    context.tr(
                      downloadable ? 'allowDownloadsBody' : 'viewOnlyBody',
                    ),
                  ),
                  value: downloadable,
                  onChanged: uploading
                      ? null
                      : (value) => setSheetState(() => downloadable = value),
                ),
                const SizedBox(height: 12),
                PremiumCard(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.verified_user_outlined,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 11),
                      Expanded(
                        child: Text(
                          context.tr('resourceReviewNote'),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        uploading ||
                            titleController.text.trim().isEmpty ||
                            filePath == null ||
                            contentType == null
                        ? null
                        : () async {
                            setSheetState(() => uploading = true);
                            try {
                              await AppControllerScope.of(
                                context,
                              ).uploadLibraryResource(
                                filePath: filePath!,
                                filename: normalizeLibraryUploadFilename(
                                  fileName!,
                                ),
                                contentType: contentType!,
                                title: titleController.text,
                                folderId: folderId,
                                audience: audience,
                                downloadable: downloadable,
                              );
                              if (!sheetContext.mounted) return;
                              Navigator.pop(sheetContext);
                              if (!mounted) return;
                              showPremiumToast(
                                context,
                                context.tr('uploadSubmitted'),
                                icon: Icons.cloud_done_outlined,
                              );
                              await _load(quietly: true);
                            } catch (_) {
                              if (!sheetContext.mounted) return;
                              setSheetState(() => uploading = false);
                              showPremiumToast(
                                context,
                                context.tr('uploadFailed'),
                                icon: Icons.error_outline_rounded,
                                color: AppTheme.coral,
                              );
                            }
                          },
                    icon: uploading
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.upload_rounded),
                    label: Text(
                      uploading
                          ? context.tr('uploading')
                          : context.tr('upload'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(titleController.dispose);
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final resources = _workspace.resources.where((resource) {
      final query = _query.toLowerCase().trim();
      return (_kind == null || resource.kind == _kind) &&
          (query.isEmpty ||
              resource.title.toLowerCase().contains(query) ||
              resource.author.toLowerCase().contains(query));
    }).toList();
    final canUpload =
        controller.account?.principalKind == 'teacher' &&
        controller.canMutate('content:write');
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    LibraryResource? featured;
    for (final resource in resources) {
      if (resource.isPublished &&
          (resource.kind == LibraryKind.video ||
              resource.kind == LibraryKind.podcast)) {
        featured = resource;
        break;
      }
    }
    return Scaffold(
      appBar: Navigator.of(context).canPop()
          ? AppBar(
              title: Text(context.tr('library')),
              actions: [
                if (canUpload)
                  IconButton(
                    tooltip: context.tr('upload'),
                    onPressed: _showUpload,
                    icon: const Icon(Icons.add_rounded),
                  ),
              ],
            )
          : null,
      floatingActionButton: canUpload
          ? FloatingActionButton.extended(
              heroTag: 'library-upload',
              onPressed: _showUpload,
              icon: const Icon(Icons.upload_rounded),
              label: Text(context.tr('upload')),
            )
          : null,
      body: SafeArea(
        top: false,
        child: RefreshIndicator(
          onRefresh: _load,
          child: CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            slivers: [
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 14),
                    child: PageIntro(
                      title: context.tr('library'),
                      subtitle: context.tr('librarySubtitle'),
                      trailing: canUpload && !Navigator.of(context).canPop()
                          ? IconButton.filledTonal(
                              tooltip: context.tr('upload'),
                              onPressed: _showUpload,
                              icon: const Icon(Icons.upload_rounded),
                            )
                          : null,
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 18),
                    child: TextField(
                      controller: _searchController,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: context.tr('searchLibrary'),
                        prefixIcon: const Icon(Icons.search_rounded),
                        suffixIcon: _query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: context.tr('clear'),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() => _query = '');
                                },
                                icon: const Icon(Icons.close_rounded),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: SizedBox(
                  height: 67 + 24 * (textScale.clamp(1.0, 2.5) - 1.0),
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: EdgeInsets.fromLTRB(
                      MediaQuery.sizeOf(context).width >= 1080
                          ? (MediaQuery.sizeOf(context).width - 1080) / 2 + 20
                          : 20,
                      13,
                      20,
                      12,
                    ),
                    children: [
                      _KindChip(
                        label: context.tr('all'),
                        icon: Icons.apps_rounded,
                        selected: _kind == null,
                        onSelected: () => setState(() => _kind = null),
                      ),
                      _KindChip(
                        label: context.tr('books'),
                        icon: Icons.menu_book_outlined,
                        selected: _kind == LibraryKind.book,
                        onSelected: () =>
                            setState(() => _kind = LibraryKind.book),
                      ),
                      _KindChip(
                        label: context.tr('podcasts'),
                        icon: Icons.podcasts_rounded,
                        selected: _kind == LibraryKind.podcast,
                        onSelected: () =>
                            setState(() => _kind = LibraryKind.podcast),
                      ),
                      _KindChip(
                        label: context.tr('videos'),
                        icon: Icons.play_circle_outline_rounded,
                        selected: _kind == LibraryKind.video,
                        onSelected: () =>
                            setState(() => _kind = LibraryKind.video),
                      ),
                    ],
                  ),
                ),
              ),
              if (!_loading &&
                  !_failed &&
                  resources.isNotEmpty &&
                  _kind == null &&
                  _query.isEmpty &&
                  featured != null) ...[
                SliverToBoxAdapter(
                  child: MaxWidthBox(
                    child: _FeaturedPlayer(
                      resource: featured,
                      onTap: () => _openResource(featured!),
                    ),
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 25)),
              ],
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  child: SectionHeader(
                    title: context.tr('recentlyAdded'),
                    subtitle: '${resources.length} ${context.tr('resources')}',
                  ),
                ),
              ),
              const SliverToBoxAdapter(child: SizedBox(height: 12)),
              if (_loading)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LibrarySkeleton(),
                )
              else if (_failed)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _LibraryLoadState(onRetry: () => _load()),
                )
              else if (resources.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: context.tr('emptyTitle'),
                    body: context.tr('emptyBody'),
                    icon: Icons.local_library_outlined,
                  ),
                )
              else
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(
                    MediaQuery.sizeOf(context).width >= 1080
                        ? (MediaQuery.sizeOf(context).width - 1080) / 2 + 20
                        : 20,
                    0,
                    MediaQuery.sizeOf(context).width >= 1080
                        ? (MediaQuery.sizeOf(context).width - 1080) / 2 + 20
                        : 20,
                    100,
                  ),
                  sliver: SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.crossAxisExtent >= 760
                          ? 2
                          : 1;
                      final cardExtent =
                          132 + 112 * (textScale.clamp(1.0, 2.5) - 1.0);
                      return SliverGrid(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: columns,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                          mainAxisExtent: cardExtent,
                        ),
                        delegate: SliverChildBuilderDelegate(
                          (context, index) => _ResourceCard(
                            resource: resources[index],
                            onTap: () => _openResource(resources[index]),
                          ),
                          childCount: resources.length,
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
  }
}

class _KindChip extends StatelessWidget {
  const _KindChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onSelected,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        selected: selected,
        onSelected: (_) => onSelected(),
        avatar: Icon(icon, size: 17),
        label: Text(label),
      ),
    );
  }
}

class _FeaturedPlayer extends StatelessWidget {
  const _FeaturedPlayer({required this.resource, required this.onTap});
  final LibraryResource resource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: resource.color,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 88,
            height: 88,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .15),
              borderRadius: BorderRadius.circular(22),
            ),
            child: Icon(resource.icon, color: Colors.white, size: 41),
          ),
          const SizedBox(width: 17),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('recentlyAdded').toUpperCase(),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white60,
                    letterSpacing: 1,
                  ),
                ),
                const SizedBox(height: 7),
                Text(
                  resource.title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: Colors.white),
                ),
                const SizedBox(height: 4),
                Text(
                  resource.subtitle,
                  style: Theme.of(
                    context,
                  ).textTheme.bodySmall?.copyWith(color: Colors.white70),
                ),
                const SizedBox(height: 13),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        resource.author.isEmpty
                            ? context.tr('starforgeLibrary')
                            : resource.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: Colors.white70),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Semantics(
                      button: true,
                      label: '${context.tr('openResource')}: ${resource.title}',
                      onTap: onTap,
                      excludeSemantics: true,
                      child: Tooltip(
                        message: context.tr('openResource'),
                        child: InkWell(
                          onTap: onTap,
                          customBorder: const CircleBorder(),
                          child: Container(
                            width: 48,
                            height: 48,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.play_arrow_rounded,
                              color: resource.color,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ResourceCard extends StatelessWidget {
  const _ResourceCard({required this.resource, required this.onTap});
  final LibraryResource resource;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final statusLabel = resource.status == 'pending'
        ? context.tr('pending')
        : resource.status == 'rejected'
        ? context.tr('rejected')
        : resource.status == 'draft'
        ? context.tr('draft')
        : resource.remoteFileId != null && resource.status == 'clean'
        ? !resource.teacherApproved
              ? context.tr('awaitingTeacherApproval')
              : !resource.managerApproved
              ? context.tr('awaitingPublication')
              : ''
        : '';
    final semanticLabel = [
      resource.title,
      resource.subtitle,
      resource.author,
      statusLabel,
    ].where((value) => value.isNotEmpty).join(', ');
    return Semantics(
      key: ValueKey('library-resource-${resource.id}'),
      button: true,
      label: semanticLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: PremiumCard(
        padding: const EdgeInsets.all(13),
        onTap: onTap,
        child: LayoutBuilder(
          builder: (context, constraints) => Row(
            children: [
              Container(
                width: constraints.maxWidth < 300 ? 64 : 76,
                height: double.infinity,
                decoration: BoxDecoration(
                  color: resource.color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(resource.icon, color: Colors.white, size: 31),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      resource.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 5),
                    Text(
                      resource.subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            resource.author.isEmpty
                                ? context.tr('starforgeLibrary')
                                : resource.author,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(color: resource.color),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (statusLabel.isNotEmpty) ...[
                          const SizedBox(width: 6),
                          Flexible(
                            flex: 2,
                            child: _ResourceStatus(
                              label: statusLabel,
                              color: resource.status == 'rejected'
                                  ? AppTheme.coral
                                  : AppTheme.gold,
                            ),
                          ),
                        ] else
                          Icon(
                            resource.downloadable
                                ? Icons.download_outlined
                                : Icons.shield_outlined,
                            size: 17,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResourceStatus extends StatelessWidget {
  const _ResourceStatus({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: color.withValues(alpha: .13),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Text(
        label,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.w800,
        ),
      ),
    ),
  );
}

class _LibrarySkeleton extends StatelessWidget {
  const _LibrarySkeleton();

  @override
  Widget build(BuildContext context) => MaxWidthBox(
    child: Column(
      children: List.generate(
        3,
        (index) => Container(
          height: 132,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: .58 - index * .08),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    ),
  );
}

class _MediaLoadingIndicator extends StatelessWidget {
  const _MediaLoadingIndicator();

  @override
  Widget build(BuildContext context) => Semantics(
    label: context.tr('resourceBeingPrepared'),
    child: Center(
      child: MediaQuery.disableAnimationsOf(context)
          ? Icon(
              Icons.hourglass_empty_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 32,
            )
          : const CircularProgressIndicator(),
    ),
  );
}

class _LibraryLoadState extends StatelessWidget {
  const _LibraryLoadState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: const EdgeInsets.all(28),
    child: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.local_library_outlined,
            size: 52,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('libraryLoadFailed'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('libraryLoadFailedBody'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('tryAgain')),
          ),
        ],
      ),
    ),
  );
}

class LibraryViewerPage extends StatefulWidget {
  const LibraryViewerPage({super.key, required this.resource});
  final LibraryResource resource;

  @override
  State<LibraryViewerPage> createState() => _LibraryViewerPageState();
}

class _LibraryViewerPageState extends State<LibraryViewerPage> {
  late LibraryResource _resource;
  VideoPlayerController? _videoPlayer;
  AudioPlayer? _audioPlayer;
  bool _mediaFailed = false;
  bool _approving = false;
  bool _protectionApplied = false;
  String _protectionLanguage = 'uz';

  @override
  void initState() {
    super.initState();
    _resource = widget.resource;
    _initializeMedia();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await AppControllerScope.of(context).trackLibraryResource(_resource);
      } catch (_) {
        // Analytics must never interrupt reading or playback.
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_resource.downloadable || _protectionApplied) return;
    _protectionApplied = true;
    _protectionLanguage = AppControllerScope.of(context).locale.languageCode;
    ContentProtection.setProtected(true, languageCode: _protectionLanguage);
  }

  Future<void> _initializeMedia() async {
    if (_resource.remoteUrl.isEmpty) return;
    if (_resource.contentType.startsWith('video/')) {
      final player = VideoPlayerController.networkUrl(
        Uri.parse(_resource.remoteUrl),
      );
      _videoPlayer = player;
      try {
        await player.initialize();
        if (mounted) setState(() {});
      } catch (_) {
        if (mounted) setState(() => _mediaFailed = true);
      }
    } else if (_resource.contentType.startsWith('audio/')) {
      final player = AudioPlayer();
      _audioPlayer = player;
      try {
        await player.setUrl(_resource.remoteUrl);
        if (mounted) setState(() {});
      } catch (_) {
        if (mounted) setState(() => _mediaFailed = true);
      }
    }
  }

  @override
  void dispose() {
    _videoPlayer?.dispose();
    _audioPlayer?.dispose();
    if (_protectionApplied) {
      ContentProtection.setProtected(false, languageCode: _protectionLanguage);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resource = _resource;
    final isBook = resource.kind == LibraryKind.book;
    final controller = AppControllerScope.of(context);
    final account = controller.account;
    final identity = [
      controller.displayName,
      if (account?.username.isNotEmpty == true) '@${account!.username}',
    ].join(' · ');
    return Scaffold(
      backgroundColor: isBook
          ? const Color(0xFF24242B)
          : Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: isBook ? const Color(0xFF24242B) : Colors.transparent,
        foregroundColor: isBook ? Colors.white : null,
        title: Text(resource.title),
        actions: [
          if (resource.remoteFileId != null &&
              resource.status == 'clean' &&
              !resource.teacherApproved &&
              AppControllerScope.of(context).canMutate('content:approve'))
            IconButton(
              tooltip: context.tr('approveResource'),
              onPressed: _approving ? null : _approveResource,
              icon: _approving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.verified_outlined),
            ),
          if (resource.downloadable)
            IconButton(
              tooltip: context.tr('openResource'),
              onPressed: resource.remoteUrl.isEmpty ? null : _openExternal,
              icon: const Icon(Icons.download_outlined),
            )
          else
            IconButton(
              tooltip: context.tr('protectedContent'),
              onPressed: () => showPremiumToast(
                context,
                context.tr('protectedContent'),
                icon: Icons.shield_outlined,
                color: AppTheme.gold,
              ),
              icon: const Icon(Icons.shield_outlined),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned.fill(
              child: isBook ? _buildBook(context) : _buildMedia(context),
            ),
            if (!resource.downloadable)
              Positioned.fill(
                child: _ProtectedWatermark(
                  label: context.l10n.format('protectedWatermark', {
                    'identity': identity,
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openExternal() async {
    final uri = Uri.tryParse(_resource.remoteUrl);
    if (uri == null ||
        !await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      showPremiumToast(
        context,
        context.tr('resourceUnavailable'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  Future<void> _approveResource() async {
    setState(() => _approving = true);
    try {
      final approved = await AppControllerScope.of(
        context,
      ).approveLibraryResource(_resource);
      if (!mounted) return;
      setState(() {
        _resource = approved;
        _approving = false;
      });
      showPremiumToast(
        context,
        context.tr('resourceApproved'),
        icon: Icons.verified_rounded,
        color: AppTheme.mint,
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _approving = false);
      showPremiumToast(
        context,
        context.tr('resourceApprovalFailed'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  Widget _buildBook(BuildContext context) {
    final resource = _resource;
    if (resource.body.isNotEmpty) {
      return SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 40),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 720),
            padding: const EdgeInsets.fromLTRB(30, 34, 30, 42),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F3E7),
              borderRadius: BorderRadius.circular(10),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 30,
                  offset: Offset(0, 14),
                ),
              ],
            ),
            child: SelectionArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    resource.author.isEmpty
                        ? context.tr('starforgeLibrary')
                        : resource.author,
                    style: const TextStyle(
                      color: Color(0xFFB85535),
                      fontWeight: FontWeight.w800,
                      letterSpacing: .6,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    resource.title,
                    style: const TextStyle(
                      color: Color(0xFF20202A),
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      height: 1.15,
                    ),
                  ),
                  if (resource.subtitle.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(
                      resource.subtitle,
                      style: const TextStyle(
                        color: Color(0xFF66616A),
                        fontSize: 14,
                      ),
                    ),
                  ],
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Divider(color: Color(0xFFD8D2C5)),
                  ),
                  Text(
                    resource.body,
                    style: const TextStyle(
                      color: Color(0xFF2A2930),
                      fontSize: 16,
                      height: 1.65,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (resource.contentType == 'application/pdf' &&
        resource.remoteUrl.isNotEmpty) {
      return PdfViewer.uri(
        Uri.parse(resource.remoteUrl),
        timeout: const Duration(seconds: 30),
      );
    }
    if (resource.contentType.startsWith('image/') &&
        resource.remoteUrl.isNotEmpty) {
      return InteractiveViewer(
        minScale: .8,
        maxScale: 4,
        child: Center(
          child: Image.network(
            resource.remoteUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) =>
                progress == null ? child : const _LibrarySkeleton(),
            errorBuilder: (_, _, _) => _resourcePanel(context),
          ),
        ),
      );
    }
    return _resourcePanel(context);
  }

  Widget _buildMedia(BuildContext context) {
    if (_mediaFailed) return _resourcePanel(context);
    final video = _videoPlayer;
    if (_resource.contentType.startsWith('video/')) {
      if (video == null || !video.value.isInitialized) {
        return const _MediaLoadingIndicator();
      }
      return Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(18),
          child: MaxWidthBox(
            maxWidth: 920,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: AspectRatio(
                    aspectRatio: video.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        VideoPlayer(video),
                        if (!video.value.isPlaying)
                          IconButton.filled(
                            tooltip: context.tr('openResource'),
                            onPressed: () {
                              video.play();
                              setState(() {});
                            },
                            iconSize: 38,
                            icon: const Icon(Icons.play_arrow_rounded),
                          ),
                        Align(
                          alignment: Alignment.bottomCenter,
                          child: VideoProgressIndicator(
                            video,
                            allowScrubbing: true,
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            colors: VideoProgressColors(
                              playedColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                              bufferedColor: Colors.white38,
                              backgroundColor: Colors.black26,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _resource.title,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: 10),
                IconButton.filledTonal(
                  tooltip: _resource.title,
                  onPressed: () {
                    video.value.isPlaying ? video.pause() : video.play();
                    setState(() {});
                  },
                  icon: Icon(
                    video.value.isPlaying
                        ? Icons.pause_rounded
                        : Icons.play_arrow_rounded,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    if (_resource.contentType.startsWith('audio/')) {
      final audio = _audioPlayer;
      if (audio == null) {
        return const _MediaLoadingIndicator();
      }
      return MaxWidthBox(
        maxWidth: 680,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: PremiumCard(
              padding: const EdgeInsets.fromLTRB(25, 32, 25, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 172,
                    height: 172,
                    decoration: BoxDecoration(
                      color: _resource.color,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Icon(
                      Icons.graphic_eq_rounded,
                      color: Colors.white,
                      size: 72,
                    ),
                  ),
                  const SizedBox(height: 27),
                  Text(
                    _resource.title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  if (_resource.author.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      _resource.author,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  StreamBuilder<Duration>(
                    stream: audio.positionStream,
                    builder: (context, positionSnapshot) =>
                        StreamBuilder<Duration?>(
                          stream: audio.durationStream,
                          builder: (context, durationSnapshot) {
                            final position =
                                positionSnapshot.data ?? Duration.zero;
                            final duration =
                                durationSnapshot.data ?? Duration.zero;
                            final max = duration.inMilliseconds > 0
                                ? duration.inMilliseconds.toDouble()
                                : 1.0;
                            return Column(
                              children: [
                                Slider(
                                  value: position.inMilliseconds
                                      .clamp(0, max.toInt())
                                      .toDouble(),
                                  max: max,
                                  onChanged: (value) => audio.seek(
                                    Duration(milliseconds: value.round()),
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_durationLabel(position)),
                                    Text(_durationLabel(duration)),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                  ),
                  const SizedBox(height: 10),
                  StreamBuilder<bool>(
                    stream: audio.playingStream,
                    builder: (context, snapshot) => IconButton.filled(
                      tooltip: _resource.title,
                      onPressed: () =>
                          snapshot.data == true ? audio.pause() : audio.play(),
                      iconSize: 36,
                      icon: Icon(
                        snapshot.data == true
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return _resourcePanel(context);
  }

  String _durationLabel(Duration value) {
    final seconds = value.inSeconds.clamp(0, 359999);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  Widget _resourcePanel(BuildContext context) {
    final resource = _resource;
    return MaxWidthBox(
      maxWidth: 700,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 210,
                height: 210,
                decoration: BoxDecoration(
                  color: resource.color,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Icon(resource.icon, color: Colors.white, size: 78),
              ),
              const SizedBox(height: 30),
              Text(
                resource.title,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
                textAlign: TextAlign.center,
              ),
              if (resource.subtitle.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  resource.subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 24),
              if (resource.remoteFileId != null &&
                  resource.status == 'clean' &&
                  !resource.teacherApproved &&
                  AppControllerScope.of(
                    context,
                  ).canMutate('content:approve')) ...[
                FilledButton.icon(
                  onPressed: _approving ? null : _approveResource,
                  icon: _approving
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.verified_outlined),
                  label: Text(context.tr('approveResource')),
                ),
                const SizedBox(height: 14),
              ],
              if (!resource.downloadable)
                StatusPill(
                  label: context.tr('protectedContent'),
                  color: AppTheme.gold,
                  icon: Icons.shield_outlined,
                )
              else if (resource.remoteUrl.isNotEmpty)
                FilledButton.icon(
                  onPressed: _openExternal,
                  icon: Icon(
                    resource.kind == LibraryKind.video
                        ? Icons.play_arrow_rounded
                        : Icons.open_in_new_rounded,
                  ),
                  label: Text(context.tr('openResource')),
                )
              else
                Text(
                  context.tr('resourceUnavailable'),
                  style: Theme.of(context).textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProtectedWatermark extends StatelessWidget {
  const _ProtectedWatermark({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: LayoutBuilder(
      builder: (context, constraints) {
        final rows = (constraints.maxHeight / 155).ceil().clamp(3, 8);
        final color = Theme.of(context).brightness == Brightness.dark
            ? Colors.white
            : Theme.of(context).colorScheme.onSurface;
        return ClipRect(
          child: Stack(
            children: [
              for (var row = 0; row < rows; row++)
                Positioned(
                  left: row.isEven ? -45 : 25,
                  top: row * (constraints.maxHeight / rows) + 30,
                  child: Transform.rotate(
                    angle: -.25,
                    child: SizedBox(
                      width: constraints.maxWidth + 110,
                      child: Text(
                        '$label     •     $label',
                        maxLines: 1,
                        overflow: TextOverflow.clip,
                        style: TextStyle(
                          color: color.withValues(alpha: .115),
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .4,
                        ),
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 12,
                bottom: 12,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surface.withValues(alpha: .88),
                    borderRadius: BorderRadius.circular(99),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).colorScheme.outlineVariant.withValues(alpha: .55),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          size: 15,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(width: 6),
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxWidth: constraints.maxWidth * .65,
                          ),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall
                                ?.copyWith(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

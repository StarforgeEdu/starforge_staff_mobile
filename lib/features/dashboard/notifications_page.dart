import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/remote_models.dart';

class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key});

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  List<NotificationInfo>? _items;
  Object? _error;
  bool _loading = false;
  bool _markingAll = false;
  DateTime? _lastUpdatedAt;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_items == null && !_loading) _load();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final result = await AppControllerScope.of(context).loadNotifications();
      if (mounted) {
        setState(() {
          _items = result;
          _lastUpdatedAt = DateTime.now();
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _markRead(NotificationInfo item) async {
    if (item.isRead) return;
    try {
      await AppControllerScope.of(context).markNotificationRead(item.id);
      if (!mounted) return;
      setState(() {
        _items = _items
            ?.map(
              (entry) => entry.id == item.id
                  ? entry.copyWith(readAt: DateTime.now())
                  : entry,
            )
            .toList(growable: false);
      });
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          context.tr('notificationReadSaveFailed'),
          icon: Icons.sync_problem_rounded,
          color: AppTheme.coral,
        );
      }
    }
  }

  void _openNotification(NotificationInfo item) {
    _showNotificationDetails(context, item);
    if (AppControllerScope.of(context).account?.readOnly != true) {
      _markRead(item);
    }
  }

  Future<void> _markAllRead() async {
    if (_markingAll) return;
    setState(() => _markingAll = true);
    try {
      await AppControllerScope.of(context).markAllNotificationsRead();
      if (!mounted) return;
      final now = DateTime.now();
      setState(() {
        _items = _items
            ?.map((item) => item.isRead ? item : item.copyWith(readAt: now))
            .toList(growable: false);
      });
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
      if (mounted) setState(() => _markingAll = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = _items?.any((item) => !item.isRead) == true;
    final canMarkRead =
        AppControllerScope.of(context).account?.readOnly != true;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('notifications')),
        actions: [
          if (hasUnread && canMarkRead)
            IconButton(
              tooltip: context.tr('markAllRead'),
              onPressed: _markingAll ? null : _markAllRead,
              icon: _markingAll
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.done_all_rounded),
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (_loading &&
                _items != null &&
                !MediaQuery.disableAnimationsOf(context))
              const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: RefreshIndicator.adaptive(
                onRefresh: _load,
                child: _body(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_items == null && _error == null) {
      return const _NotificationsSkeleton();
    }
    if (_error != null && _items == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .16),
          EmptyState(
            title: context.tr('notificationsLoadFailed'),
            body: context.tr('notificationsLoadFailedBody'),
            icon: Icons.notifications_paused_outlined,
            action: context.tr('tryAgain'),
            onAction: _load,
          ),
        ],
      );
    }
    final items = _items ?? const <NotificationInfo>[];
    if (items.isEmpty) {
      if (_error != null) {
        final horizontal = ((MediaQuery.sizeOf(context).width - 840) / 2).clamp(
          20.0,
          double.infinity,
        );
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
          children: [
            _StaleNotificationsNotice(
              updatedAt: _lastUpdatedAt,
              onRetry: _load,
            ),
          ],
        );
      }
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .16),
          EmptyState(
            title: context.tr('notificationsEmpty'),
            body: context.tr('notificationsEmptyBody'),
            icon: Icons.notifications_none_rounded,
          ),
        ],
      );
    }
    final hasStaleNotice = _error != null;
    final horizontal = ((MediaQuery.sizeOf(context).width - 840) / 2).clamp(
      20.0,
      double.infinity,
    );
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.fromLTRB(horizontal, 8, horizontal, 32),
      itemCount: items.length + (hasStaleNotice ? 1 : 0),
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (hasStaleNotice && index == 0) {
          return _StaleNotificationsNotice(
            updatedAt: _lastUpdatedAt,
            onRetry: _load,
          );
        }
        final item = items[index - (hasStaleNotice ? 1 : 0)];
        return _NotificationCard(
          item: item,
          onOpen: () => _openNotification(item),
        );
      },
    );
  }
}

class _NotificationCard extends StatelessWidget {
  const _NotificationCard({required this.item, required this.onOpen});

  final NotificationInfo item;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final color = _colorFor(item.eventType, theme);
    return Semantics(
      button: true,
      label: [
        if (!item.isRead) context.tr('unread'),
        item.title,
        item.body,
      ].where((value) => value.isNotEmpty).join('. '),
      child: PremiumCard(
        onTap: onOpen,
        padding: EdgeInsets.zero,
        color: item.isRead
            ? null
            : Color.alphaBlend(
                theme.colorScheme.primary.withValues(alpha: .07),
                theme.colorScheme.surface,
              ),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                width: 4,
                decoration: BoxDecoration(
                  color: item.isRead ? Colors.transparent : color,
                  borderRadius: const BorderRadiusDirectional.horizontal(
                    start: Radius.circular(24),
                  ),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(15, 16, 15, 16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: .13),
                          borderRadius: BorderRadius.circular(15),
                        ),
                        child: Icon(_iconFor(item.eventType), color: color),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.title.isEmpty
                                  ? context.tr('notifications')
                                  : item.title,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: item.isRead
                                    ? FontWeight.w600
                                    : FontWeight.w800,
                              ),
                            ),
                            if (item.body.isNotEmpty) ...[
                              const SizedBox(height: 5),
                              Text(
                                item.body,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyMedium,
                              ),
                            ],
                            const SizedBox(height: 8),
                            Text(
                              DateFormat.yMMMd(
                                locale,
                              ).add_Hm().format(item.createdAt.toLocal()),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.chevron_right_rounded,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
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

class _StaleNotificationsNotice extends StatelessWidget {
  const _StaleNotificationsNotice({
    required this.updatedAt,
    required this.onRetry,
  });

  final DateTime? updatedAt;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final updated = updatedAt == null
        ? ''
        : DateFormat.yMMMd(locale).add_Hm().format(updatedAt!.toLocal());
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.gold.withValues(alpha: .09),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.gold.withValues(alpha: .2)),
      ),
      child: Row(
        children: [
          const Icon(Icons.sync_problem_rounded, color: Color(0xFF9A641C)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('notificationsStale'),
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                if (updated.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    context.l10n.format('lastUpdatedAt', {'time': updated}),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
          IconButton(
            tooltip: context.tr('tryAgain'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}

class _NotificationsSkeleton extends StatelessWidget {
  const _NotificationsSkeleton();

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontal = ((width - 840) / 2).clamp(20.0, double.infinity);
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: EdgeInsets.fromLTRB(horizontal, 10, horizontal, 32),
      itemCount: 5,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => ExcludeSemantics(
        child: Container(
          height: 106,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

Future<void> _showNotificationDetails(
  BuildContext context,
  NotificationInfo item,
) async {
  final theme = Theme.of(context);
  final locale = Localizations.localeOf(context).toLanguageTag();
  final color = _colorFor(item.eventType, theme);
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    builder: (sheetContext) => Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 680),
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            4,
            24,
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: .13),
                      borderRadius: BorderRadius.circular(15),
                    ),
                    child: Icon(_iconFor(item.eventType), color: color),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _labelFor(item.eventType, sheetContext),
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: color,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          DateFormat.yMMMMd(
                            locale,
                          ).add_Hm().format(item.createdAt.toLocal()),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Text(
                item.title.isEmpty
                    ? sheetContext.tr('notifications')
                    : item.title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              if (item.body.isNotEmpty) ...[
                const SizedBox(height: 12),
                SelectableText(
                  item.body,
                  style: theme.textTheme.bodyLarge?.copyWith(height: 1.55),
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(sheetContext).pop(),
                  child: Text(sheetContext.tr('close')),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

String _labelFor(String eventType, BuildContext context) {
  final value = eventType.toLowerCase();
  if (value.contains('attendance')) return context.tr('attendance');
  if (value.contains('assignment') || value.contains('task')) {
    return context.tr('tasks');
  }
  if (value.contains('message')) return context.tr('messages');
  if (value.contains('meeting')) return context.tr('meeting');
  if (value.contains('content') || value.contains('report')) {
    return context.tr('library');
  }
  return context.tr('notifications');
}

IconData _iconFor(String eventType) {
  final value = eventType.toLowerCase();
  if (value.contains('attendance')) return Icons.fact_check_outlined;
  if (value.contains('task')) return Icons.task_alt_outlined;
  if (value.contains('message')) return Icons.forum_outlined;
  if (value.contains('meeting')) return Icons.groups_outlined;
  if (value.contains('content')) return Icons.library_books_outlined;
  return Icons.notifications_outlined;
}

Color _colorFor(String eventType, ThemeData theme) {
  final value = eventType.toLowerCase();
  if (value.contains('attendance')) return const Color(0xFF217563);
  if (value.contains('meeting')) return const Color(0xFF9A641C);
  if (value.contains('message')) return const Color(0xFF365F9E);
  return theme.colorScheme.primary;
}

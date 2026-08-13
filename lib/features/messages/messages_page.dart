import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import 'conversation_page.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final _searchController = TextEditingController();
  MessagingWorkspace _workspace = const MessagingWorkspace.empty();
  bool _showArchived = false;
  bool _loading = true;
  bool _failed = false;
  String _query = '';

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
      final workspace = await AppControllerScope.of(
        context,
      ).loadMessagingWorkspace();
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

  Future<void> _open(ChatContact contact) async {
    try {
      final resolved = await AppControllerScope.of(
        context,
      ).prepareConversation(contact);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ConversationPage(contact: resolved)),
      );
      if (mounted) await _load(quietly: true);
    } catch (_) {
      if (!mounted) return;
      showPremiumToast(
        context,
        context.tr('conversationUnavailable'),
        icon: Icons.forum_outlined,
      );
    }
  }

  void _newConversation() {
    var studentsOnly = true;
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) {
          final contacts = _workspace.contacts
              .where(
                (contact) =>
                    studentsOnly ? contact.isStudent : !contact.isStudent,
              )
              .toList();
          return SizedBox(
            height: MediaQuery.sizeOf(context).height * .72,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 15),
                  child: Text(
                    context.tr('newConversation'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<bool>(
                      segments: [
                        ButtonSegment(
                          value: true,
                          label: Text(context.tr('students')),
                          icon: const Icon(Icons.school_outlined),
                        ),
                        ButtonSegment(
                          value: false,
                          label: Text(context.tr('staff')),
                          icon: const Icon(Icons.badge_outlined),
                        ),
                      ],
                      selected: {studentsOnly},
                      showSelectedIcon: false,
                      onSelectionChanged: (value) =>
                          setSheetState(() => studentsOnly = value.first),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: contacts.isEmpty
                      ? EmptyState(
                          title: context.tr('noContacts'),
                          body: context.tr('noContactsBody'),
                          icon: studentsOnly
                              ? Icons.school_outlined
                              : Icons.badge_outlined,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 26),
                          itemCount: contacts.length,
                          separatorBuilder: (_, _) => const Divider(indent: 70),
                          itemBuilder: (context, index) {
                            final contact = contacts[index];
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              leading: PersonAvatar(name: contact.name),
                              title: Text(
                                contact.name,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(contact.role),
                              trailing: const Icon(Icons.chevron_right_rounded),
                              onTap: () {
                                Navigator.pop(sheetContext);
                                _open(contact);
                              },
                            );
                          },
                        ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final contacts = _workspace.threads.where((contact) {
      final isArchived = controller.isMessageThreadArchived(contact.threadId);
      final matchesFolder = _showArchived ? isArchived : !isArchived;
      final query = _query.toLowerCase().trim();
      return matchesFolder &&
          (query.isEmpty ||
              contact.name.toLowerCase().contains(query) ||
              contact.preview.toLowerCase().contains(query));
    }).toList();
    return Scaffold(
      floatingActionButton: controller.canMutate('messaging:write')
          ? FloatingActionButton(
              heroTag: 'messages-compose',
              tooltip: context.tr('newConversation'),
              onPressed: _newConversation,
              child: const Icon(Icons.edit_square),
            )
          : null,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            MaxWidthBox(
              maxWidth: 850,
              child: Padding(
                padding: const EdgeInsets.only(top: 22),
                child: PageIntro(
                  title: context.tr('messages'),
                  subtitle: context.trCount(
                    'unreadCount',
                    _workspace.threads.fold<int>(
                      0,
                      (sum, contact) => sum + contact.unread,
                    ),
                  ),
                  trailing: IconButton.filledTonal(
                    tooltip: context.tr(
                      controller.canMutate('messaging:write')
                          ? 'newConversation'
                          : 'refresh',
                    ),
                    onPressed: controller.canMutate('messaging:write')
                        ? _newConversation
                        : () => _load(),
                    icon: Icon(
                      controller.canMutate('messaging:write')
                          ? Icons.edit_rounded
                          : Icons.refresh_rounded,
                    ),
                  ),
                ),
              ),
            ),
            MaxWidthBox(
              maxWidth: 850,
              child: Padding(
                padding: const EdgeInsets.only(top: 18),
                child: TextField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                  decoration: InputDecoration(
                    hintText: context.tr('searchMessages'),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _query.isEmpty
                        ? null
                        : IconButton(
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
            MaxWidthBox(
              maxWidth: 850,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Row(
                  children: [
                    ChoiceChip(
                      label: Text(context.tr('inbox')),
                      avatar: const Icon(Icons.inbox_outlined, size: 17),
                      selected: !_showArchived,
                      onSelected: (_) => setState(() => _showArchived = false),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: Text(context.tr('archived')),
                      avatar: const Icon(Icons.archive_outlined, size: 17),
                      selected: _showArchived,
                      onSelected: (_) => setState(() => _showArchived = true),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: _loading
                  ? const _MessagesSkeleton()
                  : _failed
                  ? _MessageLoadState(onRetry: () => _load())
                  : contacts.isEmpty
                  ? EmptyState(
                      title: _showArchived
                          ? context.tr('emptyTitle')
                          : context.tr('noConversations'),
                      body: _showArchived
                          ? context.tr('emptyBody')
                          : context.tr('noConversationsBody'),
                      icon: _showArchived
                          ? Icons.archive_outlined
                          : Icons.forum_outlined,
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.separated(
                        key: ValueKey(_showArchived),
                        physics: const AlwaysScrollableScrollPhysics(
                          parent: BouncingScrollPhysics(),
                        ),
                        padding: EdgeInsets.fromLTRB(
                          MediaQuery.sizeOf(context).width >= 850
                              ? (MediaQuery.sizeOf(context).width - 850) / 2 +
                                    20
                              : 20,
                          0,
                          MediaQuery.sizeOf(context).width >= 850
                              ? (MediaQuery.sizeOf(context).width - 850) / 2 +
                                    20
                              : 20,
                          100,
                        ),
                        itemCount: contacts.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 6),
                        itemBuilder: (context, index) {
                          final contact = contacts[index];
                          return Dismissible(
                            key: ValueKey('${contact.id}-$_showArchived'),
                            direction: DismissDirection.endToStart,
                            confirmDismiss: (_) async {
                              final threadId = contact.threadId;
                              if (threadId == null) return false;
                              final wasArchived = _showArchived;
                              final toastLabel = wasArchived
                                  ? context.tr('inbox')
                                  : context.tr('archived');
                              final toastIcon = wasArchived
                                  ? Icons.unarchive_outlined
                                  : Icons.archive_outlined;
                              await controller.setMessageThreadArchived(
                                threadId,
                                !wasArchived,
                              );
                              if (!context.mounted) return false;
                              setState(() {});
                              showPremiumToast(
                                context,
                                toastLabel,
                                icon: toastIcon,
                              );
                              return false;
                            },
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 24),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary,
                                borderRadius: BorderRadius.circular(22),
                              ),
                              child: Icon(
                                _showArchived
                                    ? Icons.unarchive_rounded
                                    : Icons.archive_rounded,
                                color: Colors.white,
                              ),
                            ),
                            child: _ConversationTile(
                              contact: contact,
                              onTap: () => _open(contact),
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({required this.contact, required this.onTap});
  final ChatContact contact;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final name = contact.name.isEmpty
        ? context.tr('conversation')
        : contact.name;
    final preview = contact.preview.isNotEmpty
        ? contact.preview
        : contact.role.isNotEmpty
        ? contact.role
        : context.tr('openConversation');
    return PremiumCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      onTap: onTap,
      child: Row(
        children: [
          PersonAvatar(name: name, size: 52),
          const SizedBox(width: 13),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: contact.unread > 0
                              ? FontWeight.w800
                              : FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      contact.time,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: contact.unread > 0
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                          fontWeight: contact.unread > 0
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                    if (contact.unread > 0) ...[
                      const SizedBox(width: 8),
                      Container(
                        constraints: const BoxConstraints(
                          minWidth: 21,
                          minHeight: 21,
                        ),
                        alignment: Alignment.center,
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(99),
                        ),
                        child: Text(
                          '${contact.unread}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
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

class _MessagesSkeleton extends StatelessWidget {
  const _MessagesSkeleton();

  @override
  Widget build(BuildContext context) => MaxWidthBox(
    maxWidth: 850,
    child: Column(
      children: List.generate(
        4,
        (index) => Container(
          height: 82,
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest
                .withValues(alpha: .58 - index * .06),
            borderRadius: BorderRadius.circular(22),
          ),
        ),
      ),
    ),
  );
}

class _MessageLoadState extends StatelessWidget {
  const _MessageLoadState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 74,
            height: 74,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.forum_outlined,
              size: 31,
              color: Theme.of(context).colorScheme.primary,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            context.tr('messagesLoadFailed'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('messagesLoadFailedBody'),
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

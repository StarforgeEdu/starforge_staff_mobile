import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/remote_models.dart';

class MeetingsPage extends StatefulWidget {
  const MeetingsPage({super.key});

  @override
  State<MeetingsPage> createState() => _MeetingsPageState();
}

class _MeetingsPageState extends State<MeetingsPage> {
  List<MeetingInfo>? _items;
  Object? _error;
  bool _loading = false;
  int? _respondingId;

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
      final meetings = await AppControllerScope.of(
        context,
      ).loadUpcomingMeetings();
      meetings.sort((left, right) => left.startsAt.compareTo(right.startsAt));
      if (mounted) setState(() => _items = meetings);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _respond(MeetingInfo meeting, String response) async {
    if (_respondingId != null) return;
    setState(() => _respondingId = meeting.id);
    try {
      final updated = await AppControllerScope.of(
        context,
      ).respondToMeeting(meeting.id, response);
      if (!mounted) return;
      setState(() {
        _items = _items
            ?.map((item) => item.id == updated.id ? updated : item)
            .toList(growable: false);
      });
      showPremiumToast(context, context.tr('meetingResponseSaved'));
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          context.tr('meetingResponseFailed'),
          icon: Icons.error_outline_rounded,
          color: AppTheme.coral,
        );
      }
    } finally {
      if (mounted) setState(() => _respondingId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(context.tr('meetingsTitle'))),
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
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .28),
          StarforgeLoader(label: context.tr('meetingsTitle')),
        ],
      );
    }
    if (_items == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .16),
          EmptyState(
            title: context.tr('meetingsLoadFailed'),
            body: context.tr('emptyBody'),
            icon: Icons.event_busy_outlined,
            action: context.tr('tryAgain'),
            onAction: _load,
          ),
        ],
      );
    }
    final meetings = _items ?? const <MeetingInfo>[];
    if (meetings.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(height: MediaQuery.sizeOf(context).height * .16),
          EmptyState(
            title: context.tr('meetingsEmpty'),
            body: context.tr('meetingsEmptyBody'),
            icon: Icons.event_available_outlined,
          ),
        ],
      );
    }
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 32),
      itemCount: meetings.length + 1,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        if (index == 0) {
          return MaxWidthBox(
            maxWidth: 840,
            padding: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: PageIntro(
                title: context.tr('meetingsTitle'),
                subtitle: context.tr('meetingsSubtitle'),
              ),
            ),
          );
        }
        return MaxWidthBox(
          maxWidth: 840,
          padding: EdgeInsets.zero,
          child: _MeetingCard(
            meeting: meetings[index - 1],
            responding: _respondingId == meetings[index - 1].id,
            onRespond: (response) => _respond(meetings[index - 1], response),
          ),
        );
      },
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({
    required this.meeting,
    required this.responding,
    required this.onRespond,
  });

  final MeetingInfo meeting;
  final bool responding;
  final ValueChanged<String> onRespond;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    final starts = meeting.startsAt.toLocal();
    final ends = meeting.endsAt.toLocal();
    final soon =
        starts.isAfter(DateTime.now()) &&
        starts.difference(DateTime.now()) <= const Duration(hours: 24);
    final accent = soon ? AppTheme.gold : Theme.of(context).colorScheme.primary;
    final dateLabel = DateFormat.MMM(locale).format(starts).toUpperCase();
    final timeLabel =
        '${DateFormat.Hm(locale).format(starts)}–${DateFormat.Hm(locale).format(ends)}';
    final scope = [
      meeting.location,
      meeting.branchName,
    ].where((value) => value.isNotEmpty).join(' · ');
    final responseLabel = switch (meeting.response) {
      'accepted' => context.tr('meetingAccepted'),
      'declined' => context.tr('meetingDeclined'),
      _ => context.tr('meetingPending'),
    };
    final responseColor = switch (meeting.response) {
      'accepted' => AppTheme.mint,
      'declined' => AppTheme.coral,
      _ => AppTheme.gold,
    };
    final canRespond =
        meeting.status == 'scheduled' && meeting.response == 'pending';
    return PremiumCard(
      color: soon
          ? Color.alphaBlend(
              accent.withValues(alpha: .06),
              Theme.of(context).colorScheme.surface,
            )
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 54,
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                Text(
                  dateLabel,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: accent,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  '${starts.day}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(color: accent),
                ),
              ],
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        meeting.title.isEmpty
                            ? context.tr('meeting')
                            : meeting.title,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (meeting.status.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      StatusPill(label: meeting.status, color: accent),
                    ],
                  ],
                ),
                const SizedBox(height: 5),
                Text(
                  [
                    timeLabel,
                    scope,
                  ].where((value) => value.isNotEmpty).join(' · '),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (meeting.agenda.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    meeting.agenda,
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StatusPill(
                      label: responseLabel,
                      color: responseColor,
                      icon: meeting.response == 'accepted'
                          ? Icons.check_rounded
                          : meeting.response == 'declined'
                          ? Icons.close_rounded
                          : Icons.schedule_rounded,
                    ),
                    if (canRespond)
                      OutlinedButton(
                        onPressed: responding
                            ? null
                            : () => onRespond('declined'),
                        child: Text(context.tr('declineMeeting')),
                      ),
                    if (canRespond)
                      FilledButton(
                        onPressed: responding
                            ? null
                            : () => onRespond('accepted'),
                        child: responding
                            ? const SizedBox.square(
                                dimension: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(context.tr('acceptMeeting')),
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

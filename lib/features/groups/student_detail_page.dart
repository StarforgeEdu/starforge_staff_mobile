import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../data/remote_models.dart';
import '../messages/conversation_page.dart';
import 'branch_transfer_sheet.dart';
import 'group_detail_page.dart';

String _knownValue(String value) => value.trim().isEmpty ? '—' : value;

class StudentDetailPage extends StatelessWidget {
  const StudentDetailPage({
    super.key,
    required this.student,
    required this.group,
  });

  final Student student;
  final LearningGroup group;

  Future<void> _call(BuildContext context) async {
    final number = student.phone.replaceAll(' ', '');
    final uri = Uri(scheme: 'tel', path: number);
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        showPremiumToast(
          context,
          '${context.tr('phone')}: ${student.phone}',
          icon: Icons.phone_outlined,
        );
      }
    }
  }

  Future<void> _message(BuildContext context) async {
    try {
      final contact = await AppControllerScope.of(context).prepareConversation(
        ChatContact(
          id: student.id,
          name: student.name,
          role: '${context.tr('students')} · ${group.name}',
          preview: '',
          time: '',
          isStudent: true,
          profileId: int.tryParse(student.id),
          principalKind: 'student',
        ),
      );
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ConversationPage(contact: contact)),
      );
    } catch (_) {
      if (!context.mounted) return;
      showPremiumToast(
        context,
        context.tr('conversationUnavailable'),
        icon: Icons.forum_outlined,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppControllerScope.of(context);
    final canRequest = controller.canMutate('approvals:write');
    final canTransfer =
        controller.canTransferBranches && group.branchId != null;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('viewProfile')),
        actions: canRequest || canTransfer
            ? [
                if (canTransfer)
                  IconButton(
                    tooltip: context.tr('moveStudentBranch'),
                    onPressed: () async {
                      final moved = await showStudentBranchTransferSheet(
                        context,
                        student: student,
                        group: group,
                      );
                      if (moved && context.mounted) {
                        Navigator.of(context).pop(true);
                      }
                    },
                    icon: const Icon(Icons.compare_arrows_rounded),
                  ),
                if (canRequest)
                  IconButton(
                    tooltip: context.tr('requestAction'),
                    onPressed: () => showStudentRequestSheet(
                      context,
                      group: group,
                      student: student,
                    ),
                    icon: const Icon(Icons.more_horiz_rounded),
                  ),
              ]
            : null,
      ),
      body: SafeArea(
        top: false,
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 34),
          child: MaxWidthBox(
            maxWidth: 760,
            child: Column(
              children: [
                PremiumCard(
                  child: Column(
                    children: [
                      PersonAvatar(name: student.name, size: 86),
                      const SizedBox(height: 16),
                      Text(
                        student.name,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '${group.name} · ${group.level}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 20),
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final compact =
                              MediaQuery.textScalerOf(context).scale(1) >= 1.5;
                          final message = FilledButton.tonalIcon(
                            onPressed:
                                AppControllerScope.of(
                                  context,
                                ).canMutate('messaging:write')
                                ? () => _message(context)
                                : null,
                            icon: const Icon(Icons.chat_bubble_outline_rounded),
                            label: Text(context.tr('message')),
                          );
                          final call = OutlinedButton.icon(
                            onPressed: student.phone.trim().isEmpty
                                ? null
                                : () => _call(context),
                            icon: const Icon(Icons.phone_outlined),
                            label: Text(context.tr('call')),
                          );
                          if (compact) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                message,
                                const SizedBox(height: 10),
                                call,
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: message),
                              const SizedBox(width: 10),
                              Expanded(child: call),
                            ],
                          );
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = (constraints.maxWidth - 10) / 2;
                    return Row(
                      children: [
                        SizedBox(
                          width: width,
                          child: MetricTile(
                            value: student.attendance == null
                                ? '—'
                                : '${(student.attendance! * 100).round()}%',
                            label: context.tr('attendance'),
                            icon: Icons.fact_check_outlined,
                            color: AppTheme.mint,
                          ),
                        ),
                        const SizedBox(width: 10),
                        SizedBox(
                          width: width,
                          child: MetricTile(
                            value: student.lastExam == null
                                ? '—'
                                : student.lastExam!.toStringAsFixed(
                                    student.lastExam! % 1 == 0 ? 0 : 1,
                                  ),
                            label: context.tr('examHistory'),
                            icon: Icons.workspace_premium_outlined,
                            color: AppTheme.gold,
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('viewProfile'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 11),
                PremiumCard(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Column(
                    children: [
                      _DetailRow(
                        icon: Icons.phone_outlined,
                        label: context.tr('phone'),
                        value: _knownValue(student.phone),
                      ),
                      _DetailRow(
                        icon: Icons.cake_outlined,
                        label: context.tr('dateOfBirth'),
                        value: _knownValue(student.birthDate),
                      ),
                      _DetailRow(
                        icon: Icons.calendar_today_outlined,
                        label: context.tr('joined'),
                        value: _knownValue(student.joinedDate),
                      ),
                      _DetailRow(
                        icon: Icons.mail_outline_rounded,
                        label: context.tr('email'),
                        value: _knownValue(student.email),
                      ),
                      _DetailRow(
                        icon: Icons.school_outlined,
                        label: context.tr('academicLevel'),
                        value: _knownValue(student.academicLevel),
                        showDivider: false,
                      ),
                    ],
                  ),
                ),
                _StudentLeadershipPanel(student: student),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    context.tr('notes'),
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                const SizedBox(height: 11),
                PremiumCard(
                  color: theme.colorScheme.surfaceContainerHighest.withValues(
                    alpha: .42,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.notes_outlined,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          context.tr('studentNotesUnavailable'),
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed:
                        AppControllerScope.of(
                          context,
                        ).canMutate('approvals:write')
                        ? () => showStudentRequestSheet(
                            context,
                            group: group,
                            student: student,
                          )
                        : null,
                    icon: const Icon(Icons.outbox_outlined),
                    label: Text(context.tr('requestAction')),
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

class _StudentLeadershipPanel extends StatefulWidget {
  const _StudentLeadershipPanel({required this.student});

  final Student student;

  @override
  State<_StudentLeadershipPanel> createState() =>
      _StudentLeadershipPanelState();
}

class _StudentLeadershipPanelState extends State<_StudentLeadershipPanel> {
  Future<StudentLeadershipInfo?>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppControllerScope.of(
      context,
    ).loadStudentLeadership(widget.student);
  }

  void _retry() {
    setState(() {
      _future = AppControllerScope.of(
        context,
      ).loadStudentLeadership(widget.student);
    });
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<StudentLeadershipInfo?>(
    future: _future,
    builder: (context, snapshot) {
      if (snapshot.connectionState == ConnectionState.waiting) {
        return const Padding(
          padding: EdgeInsets.only(top: 14),
          child: _LeadershipSkeleton(),
        );
      }
      if (snapshot.hasError) {
        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: PremiumCard(
            child: Row(
              children: [
                Icon(
                  Icons.wb_sunny_outlined,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(context.tr('groupDetailsNeedMoment'))),
                TextButton(
                  onPressed: _retry,
                  child: Text(context.tr('tryAgain')),
                ),
              ],
            ),
          ),
        );
      }
      final info = snapshot.data;
      if (info == null) return const SizedBox.shrink();
      return _LeadershipContent(info: info);
    },
  );
}

class _LeadershipContent extends StatelessWidget {
  const _LeadershipContent({required this.info});

  final StudentLeadershipInfo info;

  @override
  Widget build(BuildContext context) {
    final identityRows = [
      (Icons.location_on_outlined, context.tr('location'), info.location),
      (
        Icons.account_balance_outlined,
        context.tr('previousSchool'),
        info.previousSchool,
      ),
    ].where((row) => row.$3.trim().isNotEmpty).toList(growable: false);
    return Column(
      children: [
        if (identityRows.isNotEmpty) ...[
          const SizedBox(height: 24),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Text(
              context.tr('studentOverview'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: 11),
          PremiumCard(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Column(
              children: [
                for (var index = 0; index < identityRows.length; index++)
                  _DetailRow(
                    icon: identityRows[index].$1,
                    label: identityRows[index].$2,
                    value: identityRows[index].$3,
                    showDivider: index < identityRows.length - 1,
                  ),
              ],
            ),
          ),
        ],
        if (info.attendance != null) ...[
          const SizedBox(height: 24),
          _LeadershipAttendance(attendance: info.attendance!),
        ],
        if (info.assignments != null) ...[
          const SizedBox(height: 24),
          _LeadershipAssignments(assignments: info.assignments!),
        ],
        if (info.learningAvailable && info.recentExams.isNotEmpty) ...[
          const SizedBox(height: 24),
          _RecentExamResults(results: info.recentExams),
        ],
        if (info.familyAvailable) ...[
          const SizedBox(height: 24),
          _FamilyContacts(guardians: info.guardians),
        ],
      ],
    );
  }
}

class _LeadershipAttendance extends StatelessWidget {
  const _LeadershipAttendance({required this.attendance});

  final StudentLeadershipAttendanceInfo attendance;

  @override
  Widget build(BuildContext context) {
    final metrics = [
      (context.tr('present'), attendance.present, AppTheme.mint),
      (context.tr('late'), attendance.late, AppTheme.gold),
      (context.tr('absent'), attendance.absent, AppTheme.coral),
      (
        context.tr('excused'),
        attendance.excused,
        Theme.of(context).colorScheme.primary,
      ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                context.tr('attendanceSummary'),
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            StatusPill(
              label: attendance.rate == null
                  ? '—'
                  : '${(attendance.rate! * 100).round()}%',
              color: AppTheme.mint,
            ),
          ],
        ),
        const SizedBox(height: 11),
        LayoutBuilder(
          builder: (context, constraints) {
            final scale = MediaQuery.textScalerOf(context).scale(1);
            final columns = scale >= 1.6
                ? 1
                : constraints.maxWidth >= 600
                ? 4
                : 2;
            final width = (constraints.maxWidth - 9 * (columns - 1)) / columns;
            return Wrap(
              spacing: 9,
              runSpacing: 9,
              children: metrics
                  .map(
                    (metric) => SizedBox(
                      width: width,
                      child: MetricTile(
                        value: '${metric.$2}',
                        label: metric.$1,
                        icon: Icons.circle,
                        color: metric.$3,
                      ),
                    ),
                  )
                  .toList(growable: false),
            );
          },
        ),
      ],
    );
  }
}

class _LeadershipAssignments extends StatelessWidget {
  const _LeadershipAssignments({required this.assignments});

  final StudentLeadershipAssignmentInfo assignments;

  @override
  Widget build(BuildContext context) {
    final values = [
      (context.tr('assigned'), assignments.assigned),
      (context.tr('completed'), assignments.completed),
      (context.tr('open'), assignments.open),
      (context.tr('late'), assignments.late),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: context.tr('assignmentsSummary')),
        const SizedBox(height: 11),
        PremiumCard(
          child: Wrap(
            spacing: 9,
            runSpacing: 9,
            children: values
                .map(
                  (item) => Chip(
                    avatar: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Text('${item.$2}'),
                    ),
                    label: Text(item.$1),
                  ),
                )
                .toList(growable: false),
          ),
        ),
      ],
    );
  }
}

class _RecentExamResults extends StatelessWidget {
  const _RecentExamResults({required this.results});

  final List<StudentLeadershipExamInfo> results;

  @override
  Widget build(BuildContext context) {
    final locale = AppControllerScope.of(context).locale.languageCode;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(title: context.tr('recentResults')),
        const SizedBox(height: 11),
        PremiumCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var index = 0; index < results.length; index++) ...[
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(13),
                        ),
                        child: Icon(
                          Icons.workspace_premium_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              results[index].title.isEmpty
                                  ? context.tr('examHistory')
                                  : results[index].title,
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 3),
                            Text(
                              [
                                results[index].subject,
                                if (results[index].date != null)
                                  DateFormat.yMMMd(
                                    locale,
                                  ).format(results[index].date!.toLocal()),
                              ].where((value) => value.isNotEmpty).join(' · '),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${results[index].score.toStringAsFixed(1)} / ${results[index].maximum.toStringAsFixed(1)}',
                              style: Theme.of(context).textTheme.labelLarge
                                  ?.copyWith(
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.primary,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                if (index < results.length - 1) const Divider(indent: 64),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _FamilyContacts extends StatelessWidget {
  const _FamilyContacts({required this.guardians});

  final List<StudentGuardianInfo> guardians;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      SectionHeader(title: context.tr('familyContacts')),
      const SizedBox(height: 11),
      PremiumCard(
        padding: guardians.isEmpty ? const EdgeInsets.all(18) : EdgeInsets.zero,
        child: guardians.isEmpty
            ? Row(
                children: [
                  Icon(
                    Icons.family_restroom_rounded,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(context.tr('noFamilyContacts'))),
                ],
              )
            : Column(
                children: [
                  for (var index = 0; index < guardians.length; index++) ...[
                    ListTile(
                      leading: PersonAvatar(name: guardians[index].name),
                      title: Text(guardians[index].name),
                      subtitle: Text(
                        [
                          guardians[index].relationship,
                          guardians[index].phone,
                          guardians[index].email,
                        ].where((value) => value.isNotEmpty).join(' · '),
                      ),
                    ),
                    if (index < guardians.length - 1) const Divider(indent: 64),
                  ],
                ],
              ),
      ),
    ],
  );
}

class _LeadershipSkeleton extends StatelessWidget {
  const _LeadershipSkeleton();

  @override
  Widget build(BuildContext context) => Column(
    children: List.generate(
      2,
      (index) => Container(
        height: 82,
        margin: EdgeInsets.only(bottom: index == 0 ? 9 : 0),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest
              .withValues(alpha: .5 - index * .08),
          borderRadius: BorderRadius.circular(20),
        ),
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.showDivider = true,
  });

  final IconData icon;
  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          child: Row(
            children: [
              Icon(
                icon,
                size: 19,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              Flexible(
                child: Text(
                  value,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
        if (showDivider) const Divider(indent: 46, endIndent: 16),
      ],
    );
  }
}

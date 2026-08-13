import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_widgets.dart';
import '../../data/workflow_models.dart';
import 'student_detail_page.dart';

class AssignedStudentsPage extends StatefulWidget {
  const AssignedStudentsPage({super.key});

  @override
  State<AssignedStudentsPage> createState() => _AssignedStudentsPageState();
}

class _AssignedStudentsPageState extends State<AssignedStudentsPage> {
  final _search = TextEditingController();
  Future<List<AssignedStudentInfo>>? _future;
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppControllerScope.of(context).loadAssignedStudents();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final future = AppControllerScope.of(
      context,
    ).loadAssignedStudents(refresh: true);
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('assignedStudents'))),
    body: FutureBuilder<List<AssignedStudentInfo>>(
      future: _future,
      builder: (context, snapshot) {
        final query = _query.trim().toLowerCase();
        final students = (snapshot.data ?? const <AssignedStudentInfo>[])
            .where(
              (item) =>
                  query.isEmpty ||
                  item.student.name.toLowerCase().contains(query) ||
                  item.student.phone.toLowerCase().contains(query) ||
                  item.group.name.toLowerCase().contains(query),
            )
            .toList(growable: false);
        return RefreshIndicator.adaptive(
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
                    title: context.tr('assignedStudents'),
                    subtitle: context.tr('assignedStudentsSubtitle'),
                    trailing: snapshot.hasData
                        ? StatusPill(
                            label: '${snapshot.data!.length}',
                            color: const Color(0xFF2D8B73),
                          )
                        : null,
                  ),
                ),
              ),
              SliverToBoxAdapter(
                child: MaxWidthBox(
                  maxWidth: 860,
                  child: Padding(
                    padding: const EdgeInsets.only(top: 17, bottom: 12),
                    child: TextField(
                      controller: _search,
                      onChanged: (value) => setState(() => _query = value),
                      decoration: InputDecoration(
                        hintText: context.tr('search'),
                        prefixIcon: const Icon(Icons.search_rounded),
                      ),
                    ),
                  ),
                ),
              ),
              if (snapshot.connectionState == ConnectionState.waiting)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator.adaptive()),
                )
              else if (snapshot.hasError)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: 'Students need another moment',
                    body:
                        'Pull down or try again to reload your assigned groups.',
                    action: context.tr('tryAgain'),
                    onAction: _refresh,
                    icon: Icons.cloud_off_outlined,
                  ),
                )
              else if (students.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    title: context.tr('noItems'),
                    body: context.tr('assignedStudentsSubtitle'),
                    icon: Icons.school_outlined,
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: SliverList.separated(
                    itemCount: students.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 10),
                    itemBuilder: (context, index) {
                      final item = students[index];
                      return MaxWidthBox(
                        maxWidth: 860,
                        padding: EdgeInsets.zero,
                        child: PremiumCard(
                          padding: const EdgeInsets.all(15),
                          onTap: () async {
                            final moved = await Navigator.of(context)
                                .push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => StudentDetailPage(
                                      student: item.student,
                                      group: item.group,
                                    ),
                                  ),
                                );
                            if (moved == true && mounted) await _refresh();
                          },
                          child: Row(
                            children: [
                              PersonAvatar(name: item.student.name),
                              const SizedBox(width: 13),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.student.name,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.titleMedium,
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      '${item.group.name} · ${item.student.phone.isEmpty ? item.student.id : item.student.phone}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded),
                            ],
                          ),
                        ),
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

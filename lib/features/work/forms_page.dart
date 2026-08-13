import 'package:flutter/material.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/workflow_models.dart';

class StaffFormsPage extends StatefulWidget {
  const StaffFormsPage({super.key});

  @override
  State<StaffFormsPage> createState() => _StaffFormsPageState();
}

class _StaffFormsPageState extends State<StaffFormsPage> {
  Future<List<StaffFormInfo>>? _future;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= AppControllerScope.of(context).loadStaffForms();
  }

  Future<void> _refresh() async {
    final future = AppControllerScope.of(context).loadStaffForms();
    setState(() => _future = future);
    await future;
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(context.tr('formsSurveys'))),
    body: FutureBuilder<List<StaffFormInfo>>(
      future: _future,
      builder: (context, snapshot) => RefreshIndicator.adaptive(
        onRefresh: _refresh,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics(),
          ),
          slivers: [
            SliverToBoxAdapter(
              child: MaxWidthBox(
                maxWidth: 840,
                child: PageIntro(
                  title: context.tr('formsSurveys'),
                  subtitle: context.tr('formsSurveysSubtitle'),
                  trailing: snapshot.hasData
                      ? StatusPill(
                          label:
                              '${snapshot.data!.where((item) => item.status == 'published').length}',
                          color: const Color(0xFF2D8B73),
                        )
                      : null,
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 18)),
            if (snapshot.connectionState == ConnectionState.waiting)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: CircularProgressIndicator.adaptive()),
              )
            else if (snapshot.hasError)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: 'Surveys need another moment',
                  body: 'Your available forms could not be refreshed just now.',
                  action: context.tr('tryAgain'),
                  onAction: _refresh,
                  icon: Icons.cloud_off_outlined,
                ),
              )
            else if ((snapshot.data ?? const []).isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  title: context.tr('noItems'),
                  body: context.tr('formsSurveysSubtitle'),
                  icon: Icons.ballot_outlined,
                ),
              )
            else
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                sliver: SliverList.separated(
                  itemCount: snapshot.data!.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 11),
                  itemBuilder: (context, index) {
                    final form = snapshot.data![index];
                    final canAnswer =
                        form.status == 'published' &&
                        (!form.responseSubmitted || form.allowMultiple);
                    return MaxWidthBox(
                      maxWidth: 840,
                      padding: EdgeInsets.zero,
                      child: PremiumCard(
                        onTap: canAnswer
                            ? () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) => StaffFormResponsePage(
                                      initialForm: form,
                                    ),
                                  ),
                                );
                                if (mounted) await _refresh();
                              }
                            : null,
                        child: Row(
                          children: [
                            Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: const Color(
                                  0xFF8C5CC4,
                                ).withValues(alpha: .12),
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: const Icon(
                                Icons.ballot_outlined,
                                color: Color(0xFF8C5CC4),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    form.title,
                                    style: Theme.of(
                                      context,
                                    ).textTheme.titleMedium,
                                  ),
                                  if (form.description.isNotEmpty) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      form.description,
                                      maxLines: 2,
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
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 7,
                                    runSpacing: 7,
                                    children: [
                                      StatusPill(
                                        label: form.responseSubmitted
                                            ? 'Completed'
                                            : form.status,
                                        color: form.responseSubmitted
                                            ? const Color(0xFF2D8B73)
                                            : AppTheme.gold,
                                      ),
                                      if (form.anonymous)
                                        const StatusPill(
                                          label: 'Anonymous',
                                          color: Color(0xFF5867C9),
                                          icon: Icons.visibility_off_outlined,
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                            if (canAnswer)
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
      ),
    ),
  );
}

class StaffFormResponsePage extends StatefulWidget {
  const StaffFormResponsePage({super.key, required this.initialForm});

  final StaffFormInfo initialForm;

  @override
  State<StaffFormResponsePage> createState() => _StaffFormResponsePageState();
}

class _StaffFormResponsePageState extends State<StaffFormResponsePage> {
  late Future<StaffFormInfo> _future;
  final Map<int, Object?> _answers = {};
  bool _submitting = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future = AppControllerScope.of(
      context,
    ).loadStaffForm(widget.initialForm.id);
  }

  Future<void> _submit(StaffFormInfo form) async {
    for (final field in form.fields.where((field) => field.required)) {
      final answer = _answers[field.id];
      final missing =
          answer == null ||
          answer is String && answer.trim().isEmpty ||
          answer is List && answer.isEmpty;
      if (missing) {
        showPremiumToast(
          context,
          'Please answer “${field.label}”.',
          icon: Icons.info_outline_rounded,
          color: AppTheme.gold,
        );
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      await AppControllerScope.of(context).submitStaffForm(form.id, _answers);
      if (!mounted) return;
      showPremiumToast(context, 'Your response was submitted.');
      Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          'Your response could not be submitted.',
          icon: Icons.error_outline_rounded,
          color: AppTheme.coral,
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.initialForm.title)),
    body: FutureBuilder<StaffFormInfo>(
      future: _future,
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          if (snapshot.hasError) {
            return EmptyState(
              title: 'This survey could not be opened',
              body: 'Please return and try again.',
              icon: Icons.error_outline_rounded,
            );
          }
          return const Center(child: CircularProgressIndicator.adaptive());
        }
        final form = snapshot.data!;
        return SafeArea(
          top: false,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 36),
            children: [
              MaxWidthBox(
                maxWidth: 720,
                padding: EdgeInsets.zero,
                child: PageIntro(
                  title: form.title,
                  subtitle: form.description,
                  trailing: form.anonymous
                      ? const StatusPill(
                          label: 'Anonymous',
                          color: Color(0xFF5867C9),
                        )
                      : null,
                ),
              ),
              const SizedBox(height: 20),
              for (final field in form.fields) ...[
                MaxWidthBox(
                  maxWidth: 720,
                  padding: EdgeInsets.zero,
                  child: PremiumCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: field.label,
                            children: field.required
                                ? const [
                                    TextSpan(
                                      text: ' *',
                                      style: TextStyle(color: AppTheme.coral),
                                    ),
                                  ]
                                : const [],
                          ),
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        if (field.helpText.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            field.helpText,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 14),
                        _StaffFormField(
                          field: field,
                          value: _answers[field.id],
                          onChanged: (value) =>
                              setState(() => _answers[field.id] = value),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              MaxWidthBox(
                maxWidth: 720,
                padding: EdgeInsets.zero,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : () => _submit(form),
                  icon: _submitting
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('Submit response'),
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _StaffFormField extends StatelessWidget {
  const _StaffFormField({
    required this.field,
    required this.value,
    required this.onChanged,
  });

  final StaffFormFieldInfo field;
  final Object? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) => switch (field.type) {
    'single_choice' => DropdownButtonFormField<String>(
      initialValue: value as String?,
      decoration: const InputDecoration(labelText: 'Choose one'),
      items: field.options
          .map((option) => DropdownMenuItem(value: option, child: Text(option)))
          .toList(growable: false),
      onChanged: onChanged,
    ),
    'multi_choice' => Wrap(
      spacing: 8,
      runSpacing: 8,
      children: field.options
          .map((option) {
            final selected = (value as List<String>? ?? const []).contains(
              option,
            );
            return FilterChip(
              label: Text(option),
              selected: selected,
              onSelected: (checked) {
                final next = [...(value as List<String>? ?? const [])];
                checked ? next.add(option) : next.remove(option);
                onChanged(next);
              },
            );
          })
          .toList(growable: false),
    ),
    'boolean' => SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: true, label: Text('Yes')),
        ButtonSegment(value: false, label: Text('No')),
      ],
      selected: value is bool ? {value! as bool} : const <bool>{},
      emptySelectionAllowed: true,
      onSelectionChanged: (selection) =>
          onChanged(selection.isEmpty ? null : selection.first),
    ),
    'rating' => Wrap(
      spacing: 4,
      children: List.generate(
        5,
        (index) => IconButton.filledTonal(
          tooltip: '${index + 1}',
          onPressed: () => onChanged(index + 1),
          icon: Icon(
            index < (value as int? ?? 0)
                ? Icons.star_rounded
                : Icons.star_outline_rounded,
          ),
        ),
      ),
    ),
    'date' => _DateAnswer(value: value as String?, onChanged: onChanged),
    _ => TextFormField(
      initialValue: value?.toString(),
      minLines: field.type == 'textarea' ? 4 : 1,
      maxLines: field.type == 'textarea' ? 8 : 1,
      keyboardType: field.type == 'number'
          ? const TextInputType.numberWithOptions(decimal: true)
          : TextInputType.text,
      onChanged: (text) =>
          onChanged(field.type == 'number' ? num.tryParse(text) ?? text : text),
    ),
  };
}

class _DateAnswer extends StatelessWidget {
  const _DateAnswer({required this.value, required this.onChanged});

  final String? value;
  final ValueChanged<Object?> onChanged;

  @override
  Widget build(BuildContext context) => OutlinedButton.icon(
    onPressed: () async {
      final now = DateTime.now();
      final selected = await showDatePicker(
        context: context,
        firstDate: DateTime(now.year - 2),
        lastDate: DateTime(now.year + 2),
        initialDate: DateTime.tryParse(value ?? '') ?? now,
      );
      if (selected != null) {
        onChanged(selected.toIso8601String().split('T').first);
      }
    },
    icon: const Icon(Icons.calendar_today_outlined),
    label: Text(value ?? 'Choose date'),
  );
}

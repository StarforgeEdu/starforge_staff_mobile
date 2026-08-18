import 'models.dart';
import 'remote_models.dart';

Map<String, dynamic> _jsonMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) return value.cast<String, dynamic>();
  return const {};
}

List<String> _jsonStrings(Object? value) {
  if (value is! List) return const [];
  return value
      .map((item) {
        if (item is Map) {
          final option = item.cast<Object?, Object?>();
          return jsonString(
            option['value'] ?? option['label'] ?? option['name'] ?? option['title'],
          ).trim();
        }
        return jsonString(item).trim();
      })
      .where((item) => item.isNotEmpty)
      .toList(growable: false);
}

class StaffRequestInfo {
  const StaffRequestInfo({
    required this.id,
    required this.kind,
    required this.title,
    required this.description,
    required this.status,
    required this.amount,
    required this.decisionNote,
    required this.createdAt,
  });

  factory StaffRequestInfo.fromJson(Map<String, dynamic> json) =>
      StaffRequestInfo(
        id: jsonRequiredPositiveInt(json['id'], 'request.id'),
        kind: jsonString(json['kind'], 'other'),
        title: jsonString(json['title']),
        description: jsonString(json['description']),
        status: jsonString(json['status'], 'pending'),
        amount: jsonDouble(json['amount_uzs']),
        decisionNote: jsonString(json['decision_note']),
        createdAt: jsonDate(json['created_at']),
      );

  final int id;
  final String kind;
  final String title;
  final String description;
  final String status;
  final double amount;
  final String decisionNote;
  final DateTime? createdAt;
}

class StaffFormFieldInfo {
  const StaffFormFieldInfo({
    required this.id,
    required this.label,
    required this.type,
    required this.required,
    required this.options,
    required this.helpText,
  });

  factory StaffFormFieldInfo.fromJson(Map<String, dynamic> json) =>
      StaffFormFieldInfo(
        id: jsonRequiredPositiveInt(json['id'], 'form_field.id'),
        label: jsonString(json['label']),
        type: jsonString(json['field_type'], 'short_text'),
        required: json['required'] == true,
        options: _jsonStrings(json['options']),
        helpText: jsonString(json['help_text']),
      );

  final int id;
  final String label;
  final String type;
  final bool required;
  final List<String> options;
  final String helpText;
}

class StaffFormInfo {
  const StaffFormInfo({
    required this.id,
    required this.title,
    required this.description,
    required this.status,
    required this.anonymous,
    required this.allowMultiple,
    required this.responseSubmitted,
    required this.fields,
    required this.closesAt,
  });

  factory StaffFormInfo.fromJson(Map<String, dynamic> json) => StaffFormInfo(
    id: jsonRequiredPositiveInt(json['id'], 'form.id'),
    title: jsonString(json['title']),
    description: jsonString(json['description']),
    status: jsonString(json['status'], 'draft'),
    anonymous: json['is_anonymous'] == true,
    allowMultiple: json['allow_multiple'] == true,
    responseSubmitted: json['response_submitted'] == true,
    fields:
        (json['form_fields'] is List ? json['form_fields'] as List : const [])
            .whereType<Map>()
            .map(
              (item) =>
                  StaffFormFieldInfo.fromJson(item.cast<String, dynamic>()),
            )
            .toList(growable: false),
    closesAt: jsonDate(json['closes_at']),
  );

  final int id;
  final String title;
  final String description;
  final String status;
  final bool anonymous;
  final bool allowMultiple;
  final bool responseSubmitted;
  final List<StaffFormFieldInfo> fields;
  final DateTime? closesAt;
}

class StaffAchievementInfo {
  const StaffAchievementInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.emoji,
    required this.scope,
    required this.status,
    required this.cohortId,
    required this.createdAt,
  });

  factory StaffAchievementInfo.fromJson(Map<String, dynamic> json) =>
      StaffAchievementInfo(
        id: jsonRequiredPositiveInt(json['id'], 'achievement.id'),
        name: jsonString(json['name']),
        description: jsonString(json['description']),
        emoji: jsonString(json['emoji'], '⭐'),
        scope: jsonString(json['scope']),
        status: jsonString(json['status']),
        cohortId: jsonInt(json['cohort']),
        createdAt: jsonDate(json['created_at']),
      );

  final int id;
  final String name;
  final String description;
  final String emoji;
  final String scope;
  final String status;
  final int? cohortId;
  final DateTime? createdAt;
}

class StaffReportInfo {
  const StaffReportInfo({
    required this.id,
    required this.key,
    required this.title,
    required this.description,
    required this.defaultFormat,
  });

  factory StaffReportInfo.fromJson(Map<String, dynamic> json) =>
      StaffReportInfo(
        id: jsonRequiredPositiveInt(json['id'], 'report.id'),
        key: jsonString(json['key']),
        title: jsonString(json['title']),
        description: jsonString(json['description']),
        defaultFormat: jsonString(json['default_format'], 'pdf'),
      );

  final int id;
  final String key;
  final String title;
  final String description;
  final String defaultFormat;
}

class StaffReportRunInfo {
  const StaffReportRunInfo({
    required this.id,
    required this.reportKey,
    required this.format,
    required this.status,
    required this.downloadUrl,
    required this.error,
    required this.createdAt,
  });

  factory StaffReportRunInfo.fromJson(Map<String, dynamic> json) =>
      StaffReportRunInfo(
        id: jsonRequiredPositiveInt(json['id'], 'report_run.id'),
        reportKey: jsonString(json['report_key']),
        format: jsonString(json['format']),
        status: jsonString(json['status']),
        downloadUrl: jsonString(json['download_url']),
        error: jsonString(json['error']),
        createdAt: jsonDate(json['created_at']),
      );

  final int id;
  final String reportKey;
  final String format;
  final String status;
  final String downloadUrl;
  final String error;
  final DateTime? createdAt;
}

class AssignedStudentInfo {
  const AssignedStudentInfo({required this.student, required this.group});

  final Student student;
  final LearningGroup group;
}

class BranchChoiceInfo {
  const BranchChoiceInfo({
    required this.id,
    required this.name,
    required this.isActive,
  });

  factory BranchChoiceInfo.fromJson(Map<String, dynamic> json) =>
      BranchChoiceInfo(
        id: jsonRequiredPositiveInt(json['id'], 'branch.id'),
        name: jsonString(json['name']),
        isActive: json['is_active'] != false,
      );

  final int id;
  final String name;
  final bool isActive;
}

Map<String, dynamic> workflowJsonMap(Object? value) => _jsonMap(value);

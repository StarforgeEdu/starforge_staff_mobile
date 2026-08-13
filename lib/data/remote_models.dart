import 'models.dart';

int? jsonInt(Object? value) {
  if (value is int) return value;
  if (value is num) {
    final number = value.toDouble();
    if (!number.isFinite || number.truncateToDouble() != number) return null;
    return number.toInt();
  }
  if (value is String) return int.tryParse(value.trim());
  return null;
}

double jsonDouble(Object? value, [double fallback = 0]) => switch (value) {
  num number => number.toDouble(),
  String text => double.tryParse(text) ?? fallback,
  _ => fallback,
};

String jsonString(Object? value, [String fallback = '']) => switch (value) {
  String text => text,
  num number => number.toString(),
  bool boolean => boolean.toString(),
  _ => fallback,
};

DateTime? jsonDate(Object? value) =>
    value == null ? null : DateTime.tryParse(value.toString());

int jsonRequiredPositiveInt(Object? value, String field) {
  final parsed = jsonInt(value);
  if (parsed == null || parsed <= 0) {
    throw FormatException('Missing or invalid positive integer: $field');
  }
  return parsed;
}

int jsonRequiredNonNegativeInt(Object? value, String field) {
  final parsed = jsonInt(value);
  if (parsed == null || parsed < 0) {
    throw FormatException('Missing or invalid non-negative integer: $field');
  }
  return parsed;
}

int? jsonOptionalPositiveInt(Object? value, String field) {
  if (value == null) return null;
  return jsonRequiredPositiveInt(value, field);
}

DateTime jsonRequiredDate(Object? value, String field) {
  final parsed = jsonDate(value);
  if (parsed == null) throw FormatException('Missing or invalid date: $field');
  return parsed;
}

class RoleMembership {
  const RoleMembership({
    required this.id,
    required this.name,
    required this.slug,
    required this.kind,
    required this.branchName,
    required this.departmentName,
    required this.branchId,
    required this.departmentId,
  });

  factory RoleMembership.fromJson(Map<String, dynamic> json) => RoleMembership(
    id: jsonRequiredPositiveInt(json['id'], 'membership.id'),
    name: jsonString(
      json['account_type_name'],
      jsonString(json['legacy_role']),
    ),
    slug: jsonString(
      json['account_type_slug'],
      jsonString(json['legacy_role']),
    ),
    kind: jsonString(json['account_kind']),
    branchName: jsonString(json['branch_name']),
    departmentName: jsonString(json['department_name']),
    branchId: jsonOptionalPositiveInt(json['branch'], 'membership.branch'),
    departmentId: jsonOptionalPositiveInt(
      json['department'],
      'membership.department',
    ),
  );

  final int id;
  final String name;
  final String slug;
  final String kind;
  final String branchName;
  final String departmentName;
  final int? branchId;
  final int? departmentId;
}

class StaffAccount {
  const StaffAccount({
    required this.id,
    required this.principalKind,
    required this.username,
    required this.fullName,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    required this.phone,
    required this.email,
    required this.preferredLanguage,
    required this.mustChangePassword,
    required this.memberships,
    required this.permissions,
    required this.readOnly,
  });

  factory StaffAccount.fromJson(Map<String, dynamic> json) => StaffAccount(
    id: jsonRequiredPositiveInt(json['id'], 'account.id'),
    principalKind: jsonString(json['principal_kind']),
    username: jsonString(json['username']),
    fullName: jsonString(json['full_name']).trim().isEmpty
        ? jsonString(json['username'])
        : jsonString(json['full_name']),
    firstName: jsonString(json['first_name']),
    middleName: jsonString(json['middle_name']),
    lastName: jsonString(json['last_name']),
    phone: jsonString(json['phone']),
    email: jsonString(json['email']),
    preferredLanguage: jsonString(json['preferred_language'], 'uz'),
    mustChangePassword: json['must_change_password'] == true,
    memberships: (json['role_memberships'] as List? ?? const [])
        .whereType<Map>()
        .map((item) => RoleMembership.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false),
    permissions: (json['effective_permissions'] as List? ?? const [])
        .map((item) => item.toString())
        .toSet(),
    readOnly: json['read_only_session'] == true,
  );

  final int id;
  final String principalKind;
  final String username;
  final String fullName;
  final String firstName;
  final String middleName;
  final String lastName;
  final String phone;
  final String email;
  final String preferredLanguage;
  final bool mustChangePassword;
  final List<RoleMembership> memberships;
  final Set<String> permissions;
  final bool readOnly;

  String get roleName => memberships.isEmpty
      ? (principalKind == 'teacher' ? 'Teacher' : 'Staff')
      : memberships
            .map((item) => item.name)
            .where((name) => name.isNotEmpty)
            .join(' · ');

  String get branchName => memberships
      .map((item) => item.branchName)
      .firstWhere((name) => name.isNotEmpty, orElse: () => '');

  String get departmentName => memberships
      .map((item) => item.departmentName)
      .firstWhere((name) => name.isNotEmpty, orElse: () => '');

  bool can(String permission) {
    if (permissions.contains('*:*') || permissions.contains(permission)) {
      return true;
    }
    final separator = permission.indexOf(':');
    if (separator <= 0) return false;
    return permissions.contains('${permission.substring(0, separator)}:*');
  }
}

class LoginSession {
  const LoginSession({
    required this.access,
    required this.principalKind,
    required this.mustChangePassword,
  });

  factory LoginSession.fromJson(Map<String, dynamic> json) => LoginSession(
    access: jsonString(json['access']),
    principalKind: jsonString(json['role']),
    mustChangePassword: json['must_change_password'] == true,
  );

  final String access;
  final String principalKind;
  final bool mustChangePassword;
}

class LessonInfo {
  const LessonInfo({
    required this.id,
    required this.cohortId,
    required this.cohortName,
    required this.title,
    required this.roomName,
    required this.typeName,
    required this.startsAt,
    required this.endsAt,
    required this.status,
  });

  factory LessonInfo.fromJson(Map<String, dynamic> json) => LessonInfo(
    id: jsonRequiredPositiveInt(json['id'], 'lesson.id'),
    cohortId: jsonRequiredPositiveInt(json['cohort'], 'lesson.cohort'),
    cohortName: jsonString(
      json['cohort_name'],
      json['cohort'] is String ? jsonString(json['cohort']) : '',
    ),
    title: jsonString(json['title']),
    roomName: jsonString(json['room_name']),
    typeName: jsonString(json['lesson_type_name']),
    startsAt: jsonRequiredDate(json['starts_at'], 'lesson.starts_at'),
    endsAt: jsonRequiredDate(json['ends_at'], 'lesson.ends_at'),
    status: jsonString(json['status']),
  );

  final int id;
  final int cohortId;
  final String cohortName;
  final String title;
  final String roomName;
  final String typeName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String status;

  bool get isCancelled => status == 'cancelled';
}

class CohortCycleNextLessonInfo {
  const CohortCycleNextLessonInfo({
    required this.id,
    required this.title,
    required this.startsAt,
    required this.endsAt,
    required this.roomName,
    required this.teacherName,
    required this.cycleLessonNumber,
    required this.isCycleExamDay,
  });

  factory CohortCycleNextLessonInfo.fromJson(Map<String, dynamic> json) {
    final cycleLessonNumber = jsonRequiredPositiveInt(
      json['cycle_lesson_number'],
      'cycle.next_lesson.cycle_lesson_number',
    );
    if (cycleLessonNumber > 12 || json['is_cycle_exam_day'] is! bool) {
      throw const FormatException('Invalid cycle next lesson.');
    }
    return CohortCycleNextLessonInfo(
      id: jsonRequiredPositiveInt(json['id'], 'cycle.next_lesson.id'),
      title: jsonString(json['title']),
      startsAt: jsonRequiredDate(
        json['starts_at'],
        'cycle.next_lesson.starts_at',
      ),
      endsAt: jsonRequiredDate(json['ends_at'], 'cycle.next_lesson.ends_at'),
      roomName: jsonString(json['room_name']),
      teacherName: jsonString(json['teacher_name']),
      cycleLessonNumber: cycleLessonNumber,
      isCycleExamDay: json['is_cycle_exam_day'] as bool,
    );
  }

  final int id;
  final String title;
  final DateTime startsAt;
  final DateTime endsAt;
  final String roomName;
  final String teacherName;
  final int cycleLessonNumber;
  final bool isCycleExamDay;
}

class CohortCycleProgressInfo {
  const CohortCycleProgressInfo({
    required this.cohortId,
    required this.currentLevel,
    required this.currentStudyMonth,
    required this.lessonCycleLength,
    required this.completedLessons,
    required this.completedCycles,
    required this.completedInCurrentCycle,
    required this.nextCycleLessonNumber,
    required this.lessonsRemainingInCycle,
    required this.examDayDue,
    required this.examReminderDue,
    required this.nextScheduledLesson,
    required this.pastScheduledLessonsWithoutCompletion,
    required this.completionDataComplete,
  });

  factory CohortCycleProgressInfo.fromJson(Map<String, dynamic> json) {
    final cycleLength = jsonRequiredPositiveInt(
      json['lesson_cycle_length'],
      'cycle.lesson_cycle_length',
    );
    final completedLessons = jsonInt(json['completed_lessons']);
    final completedCycles = jsonInt(json['completed_cycles']);
    final completedInCycle = jsonInt(json['completed_in_current_cycle']);
    final nextNumber = jsonInt(json['next_cycle_lesson_number']);
    final remaining = jsonInt(json['lessons_remaining_in_cycle']);
    final overdue = jsonInt(json['past_scheduled_lessons_without_completion']);
    final examDay = json['exam_day_due'];
    final reminder = json['exam_reminder_due'];
    final complete = json['completion_data_complete'];
    final automatic = json['automatic_level_progression'];
    final studyMonth = jsonInt(json['current_study_month']);
    if (!const {8, 12}.contains(cycleLength) ||
        studyMonth == null ||
        studyMonth < 1 ||
        studyMonth > 600 ||
        completedLessons == null ||
        completedLessons < 0 ||
        completedCycles == null ||
        completedCycles < 0 ||
        completedInCycle == null ||
        completedInCycle < 0 ||
        completedInCycle >= cycleLength ||
        nextNumber == null ||
        nextNumber != completedInCycle + 1 ||
        remaining == null ||
        remaining != cycleLength - completedInCycle ||
        overdue == null ||
        overdue < 0 ||
        examDay is! bool ||
        reminder is! bool ||
        complete is! bool ||
        jsonInt(json['exam_reminder_window_days']) != 7 ||
        jsonString(json['level_progression_mode']) != 'manual' ||
        automatic != false ||
        completedCycles != completedLessons ~/ cycleLength ||
        completedInCycle != completedLessons % cycleLength ||
        examDay != (nextNumber == cycleLength) ||
        complete != (overdue == 0)) {
      throw const FormatException('Invalid cohort cycle progress.');
    }
    final rawNext = json['next_scheduled_lesson'];
    final next = rawNext == null
        ? null
        : rawNext is Map
        ? CohortCycleNextLessonInfo.fromJson(rawNext.cast<String, dynamic>())
        : throw const FormatException('Invalid cycle next lesson.');
    if (next != null &&
        (next.cycleLessonNumber != nextNumber ||
            next.isCycleExamDay != examDay)) {
      throw const FormatException('Inconsistent cycle next lesson.');
    }
    return CohortCycleProgressInfo(
      cohortId: jsonRequiredPositiveInt(json['cohort'], 'cycle.cohort'),
      currentLevel: jsonString(json['current_level']),
      currentStudyMonth: studyMonth,
      lessonCycleLength: cycleLength,
      completedLessons: completedLessons,
      completedCycles: completedCycles,
      completedInCurrentCycle: completedInCycle,
      nextCycleLessonNumber: nextNumber,
      lessonsRemainingInCycle: remaining,
      examDayDue: examDay,
      examReminderDue: reminder,
      nextScheduledLesson: next,
      pastScheduledLessonsWithoutCompletion: overdue,
      completionDataComplete: complete,
    );
  }

  final int cohortId;
  final String currentLevel;
  final int currentStudyMonth;
  final int lessonCycleLength;
  final int completedLessons;
  final int completedCycles;
  final int completedInCurrentCycle;
  final int nextCycleLessonNumber;
  final int lessonsRemainingInCycle;
  final bool examDayDue;
  final bool examReminderDue;
  final CohortCycleNextLessonInfo? nextScheduledLesson;
  final int pastScheduledLessonsWithoutCompletion;
  final bool completionDataComplete;
}

class CohortTeachingProgressInfo {
  const CohortTeachingProgressInfo({
    required this.cohortId,
    required this.level,
    required this.studyMonth,
    required this.lessonCycleLength,
    required this.updatedAt,
  });

  factory CohortTeachingProgressInfo.fromJson(Map<String, dynamic> json) {
    final studyMonth = jsonInt(json['study_month']);
    final cycleLength = jsonInt(json['lesson_cycle_length']);
    if (studyMonth == null ||
        studyMonth < 1 ||
        studyMonth > 600 ||
        !const {8, 12}.contains(cycleLength)) {
      throw const FormatException('Invalid cohort teaching progress.');
    }
    return CohortTeachingProgressInfo(
      cohortId: jsonRequiredPositiveInt(
        json['cohort'],
        'teachingProgress.cohort',
      ),
      level: jsonString(json['level']),
      studyMonth: studyMonth,
      lessonCycleLength: cycleLength!,
      updatedAt: jsonRequiredDate(
        json['updated_at'],
        'teachingProgress.updated_at',
      ),
    );
  }

  final int cohortId;
  final String level;
  final int studyMonth;
  final int lessonCycleLength;
  final DateTime updatedAt;
}

class AttendanceRecordInfo {
  const AttendanceRecordInfo({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.lessonId,
    required this.lessonStartsAt,
    required this.status,
    required this.note,
    this.cardType = '',
  });

  factory AttendanceRecordInfo.fromJson(Map<String, dynamic> json) =>
      AttendanceRecordInfo(
        id: jsonRequiredPositiveInt(json['id'], 'attendance.id'),
        studentId: jsonRequiredPositiveInt(
          json['student'],
          'attendance.student',
        ),
        studentName: jsonString(json['student_name']),
        lessonId: jsonRequiredPositiveInt(json['lesson'], 'attendance.lesson'),
        lessonStartsAt: jsonRequiredDate(
          json['lesson_starts_at'],
          'attendance.lesson_starts_at',
        ),
        status: jsonString(json['status']),
        note: jsonString(json['note']),
        cardType: jsonString(json['card_type']),
      );

  final int id;
  final int studentId;
  final String studentName;
  final int lessonId;
  final DateTime lessonStartsAt;
  final String status;
  final String note;
  final String cardType;

  bool get wasCardScan => note == 'card_scan';
  bool get hasIssuedCard => cardType == 'smart' || cardType == 'warning';
}

class StudentAttendanceSummary {
  const StudentAttendanceSummary({
    required this.studentId,
    required this.name,
    required this.present,
    required this.absent,
    required this.late,
    required this.excused,
    required this.total,
    required this.percentPresent,
  });

  factory StudentAttendanceSummary.fromJson(Map<String, dynamic> json) =>
      StudentAttendanceSummary(
        studentId: jsonRequiredPositiveInt(
          json['student'],
          'attendance_summary.student',
        ),
        name: jsonString(json['name']),
        present: jsonInt(json['present']) ?? 0,
        absent: jsonInt(json['absent']) ?? 0,
        late: jsonInt(json['late']) ?? 0,
        excused: jsonInt(json['excused']) ?? 0,
        total: jsonInt(json['total']) ?? 0,
        percentPresent: jsonDouble(json['percent_present']),
      );

  final int studentId;
  final String name;
  final int present;
  final int absent;
  final int late;
  final int excused;
  final int total;
  final double percentPresent;
}

class AttendanceMonth {
  const AttendanceMonth({
    required this.month,
    required this.lessons,
    required this.records,
    required this.rate,
    required this.students,
  });

  factory AttendanceMonth.empty(DateTime month) => AttendanceMonth(
    month: month,
    lessons: const [],
    records: const [],
    rate: 0,
    students: const [],
  );

  final DateTime month;
  final List<LessonInfo> lessons;
  final List<AttendanceRecordInfo> records;
  final double rate;
  final List<StudentAttendanceSummary> students;

  List<AttendanceRecordInfo> recordsFor(int lessonId) =>
      records.where((record) => record.lessonId == lessonId).toList();

  int expectedRosterFor(int lessonId) {
    final recordedStudentIds = recordsFor(
      lessonId,
    ).map((record) => record.studentId).where((id) => id > 0).toSet();
    final dashboardStudentIds = students
        .map((student) => student.studentId)
        .where((id) => id > 0)
        .toSet();
    return <int>{...recordedStudentIds, ...dashboardStudentIds}.length;
  }

  bool isRegisterComplete(int lessonId, {int expectedRosterCount = 0}) {
    final inferred = expectedRosterFor(lessonId);
    final expected = inferred > expectedRosterCount
        ? inferred
        : expectedRosterCount;
    if (expected == 0) return false;
    final recorded = recordsFor(
      lessonId,
    ).map((record) => record.studentId).where((id) => id > 0).toSet().length;
    return recorded >= expected;
  }
}

class StudentLeadershipInfo {
  const StudentLeadershipInfo({
    required this.email,
    required this.status,
    required this.academicLevel,
    required this.location,
    required this.previousSchool,
    required this.branchName,
    required this.groupName,
    required this.groupLevel,
    required this.attendance,
    required this.recentExams,
    required this.assignments,
    required this.guardians,
    required this.learningAvailable,
    required this.familyAvailable,
  });

  factory StudentLeadershipInfo.fromJson(Map<String, dynamic> json) {
    Map<String, dynamic> map(Object? value) => value is Map
        ? value.cast<String, dynamic>()
        : const <String, dynamic>{};
    final identity = map(json['identity']);
    final branch = map(identity['branch']);
    final group = map(identity['current_group']);
    final attendanceJson = map(json['attendance']);
    final learning = map(json['learning']);
    final assignmentsJson = map(learning['assignments']);
    final family = map(json['family']);
    return StudentLeadershipInfo(
      email: jsonString(identity['email']),
      status: jsonString(identity['status']),
      academicLevel: jsonString(identity['academic_level']),
      location: jsonString(identity['location']),
      previousSchool: jsonString(identity['previous_school']),
      branchName: jsonString(branch['name']),
      groupName: jsonString(group['name']),
      groupLevel: jsonString(group['level']),
      attendance: attendanceJson.isEmpty
          ? null
          : StudentLeadershipAttendanceInfo.fromJson(attendanceJson),
      recentExams: (learning['recent_exam_results'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) => StudentLeadershipExamInfo.fromJson(
              item.cast<String, dynamic>(),
            ),
          )
          .toList(growable: false),
      assignments: assignmentsJson.isEmpty
          ? null
          : StudentLeadershipAssignmentInfo.fromJson(assignmentsJson),
      guardians: (family['guardians'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                StudentGuardianInfo.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
      learningAvailable: json['learning'] is Map,
      familyAvailable: json['family'] is Map,
    );
  }

  final String email;
  final String status;
  final String academicLevel;
  final String location;
  final String previousSchool;
  final String branchName;
  final String groupName;
  final String groupLevel;
  final StudentLeadershipAttendanceInfo? attendance;
  final List<StudentLeadershipExamInfo> recentExams;
  final StudentLeadershipAssignmentInfo? assignments;
  final List<StudentGuardianInfo> guardians;
  final bool learningAvailable;
  final bool familyAvailable;
}

class StudentLeadershipAttendanceInfo {
  const StudentLeadershipAttendanceInfo({
    required this.present,
    required this.late,
    required this.absent,
    required this.excused,
    required this.countableSessions,
    required this.rate,
    required this.currentStreak,
  });

  factory StudentLeadershipAttendanceInfo.fromJson(Map<String, dynamic> json) =>
      StudentLeadershipAttendanceInfo(
        present: jsonInt(json['present']) ?? 0,
        late: jsonInt(json['late']) ?? 0,
        absent: jsonInt(json['absent']) ?? 0,
        excused: jsonInt(json['excused']) ?? 0,
        countableSessions: jsonInt(json['countable_sessions']) ?? 0,
        rate: json['attendance_rate_fraction'] == null
            ? null
            : jsonDouble(json['attendance_rate_fraction']),
        currentStreak: jsonInt(json['current_attendance_streak']) ?? 0,
      );

  final int present;
  final int late;
  final int absent;
  final int excused;
  final int countableSessions;
  final double? rate;
  final int currentStreak;
}

class StudentLeadershipExamInfo {
  const StudentLeadershipExamInfo({
    required this.title,
    required this.subject,
    required this.date,
    required this.score,
    required this.maximum,
  });

  factory StudentLeadershipExamInfo.fromJson(Map<String, dynamic> json) {
    final exam = json['exam'] is Map
        ? (json['exam'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final subject = json['subject'] is Map
        ? (json['subject'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return StudentLeadershipExamInfo(
      title: jsonString(exam['title']),
      subject: jsonString(subject['name']),
      date: jsonDate(exam['date']),
      score: jsonDouble(json['score']),
      maximum: jsonDouble(json['maximum']),
    );
  }

  final String title;
  final String subject;
  final DateTime? date;
  final double score;
  final double maximum;
}

class StudentLeadershipAssignmentInfo {
  const StudentLeadershipAssignmentInfo({
    required this.assigned,
    required this.completed,
    required this.open,
    required this.late,
  });

  factory StudentLeadershipAssignmentInfo.fromJson(Map<String, dynamic> json) =>
      StudentLeadershipAssignmentInfo(
        assigned: jsonInt(json['assigned']) ?? 0,
        completed: jsonInt(json['completed']) ?? 0,
        open: jsonInt(json['open']) ?? 0,
        late: jsonInt(json['late']) ?? 0,
      );

  final int assigned;
  final int completed;
  final int open;
  final int late;
}

class StudentGuardianInfo {
  const StudentGuardianInfo({
    required this.name,
    required this.relationship,
    required this.phone,
    required this.email,
    required this.isPrimary,
  });

  factory StudentGuardianInfo.fromJson(Map<String, dynamic> json) {
    final contacts = json['contacts'] is Map
        ? (json['contacts'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return StudentGuardianInfo(
      name: jsonString(json['name']),
      relationship: jsonString(json['relationship']),
      phone: jsonString(contacts['phone']),
      email: jsonString(contacts['email']),
      isPrimary: json['is_primary'] == true,
    );
  }

  final String name;
  final String relationship;
  final String phone;
  final String email;
  final bool isPrimary;
}

class ExamInfo {
  const ExamInfo({
    required this.id,
    required this.title,
    required this.date,
    required this.maxScore,
    required this.published,
    this.subjectName = '',
    this.termName = '',
    this.typeName = '',
    this.requiresRepublish = false,
  });

  factory ExamInfo.fromJson(Map<String, dynamic> json) {
    final type = json['exam_type_detail'];
    return ExamInfo(
      id: jsonRequiredPositiveInt(json['id'], 'exam.id'),
      title: jsonString(json['title'], 'Exam'),
      date: jsonRequiredDate(json['exam_date'], 'exam.exam_date'),
      maxScore: jsonDouble(json['max_score'], 100),
      published: json['is_published'] == true,
      subjectName: jsonString(json['subject_name']),
      termName: jsonString(json['term_name']),
      typeName: type is Map ? jsonString(type['name']) : '',
      requiresRepublish: json['requires_republish'] == true,
    );
  }

  final int id;
  final String title;
  final DateTime date;
  final double maxScore;
  final bool published;
  final String subjectName;
  final String termName;
  final String typeName;
  final bool requiresRepublish;
}

class ExamResultInfo {
  const ExamResultInfo({
    required this.studentId,
    required this.studentName,
    required this.score,
    required this.note,
    this.components = const [],
  });

  factory ExamResultInfo.fromJson(Map<String, dynamic> json) => ExamResultInfo(
    studentId: jsonRequiredPositiveInt(json['student'], 'exam_result.student'),
    studentName: jsonString(json['student_name']),
    score: jsonDouble(json['score']),
    note: jsonString(json['note']),
    components: (json['components'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) =>
              ExamSkillComponentInfo.fromJson(item.cast<String, dynamic>()),
        )
        .where((component) => component.name.isNotEmpty)
        .toList(growable: false),
  );

  final int studentId;
  final String studentName;
  final double score;
  final String note;
  final List<ExamSkillComponentInfo> components;
}

class ExamSkillComponentInfo {
  const ExamSkillComponentInfo({
    required this.name,
    required this.score,
    required this.maxScore,
  });

  factory ExamSkillComponentInfo.fromJson(Map<String, dynamic> json) =>
      ExamSkillComponentInfo(
        name: jsonString(json['name']),
        score: jsonDouble(json['score']),
        maxScore: jsonDouble(json['max_score']),
      );

  final String name;
  final double score;
  final double maxScore;

  double get fraction => maxScore <= 0 ? 0 : (score / maxScore).clamp(0, 1);
}

class TeacherDashboardData {
  const TeacherDashboardData({
    required this.groupsCount,
    required this.studentsCount,
    required this.nextLessons,
    required this.nextMeeting,
  });

  factory TeacherDashboardData.fromJson(Map<String, dynamic> json) {
    final meeting = json['next_meeting'];
    return TeacherDashboardData(
      groupsCount: jsonRequiredNonNegativeInt(
        json['groups_count'],
        'teacher_dashboard.groups_count',
      ),
      studentsCount: jsonInt(json['students_count']),
      nextLessons: (json['next_lessons'] as List? ?? const [])
          .whereType<Map>()
          .map((item) => LessonInfo.fromJson(item.cast<String, dynamic>()))
          .toList(growable: false),
      nextMeeting: meeting is Map
          ? meeting.cast<String, dynamic>()
          : const <String, dynamic>{},
    );
  }

  final int groupsCount;
  final int? studentsCount;
  final List<LessonInfo> nextLessons;
  final Map<String, dynamic> nextMeeting;
}

enum FeatureAvailabilityStatus { available, degraded, unavailable }

class FeatureAvailabilityInfo {
  const FeatureAvailabilityInfo({required this.feature, required this.status});

  factory FeatureAvailabilityInfo.fromJson(Map<String, dynamic> json) =>
      FeatureAvailabilityInfo(
        feature: jsonString(json['feature']),
        status: switch (jsonString(json['status'])) {
          'available' => FeatureAvailabilityStatus.available,
          'degraded' => FeatureAvailabilityStatus.degraded,
          _ => FeatureAvailabilityStatus.unavailable,
        },
      );

  final String feature;
  final FeatureAvailabilityStatus status;

  bool get isAvailable => status == FeatureAvailabilityStatus.available;
}

class MessageContactInfo {
  const MessageContactInfo({
    required this.userId,
    required this.profileId,
    required this.principalKind,
    required this.category,
    required this.displayName,
    required this.username,
    required this.roleLabel,
    required this.recentlyActive,
  });

  factory MessageContactInfo.fromJson(Map<String, dynamic> json) =>
      MessageContactInfo(
        userId: jsonRequiredPositiveInt(
          json['user_id'] ?? json['id'],
          'message_contact.user_id',
        ),
        profileId: jsonInt(json['profile_id']),
        principalKind: jsonString(json['principal_kind']),
        category: jsonString(json['category']),
        displayName: jsonString(
          json['display_name'],
          jsonString(json['username']),
        ),
        username: jsonString(json['username']),
        roleLabel: jsonString(json['role_label']),
        recentlyActive: json['recently_active'] == true,
      );

  final int userId;
  final int? profileId;
  final String principalKind;
  final String category;
  final String displayName;
  final String username;
  final String roleLabel;
  final bool recentlyActive;
}

class MessageParticipantInfo {
  const MessageParticipantInfo({
    required this.userId,
    required this.principalKind,
    required this.principalId,
  });

  factory MessageParticipantInfo.fromJson(Map<String, dynamic> json) =>
      MessageParticipantInfo(
        userId: jsonRequiredPositiveInt(
          json['user'],
          'message_participant.user',
        ),
        principalKind: jsonString(json['principal_kind']),
        principalId: jsonInt(json['principal_id']),
      );

  final int userId;
  final String principalKind;
  final int? principalId;
}

class MessageThreadInfo {
  const MessageThreadInfo({
    required this.id,
    required this.subject,
    required this.participants,
    required this.unreadCount,
    required this.lastMessageAt,
    required this.notificationsMuted,
  });

  factory MessageThreadInfo.fromJson(Map<String, dynamic> json) =>
      MessageThreadInfo(
        id: jsonRequiredPositiveInt(json['id'], 'message_thread.id'),
        subject: jsonString(json['subject']),
        participants: (json['participants'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  MessageParticipantInfo.fromJson(item.cast<String, dynamic>()),
            )
            .toList(growable: false),
        unreadCount: jsonInt(json['unread_count']) ?? 0,
        lastMessageAt: jsonDate(json['last_message_at']),
        notificationsMuted: json['notifications_muted'] == true,
      );

  final int id;
  final String subject;
  final List<MessageParticipantInfo> participants;
  final int unreadCount;
  final DateTime? lastMessageAt;
  final bool notificationsMuted;
}

class MessageInfo {
  const MessageInfo({
    required this.id,
    required this.threadId,
    required this.senderUserId,
    required this.senderPrincipalKind,
    required this.senderPrincipalId,
    required this.body,
    required this.attachments,
    required this.createdAt,
  });

  factory MessageInfo.fromJson(Map<String, dynamic> json) => MessageInfo(
    id: jsonRequiredPositiveInt(json['id'], 'message.id'),
    threadId: jsonRequiredPositiveInt(json['thread'], 'message.thread'),
    senderUserId: jsonRequiredPositiveInt(json['sender'], 'message.sender'),
    senderPrincipalKind: jsonString(json['sender_principal_kind']),
    senderPrincipalId: jsonInt(json['sender_principal_id']),
    body: jsonString(json['body']),
    attachments: (json['attachments'] as List? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false),
    createdAt: jsonRequiredDate(json['created_at'], 'message.created_at'),
  );

  final int id;
  final int threadId;
  final int senderUserId;
  final String senderPrincipalKind;
  final int? senderPrincipalId;
  final String body;
  final List<String> attachments;
  final DateTime createdAt;
}

class ContentFolderInfo {
  const ContentFolderInfo({
    required this.id,
    required this.libraryId,
    required this.libraryName,
    required this.name,
    required this.parentId,
    required this.parentName,
    required this.libraryVisibility,
    required this.libraryCohortId,
    required this.libraryCohortName,
  });

  factory ContentFolderInfo.fromJson(Map<String, dynamic> json) =>
      ContentFolderInfo(
        id: jsonRequiredPositiveInt(json['id'], 'folder.id'),
        libraryId: jsonRequiredPositiveInt(json['library'], 'folder.library'),
        libraryName: jsonString(json['library_name']),
        name: jsonString(json['name']),
        parentId: jsonOptionalPositiveInt(json['parent'], 'folder.parent'),
        parentName: jsonString(json['parent_name']),
        libraryVisibility: jsonString(json['library_visibility']),
        libraryCohortId: jsonOptionalPositiveInt(
          json['library_cohort'],
          'folder.library_cohort',
        ),
        libraryCohortName: jsonString(json['library_cohort_name']),
      );

  final int id;
  final int libraryId;
  final String libraryName;
  final String name;
  final int? parentId;
  final String parentName;
  final String libraryVisibility;
  final int? libraryCohortId;
  final String libraryCohortName;
}

class ContentFileInfo {
  const ContentFileInfo({
    required this.id,
    required this.title,
    required this.contentType,
    required this.sizeBytes,
    required this.status,
    required this.locationName,
    required this.author,
    required this.thumbnailUrl,
    required this.downloadable,
    required this.createdAt,
    required this.teacherApproved,
    required this.managerApproved,
    required this.rejectReason,
  });

  factory ContentFileInfo.fromJson(Map<String, dynamic> json) =>
      ContentFileInfo(
        id: jsonRequiredPositiveInt(json['id'], 'content_file.id'),
        title: jsonString(json['title']),
        contentType: jsonString(json['content_type']),
        sizeBytes: jsonRequiredNonNegativeInt(
          json['size_bytes'],
          'content_file.size_bytes',
        ),
        status: jsonString(json['status']),
        locationName: jsonString(
          json['folder_name'],
          jsonString(json['lesson_title']),
        ),
        author: jsonString(json['uploaded_by_name']),
        thumbnailUrl: jsonString(json['thumbnail_url']),
        downloadable: json['is_downloadable'] != false,
        createdAt: jsonDate(json['created_at']),
        teacherApproved: json['is_approved_teacher'] == true,
        managerApproved: json['is_approved_manager'] == true,
        rejectReason: jsonString(json['reject_reason']),
      );

  final int id;
  final String title;
  final String contentType;
  final int sizeBytes;
  final String status;
  final String locationName;
  final String author;
  final String thumbnailUrl;
  final bool downloadable;
  final DateTime? createdAt;
  final bool teacherApproved;
  final bool managerApproved;
  final String rejectReason;
}

class LibraryMaterialInfo {
  const LibraryMaterialInfo({
    required this.id,
    required this.libraryName,
    required this.title,
    required this.topic,
    required this.body,
    required this.status,
    required this.author,
    required this.createdAt,
  });

  factory LibraryMaterialInfo.fromJson(Map<String, dynamic> json) =>
      LibraryMaterialInfo(
        id: jsonRequiredPositiveInt(json['id'], 'library_material.id'),
        libraryName: jsonString(json['library_name']),
        title: jsonString(json['title']),
        topic: jsonString(json['topic']),
        body: jsonString(json['body']),
        status: jsonString(json['status']),
        author: jsonString(json['created_by_name']),
        createdAt: jsonDate(json['created_at']),
      );

  final int id;
  final String libraryName;
  final String title;
  final String topic;
  final String body;
  final String status;
  final String author;
  final DateTime? createdAt;
}

class PrinterInfo {
  const PrinterInfo({
    required this.id,
    required this.branchId,
    required this.name,
    required this.modelName,
    required this.supportsColor,
    required this.supportsDuplex,
    required this.paperSizes,
    required this.active,
  });

  factory PrinterInfo.fromJson(Map<String, dynamic> json) {
    final capabilities = json['capabilities'];
    final safeCapabilities = capabilities is Map
        ? capabilities.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    return PrinterInfo(
      id: jsonRequiredPositiveInt(json['id'], 'printer.id'),
      branchId: jsonRequiredPositiveInt(json['branch'], 'printer.branch'),
      name: jsonString(json['name']),
      modelName: jsonString(json['model_name']),
      supportsColor: safeCapabilities['color'] == true,
      supportsDuplex: safeCapabilities['duplex'] == true,
      paperSizes: (safeCapabilities['paper'] as List? ?? const [])
          .map((item) => item.toString())
          .where((item) => item.isNotEmpty)
          .toList(growable: false),
      active: json['is_active'] == true,
    );
  }

  final int id;
  final int branchId;
  final String name;
  final String modelName;
  final bool supportsColor;
  final bool supportsDuplex;
  final List<String> paperSizes;
  final bool active;
}

class PrintJobInfo {
  const PrintJobInfo({
    required this.id,
    required this.printerId,
    required this.status,
    required this.source,
    required this.pages,
    required this.copies,
    required this.color,
    required this.duplex,
    required this.createdAt,
    required this.finishedAt,
    required this.scheduledFor,
  });

  factory PrintJobInfo.fromJson(Map<String, dynamic> json) => PrintJobInfo(
    id: jsonRequiredPositiveInt(json['id'], 'print_job.id'),
    printerId:
        jsonOptionalPositiveInt(
          json['preferred_printer'],
          'print_job.preferred_printer',
        ) ??
        jsonOptionalPositiveInt(json['printer'], 'print_job.printer'),
    status: jsonString(json['status']),
    source: jsonString(json['source']),
    pages: jsonRequiredPositiveInt(json['pages'], 'print_job.pages'),
    copies: jsonRequiredPositiveInt(json['copies'], 'print_job.copies'),
    color: json['color'] == true,
    duplex: json['duplex'] == true,
    createdAt: jsonRequiredDate(json['created_at'], 'print_job.created_at'),
    finishedAt: jsonDate(json['finished_at']),
    scheduledFor: jsonDate(json['scheduled_for']),
  );

  final int id;
  final int? printerId;
  final String status;
  final String source;
  final int pages;
  final int copies;
  final bool color;
  final bool duplex;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final DateTime? scheduledFor;
}

class PayrollPayslipInfo {
  const PayrollPayslipInfo({
    required this.id,
    required this.documentNumber,
    required this.periodStatus,
    required this.branchName,
    required this.departmentName,
    required this.periodLabel,
    required this.periodStart,
    required this.periodEnd,
    required this.payDate,
    required this.currency,
    required this.baseAmount,
    required this.bonusAmount,
    required this.deductionAmount,
    required this.netAmount,
    required this.generatedAt,
  });

  factory PayrollPayslipInfo.fromJson(Map<String, dynamic> json) {
    final snapshot = json['snapshot'] is Map
        ? (json['snapshot'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final period = snapshot['period'] is Map
        ? (snapshot['period'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return PayrollPayslipInfo(
      id: jsonRequiredPositiveInt(json['id'], 'payslip.id'),
      documentNumber: jsonString(json['document_number']),
      periodStatus: jsonString(json['period_status']),
      branchName: jsonString(json['branch_at_run_name']),
      departmentName: jsonString(json['department_at_run_name']),
      periodLabel: jsonString(period['label']),
      periodStart: jsonDate(period['period_start']),
      periodEnd: jsonDate(period['period_end']),
      payDate: jsonDate(period['pay_date']),
      currency: jsonString(snapshot['currency'], 'UZS'),
      baseAmount: jsonDouble(snapshot['base_amount_uzs']),
      bonusAmount: jsonDouble(snapshot['bonus_amount_uzs']),
      deductionAmount: jsonDouble(snapshot['deduction_amount_uzs']),
      netAmount: jsonDouble(snapshot['net_amount_uzs']),
      generatedAt: jsonDate(json['generated_at']),
    );
  }

  final int id;
  final String documentNumber;
  final String periodStatus;
  final String branchName;
  final String departmentName;
  final String periodLabel;
  final DateTime? periodStart;
  final DateTime? periodEnd;
  final DateTime? payDate;
  final String currency;
  final double baseAmount;
  final double bonusAmount;
  final double deductionAmount;
  final double netAmount;
  final DateTime? generatedAt;
}

class ComplianceRuleInfo {
  const ComplianceRuleInfo({
    required this.id,
    required this.title,
    required this.body,
    required this.version,
    required this.roles,
    required this.acknowledged,
    required this.updatedAt,
  });

  factory ComplianceRuleInfo.fromJson(Map<String, dynamic> json) =>
      ComplianceRuleInfo(
        id: jsonRequiredPositiveInt(json['id'], 'rule.id'),
        title: jsonString(json['title']),
        body: jsonString(json['body']),
        version: jsonRequiredPositiveInt(json['version'], 'rule.version'),
        roles: (json['applies_to_roles'] as List? ?? const [])
            .map((item) => item.toString())
            .toList(growable: false),
        acknowledged: json['acknowledged'] == true,
        updatedAt: jsonDate(json['updated_at']),
      );

  final int id;
  final String title;
  final String body;
  final int version;
  final List<String> roles;
  final bool acknowledged;
  final DateTime? updatedAt;

  ComplianceRuleInfo copyWith({bool? acknowledged}) => ComplianceRuleInfo(
    id: id,
    title: title,
    body: body,
    version: version,
    roles: roles,
    acknowledged: acknowledged ?? this.acknowledged,
    updatedAt: updatedAt,
  );
}

class NotificationInfo {
  const NotificationInfo({
    required this.id,
    required this.eventType,
    required this.title,
    required this.body,
    required this.data,
    required this.readAt,
    required this.createdAt,
  });

  factory NotificationInfo.fromJson(Map<String, dynamic> json) =>
      NotificationInfo(
        id: jsonRequiredPositiveInt(json['id'], 'notification.id'),
        eventType: jsonString(json['event_type']),
        title: jsonString(json['title']),
        body: jsonString(json['body']),
        data: json['data'] is Map
            ? (json['data'] as Map).cast<String, dynamic>()
            : const {},
        readAt: jsonDate(json['read_at']),
        createdAt: jsonRequiredDate(
          json['created_at'],
          'notification.created_at',
        ),
      );

  final int id;
  final String eventType;
  final String title;
  final String body;
  final Map<String, dynamic> data;
  final DateTime? readAt;
  final DateTime createdAt;

  bool get isRead => readAt != null;

  NotificationInfo copyWith({DateTime? readAt}) => NotificationInfo(
    id: id,
    eventType: eventType,
    title: title,
    body: body,
    data: data,
    readAt: readAt ?? this.readAt,
    createdAt: createdAt,
  );
}

/// A role-account's explicit override for one notification event/channel.
///
/// The notifications service treats a missing row as its channel default. The
/// staff app currently exposes only the durable in-app channel; external push
/// delivery is intentionally not presented until a mobile push provider is
/// configured for this app.
class NotificationPreferenceInfo {
  const NotificationPreferenceInfo({
    required this.eventType,
    required this.channel,
    required this.enabled,
  });

  factory NotificationPreferenceInfo.fromJson(Map<String, dynamic> json) =>
      NotificationPreferenceInfo(
        eventType: jsonString(json['event_type']),
        channel: jsonString(json['channel']),
        enabled: json['enabled'] == true,
      );

  final String eventType;
  final String channel;
  final bool enabled;

  Map<String, Object?> toJson() => {
    'event_type': eventType,
    'channel': channel,
    'enabled': enabled,
  };
}

class MeetingInfo {
  const MeetingInfo({
    required this.id,
    required this.title,
    required this.agenda,
    required this.branchName,
    required this.startsAt,
    required this.endsAt,
    required this.location,
    required this.status,
  });

  factory MeetingInfo.fromJson(Map<String, dynamic> json) => MeetingInfo(
    id: jsonRequiredPositiveInt(json['id'], 'meeting.id'),
    title: jsonString(json['title']),
    agenda: jsonString(json['agenda']),
    branchName: jsonString(json['branch_name']),
    startsAt: jsonRequiredDate(json['starts_at'], 'meeting.starts_at'),
    endsAt: jsonRequiredDate(json['ends_at'], 'meeting.ends_at'),
    location: jsonString(json['location']),
    status: jsonString(json['status']),
  );

  final int id;
  final String title;
  final String agenda;
  final String branchName;
  final DateTime startsAt;
  final DateTime endsAt;
  final String location;
  final String status;

  Map<String, dynamic> toDashboardMap() => {
    'id': id,
    'title': title,
    'starts_at': startsAt.toIso8601String(),
    'location': location,
  };
}

class CrmLeadInfo {
  const CrmLeadInfo({
    required this.id,
    required this.studentName,
    required this.phone,
    required this.branchName,
    required this.departmentName,
    required this.stageName,
    required this.state,
    required this.nextFollowUpAt,
  });

  factory CrmLeadInfo.fromJson(Map<String, dynamic> json) {
    final student = json['student'] is Map
        ? (json['student'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    final stage = json['stage'] is Map
        ? (json['stage'] as Map).cast<String, dynamic>()
        : const <String, dynamic>{};
    return CrmLeadInfo(
      id: jsonRequiredPositiveInt(json['id'], 'crm_lead.id'),
      studentName: jsonString(student['full_name']),
      phone: jsonString(student['phone']),
      branchName: jsonString(json['branch_name']),
      departmentName: jsonString(json['department_name']),
      stageName: jsonString(stage['name']),
      state: jsonString(json['state']),
      nextFollowUpAt: jsonDate(json['next_follow_up_at']),
    );
  }

  final int id;
  final String studentName;
  final String phone;
  final String branchName;
  final String departmentName;
  final String stageName;
  final String state;
  final DateTime? nextFollowUpAt;
}

class FinanceInvoiceInfo {
  const FinanceInvoiceInfo({
    required this.id,
    required this.number,
    required this.studentName,
    required this.status,
    required this.currency,
    required this.total,
    required this.outstanding,
    required this.dueDate,
  });

  factory FinanceInvoiceInfo.fromJson(Map<String, dynamic> json) =>
      FinanceInvoiceInfo(
        id: jsonRequiredPositiveInt(json['id'], 'finance_invoice.id'),
        number: jsonString(json['number']),
        studentName: jsonString(json['student_name']),
        status: jsonString(json['status']),
        currency: jsonString(json['currency'], 'UZS'),
        total: jsonDouble(json['total_uzs']),
        outstanding: jsonDouble(json['outstanding_uzs']),
        dueDate: jsonDate(json['due_date']),
      );

  final int id;
  final String number;
  final String studentName;
  final String status;
  final String currency;
  final double total;
  final double outstanding;
  final DateTime? dueDate;
}

class CashierShiftInfo {
  const CashierShiftInfo({
    required this.id,
    required this.branchName,
    required this.status,
    required this.openedAt,
    required this.closedAt,
    required this.openingCash,
    required this.closingCash,
    required this.discrepancy,
  });

  factory CashierShiftInfo.fromJson(Map<String, dynamic> json) =>
      CashierShiftInfo(
        id: jsonRequiredPositiveInt(json['id'], 'cashier_shift.id'),
        branchName: jsonString(json['branch_name']),
        status: jsonString(json['status']),
        openedAt: jsonDate(json['opened_at']),
        closedAt: jsonDate(json['closed_at']),
        openingCash: jsonDouble(json['opening_cash_uzs']),
        closingCash: jsonDouble(json['closing_cash_uzs']),
        discrepancy: jsonDouble(json['discrepancy_uzs']),
      );

  final int id;
  final String branchName;
  final String status;
  final DateTime? openedAt;
  final DateTime? closedAt;
  final double openingCash;
  final double closingCash;
  final double discrepancy;
}

Student studentFromJson(Map<String, dynamic> json) {
  final id = jsonRequiredPositiveInt(json['id'], 'student.id');
  final fullName = jsonString(json['full_name']).trim();
  return Student(
    id: '$id',
    name: fullName.isEmpty ? jsonString(json['username']) : fullName,
    phone: jsonString(json['phone']),
    guardian: '',
    guardianPhone: '',
    birthDate: jsonString(json['birthdate']),
    joinedDate: jsonString(json['enrollment_date']),
    attendance: null,
    lastExam: null,
    email: jsonString(json['email']),
    status: jsonString(json['status']),
    academicLevel: jsonString(json['academic_level']),
  );
}

LearningGroup groupFromJson(Map<String, dynamic> json) {
  final id = jsonRequiredPositiveInt(json['id'], 'cohort.id');
  final assignments = (json['teachers'] as List? ?? const [])
      .whereType<Map>()
      .map((item) => item.cast<Object?, Object?>())
      .toList(growable: false);
  final teachers = assignments
      .map((item) => jsonInt(item['teacher']))
      .whereType<int>()
      .toList(growable: false);
  final rawCycleLength = jsonInt(json['lesson_cycle_length']);
  final cycleLength = const {8, 12}.contains(rawCycleLength)
      ? rawCycleLength
      : null;
  final rawStudyMonth = jsonInt(json['study_month']);
  if (rawStudyMonth != null && (rawStudyMonth < 1 || rawStudyMonth > 600)) {
    throw const FormatException('Invalid cohort study month.');
  }
  List<int> teachersWithType(Set<String> slugs) => assignments
      .where(
        (item) => slugs.contains(
          jsonString(
            item['teacher_type_slug'],
            jsonString(item['role']),
          ).trim().toLowerCase().replaceAll('_', '-'),
        ),
      )
      .map((item) => jsonInt(item['teacher']))
      .whereType<int>()
      .toList(growable: false);
  return LearningGroup(
    id: id.toString(),
    remoteId: id,
    branchId: jsonOptionalPositiveInt(json['branch'], 'cohort.branch'),
    name: jsonString(json['name']),
    course: jsonString(json['department_name'], jsonString(json['level'])),
    level: jsonString(json['level']),
    studyMonth: rawStudyMonth,
    schedule: '',
    room: jsonString(json['default_room_name'], '—'),
    branch: jsonString(json['branch_name'], '—'),
    department: jsonString(json['department_name'], '—'),
    mainTeacher: jsonString(json['primary_teacher_name'], '—'),
    primaryTeacherId: jsonOptionalPositiveInt(
      json['primary_teacher'],
      'cohort.primary_teacher',
    ),
    teacherIds: teachers,
    assistantTeacherIds: teachersWithType(const {'assistant'}),
    coTeacherIds: teachersWithType(const {'co-teacher'}),
    capacity: jsonInt(json['capacity']),
    progress: null,
    attendance: null,
    nextLesson: '',
    students: const [],
    startDate: jsonDate(json['start_date']),
    endDate: jsonDate(json['end_date']),
    lessonCycleLength: cycleLength,
  );
}

StaffTask taskFromJson(Map<String, dynamic> json) {
  final id = jsonRequiredPositiveInt(json['id'], 'task.id');
  final status = jsonString(json['status'], 'open');
  final priority = jsonString(json['priority'], 'normal');
  final due = jsonDate(json['due_at']);
  final tags = <String>[
    if (jsonString(json['department_name']).isNotEmpty)
      jsonString(json['department_name']),
  ];
  final assigneePrincipal = json['assignee_principal'];
  final creatorPrincipal = json['created_by'];
  final safeAssignee = assigneePrincipal is Map
      ? assigneePrincipal.cast<Object?, Object?>()
      : const <Object?, Object?>{};
  final safeCreator = creatorPrincipal is Map
      ? creatorPrincipal.cast<Object?, Object?>()
      : const <Object?, Object?>{};
  return StaffTask(
    id: id.toString(),
    remoteId: id,
    title: jsonString(json['title']),
    description: jsonString(json['description']),
    due: due?.toIso8601String() ?? '',
    assignee: jsonString(json['assignee_name'], '—'),
    creator: jsonString(json['created_by_name'], '—'),
    stage: switch (status) {
      'in_progress' => TaskStage.inProgress,
      'blocked' => TaskStage.blocked,
      'done' => TaskStage.done,
      'cancelled' => TaskStage.cancelled,
      _ => TaskStage.todo,
    },
    highPriority: priority == 'high' || priority == 'urgent',
    tags: tags,
    rawStatus: status,
    assigneePrincipalKind: jsonString(safeAssignee['kind']),
    assigneePrincipalId: jsonInt(safeAssignee['id']),
    creatorPrincipalKind: jsonString(safeCreator['kind']),
    creatorPrincipalId: jsonInt(safeCreator['id']),
  );
}

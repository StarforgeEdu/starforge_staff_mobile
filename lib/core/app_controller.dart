import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/models.dart';
import '../data/remote_models.dart';
import '../data/workflow_models.dart';
import '../services/starforge_api.dart';

enum StaffRole {
  teacher,
  assistant,
  media,
  reception,
  sales,
  printer,
  cashier,
  staff,
}

enum AccentChoice {
  indigo(Color(0xFF6C63E8)),
  ocean(Color(0xFF087E8B)),
  coral(Color(0xFFE85D75)),
  forest(Color(0xFF2D8B73));

  const AccentChoice(this.color);
  final Color color;
}

enum AuthResult { success, invalid, restricted, unavailable, rateLimited }

class ConversationHistoryPage {
  const ConversationHistoryPage({
    required this.messages,
    required this.nextOlderPage,
  });

  const ConversationHistoryPage.empty()
    : messages = const [],
      nextOlderPage = null;

  final List<ChatMessage> messages;
  final int? nextOlderPage;
}

class AppController extends ChangeNotifier {
  AppController._(this._preferences, this._gateway);

  final SharedPreferences _preferences;
  final StarforgeGateway _gateway;

  Locale _locale = const Locale('uz');
  ThemeMode _themeMode = ThemeMode.system;
  AccentChoice _accent = AccentChoice.indigo;
  StaffRole _role = StaffRole.staff;
  bool _isSignedIn = false;
  bool _mustChangePassword = false;
  bool _restoring = false;
  String _displayName = '';
  String _roleDisplayName = '';
  StaffAccount? _account;
  String? _pendingCurrentPassword;
  List<LearningGroup> _groups = const [];
  bool _groupsLoaded = false;
  final Map<int, ChatContact> _messageThreadsById = {};
  final Map<int, ChatContact> _directMessageThreadsByUser = {};
  final Map<int, Future<ChatContact>> _messageThreadCreations = {};
  Set<int> _archivedMessageThreadIds = const {};

  static Future<AppController> load({
    StarforgeGateway? gateway,
    bool restoreSession = true,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final controller = AppController._(
      preferences,
      gateway ?? RemoteStarforgeGateway(),
    );
    controller._locale = Locale(preferences.getString('locale') ?? 'uz');
    controller._themeMode = ThemeMode.values.firstWhere(
      (mode) => mode.name == preferences.getString('themeMode'),
      orElse: () => ThemeMode.system,
    );
    controller._accent = AccentChoice.values.firstWhere(
      (accent) => accent.name == preferences.getString('accent'),
      orElse: () => AccentChoice.indigo,
    );
    if (controller._gateway case final RemoteStarforgeGateway remote) {
      remote.language = controller._locale.languageCode;
    }
    if (controller._gateway case final SessionExpirySource source) {
      source.addSessionExpiredListener(controller._expireSession);
    }
    if (restoreSession) await controller._restoreSession();
    return controller;
  }

  Locale get locale => _locale;
  ThemeMode get themeMode => _themeMode;
  AccentChoice get accent => _accent;
  StaffRole get role => _role;
  bool get isSignedIn => _isSignedIn;
  bool get mustChangePassword => _mustChangePassword;
  bool get restoring => _restoring;
  String get displayName =>
      _displayName.isEmpty ? 'Starforge Staff' : _displayName;
  String get roleDisplayName => _roleDisplayName;
  String get localizedRoleKey => switch (_role) {
    StaffRole.teacher => 'teacher',
    StaffRole.assistant => 'assistant',
    StaffRole.media => 'media',
    StaffRole.reception => 'reception',
    StaffRole.sales => 'sales',
    StaffRole.printer => 'printer',
    StaffRole.cashier => 'cashier',
    StaffRole.staff => 'staffMember',
  };
  StaffAccount? get account => _account;
  Set<String> get permissions => _account?.permissions ?? const {};
  String get branchName => _account?.branchName ?? '';
  String get departmentName => _account?.departmentName ?? '';
  List<LearningGroup> get groups => List.unmodifiable(_groups);
  bool get groupsLoaded => _groupsLoaded;

  bool can(String permission) => _account?.can(permission) ?? false;

  bool canMutate(String permission) =>
      _account?.readOnly != true && can(permission);

  bool get canTransferBranches =>
      canMutate('org:write') && _gateway is BranchTransferGateway;

  bool get hasTeachingWorkspace =>
      _account?.principalKind == 'teacher' ||
      can('cohorts:read') && can('attendance:read');

  Future<void> _restoreSession() async {
    _restoring = true;
    try {
      if (!await _gateway.hasSavedSession()) return;
      final account = await _gateway.currentAccount();
      if (!_isAllowedAccount(account)) {
        await _revokeRejectedSession();
        return;
      }
      await _applyAccount(account);
      _isSignedIn = true;
    } on StarforgeException catch (error) {
      // The remote gateway already clears an actually rejected token. Keep a
      // valid saved session through timeouts, offline starts and temporary 5xx
      // responses so the user can retry without signing in again.
      if (error.isAuthenticationFailure) await _gateway.clearSession();
    } catch (_) {
      // Secure storage/platform failures are transient until proven otherwise;
      // never destroy credentials merely because session restoration failed.
    } finally {
      _restoring = false;
    }
  }

  Future<void> setLocale(Locale value) async {
    _locale = value;
    if (_gateway case final RemoteStarforgeGateway remote) {
      remote.language = value.languageCode;
    }
    await _preferences.setString('locale', value.languageCode);
    notifyListeners();
    if (_isSignedIn && _account?.readOnly != true) {
      try {
        final updated = await _gateway.updateProfile({
          'preferred_language': value.languageCode,
        });
        _account = updated;
      } catch (_) {
        // The local preference remains useful while an account is temporarily
        // offline. A later successful profile update will reconcile it.
      }
    }
  }

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    await _preferences.setString('themeMode', value.name);
    notifyListeners();
  }

  Future<void> setAccent(AccentChoice value) async {
    _accent = value;
    await _preferences.setString('accent', value.name);
    notifyListeners();
  }

  Future<bool> rename(String value) async {
    final trimmed = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (trimmed.isEmpty) return false;
    final pieces = trimmed.split(' ');
    return updateName(
      firstName: pieces.first,
      middleName: pieces.length < 3
          ? ''
          : pieces.sublist(1, pieces.length - 1).join(' '),
      lastName: pieces.length == 1 ? '' : pieces.last,
    );
  }

  Future<bool> updateName({
    required String firstName,
    required String middleName,
    required String lastName,
  }) async {
    if (_account?.readOnly == true) return false;
    final normalizedFirst = firstName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalizedMiddle = middleName.trim().replaceAll(RegExp(r'\s+'), ' ');
    final normalizedLast = lastName.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalizedFirst.isEmpty) return false;
    try {
      final updated = await _gateway.updateProfile({
        'first_name': normalizedFirst,
        'middle_name': normalizedMiddle,
        'last_name': normalizedLast,
      });
      await _applyAccount(updated);
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<AuthResult> signIn({
    required String username,
    required String password,
  }) async {
    final normalized = username.trim();
    if (normalized.isEmpty || password.isEmpty) return AuthResult.invalid;
    try {
      final login = await _gateway.login(normalized, password);
      if (login.principalKind != 'teacher' && login.principalKind != 'staff') {
        await _revokeRejectedSession();
        return AuthResult.restricted;
      }
      final account = await _gateway.currentAccount();
      if (!_isAllowedAccount(account)) {
        await _revokeRejectedSession();
        return AuthResult.restricted;
      }
      await _applyAccount(account);
      _mustChangePassword =
          login.mustChangePassword || account.mustChangePassword;
      // Keep the current secret only for the short, mandatory-change flow.
      // Normal sessions must never retain a plaintext password in app state.
      _pendingCurrentPassword = _mustChangePassword ? password : null;
      _isSignedIn = true;
      _groups = const [];
      _groupsLoaded = false;
      notifyListeners();
      return AuthResult.success;
    } on StarforgeException catch (error) {
      if (error.statusCode == 429 || error.code.contains('rate')) {
        return AuthResult.rateLimited;
      }
      if (error.isAuthenticationFailure ||
          error.statusCode == 400 ||
          error.statusCode == 422) {
        return AuthResult.invalid;
      }
      return AuthResult.unavailable;
    } catch (_) {
      return AuthResult.unavailable;
    }
  }

  Future<bool> completeRequiredPasswordChange({
    String? currentPassword,
    required String newPassword,
  }) async {
    final oldPassword = currentPassword?.trim().isNotEmpty == true
        ? currentPassword!
        : _pendingCurrentPassword;
    if (oldPassword == null || oldPassword.isEmpty || newPassword.length < 10) {
      return false;
    }
    try {
      await _gateway.changePassword(oldPassword, newPassword);
      final updated = await _gateway.currentAccount();
      await _applyAccount(updated);
      _mustChangePassword = false;
      _pendingCurrentPassword = null;
      notifyListeners();
      return true;
    } catch (_) {
      return false;
    }
  }

  Future<void> signOut() async {
    _expireSession();
    try {
      await _gateway.logout();
    } catch (_) {
      await _gateway.clearSession();
    }
  }

  Future<List<LearningGroup>> loadGroups({bool refresh = false}) async {
    if (_groupsLoaded && !refresh) return groups;
    final loaded = await _gateway.groups();
    final account = _account;
    var visible = loaded;
    if (account?.principalKind == 'teacher') {
      visible = loaded
          .where(
            (group) =>
                group.remoteId == null ||
                group.primaryTeacherId == account!.id ||
                group.teacherIds.contains(account.id),
          )
          .toList(growable: false);
    }
    _groups = visible;
    if (account?.principalKind == 'teacher') {
      final isPrimary = visible.any(
        (group) => group.primaryTeacherId == account!.id,
      );
      final isAssistant = visible.any(
        (group) =>
            group.assistantTeacherIds.contains(account!.id) ||
            group.coTeacherIds.contains(account.id),
      );
      if (!isPrimary && isAssistant) {
        _role = StaffRole.assistant;
      } else if (_role == StaffRole.assistant && isPrimary) {
        _role = StaffRole.teacher;
      }
    }
    _groupsLoaded = true;
    notifyListeners();
    return groups;
  }

  Future<LearningGroup> loadGroupDetails(LearningGroup group) async {
    final remoteId = group.remoteId;
    if (remoteId == null) return group;
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final responses = await Future.wait<Object?>([
      can('students:read')
          ? _gateway.studentsForGroup(remoteId)
          : Future.value(const <Student>[]),
      can('attendance:read')
          ? _gateway.attendanceForMonth(remoteId, currentMonth)
          : Future.value(AttendanceMonth.empty(currentMonth)),
      can('attendance:read')
          ? _gateway.attendanceForMonth(remoteId, nextMonth)
          : Future.value(AttendanceMonth.empty(nextMonth)),
    ]);
    final students = responses[0] as List<Student>;
    final attendance = responses[1] as AttendanceMonth;
    final nextMonthAttendance = responses[2] as AttendanceMonth;
    final attendanceByStudent = {
      for (final summary in attendance.students)
        summary.studentId.toString(): summary.percentPresent / 100,
    };
    final enrichedStudents = students
        .map(
          (student) => attendanceByStudent.containsKey(student.id)
              ? student.copyWith(attendance: attendanceByStudent[student.id])
              : student,
        )
        .toList(growable: false);
    final next =
        [...attendance.lessons, ...nextMonthAttendance.lessons]
            .where(
              (lesson) => lesson.startsAt.isAfter(now) && !lesson.isCancelled,
            )
            .toList()
          ..sort((a, b) => a.startsAt.compareTo(b.startsAt));
    final updated = group.copyWith(
      students: enrichedStudents,
      attendance: attendance.rate / 100,
      nextLesson: next.isEmpty ? '' : next.first.startsAt.toIso8601String(),
    );
    _groups = _groups
        .map((item) => item.id == group.id ? updated : item)
        .toList();
    notifyListeners();
    return updated;
  }

  Future<List<AssignedStudentInfo>> loadAssignedStudents({
    bool refresh = false,
  }) async {
    if (!can('students:read')) return const [];
    final assignedGroups = await loadGroups(refresh: refresh);
    final detailed = await Future.wait(assignedGroups.map(loadGroupDetails));
    final unique = <String, AssignedStudentInfo>{};
    for (final group in detailed) {
      for (final student in group.students) {
        unique.putIfAbsent(
          student.id,
          () => AssignedStudentInfo(student: student, group: group),
        );
      }
    }
    final students = unique.values.toList(growable: false)
      ..sort((a, b) => a.student.name.compareTo(b.student.name));
    return students;
  }

  StaffWorkflowGateway _requireWorkflow(
    String permission, {
    bool write = false,
  }) {
    if (write ? !canMutate(permission) : !can(permission)) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This workspace is unavailable for this account.',
        statusCode: 403,
      );
    }
    final gateway = _gateway;
    if (gateway is! StaffWorkflowGateway) {
      throw const StarforgeException(
        code: 'feature_unavailable',
        message: 'This workspace is not available in this app version.',
      );
    }
    return gateway as StaffWorkflowGateway;
  }

  Future<List<StaffRequestInfo>> loadStaffRequests() =>
      _requireWorkflow('approvals:read').staffRequests();

  Future<StaffRequestInfo> createStaffRequest({
    required String kind,
    required String title,
    required String description,
    double? amount,
  }) {
    final branchId = _account?.memberships
        .map((item) => item.branchId)
        .whereType<int>()
        .firstOrNull;
    return _requireWorkflow('approvals:write', write: true).createStaffRequest(
      kind: kind,
      title: title,
      description: description,
      branchId: branchId,
      amount: amount,
    );
  }

  Future<StaffRequestInfo> cancelStaffRequest(int requestId) =>
      _requireWorkflow(
        'approvals:write',
        write: true,
      ).cancelStaffRequest(requestId);

  Future<List<StaffFormInfo>> loadStaffForms() =>
      _requireWorkflow('forms:read').staffForms();

  Future<StaffFormInfo> loadStaffForm(int formId) =>
      _requireWorkflow('forms:read').staffForm(formId);

  Future<void> submitStaffForm(int formId, Map<int, Object?> answers) =>
      _requireWorkflow(
        'forms:read',
        write: true,
      ).submitStaffForm(formId, answers);

  Future<List<StaffAchievementInfo>> loadStaffAchievements() =>
      _requireWorkflow('achievements:read').staffAchievements();

  Future<StaffAchievementInfo> createGroupAchievement({
    required int cohortId,
    required String name,
    required String description,
    required String emoji,
  }) => _requireWorkflow('achievements:write', write: true)
      .createGroupAchievement(
        cohortId: cohortId,
        name: name,
        description: description,
        emoji: emoji,
      );

  Future<void> grantStaffAchievement({
    required int achievementId,
    required int studentId,
    required String note,
  }) =>
      _requireWorkflow('achievements:write', write: true).grantStaffAchievement(
        achievementId: achievementId,
        studentId: studentId,
        note: note,
      );

  Future<List<StaffReportInfo>> loadStaffReports() =>
      _requireWorkflow('reports:read').staffReports();

  Future<List<StaffReportRunInfo>> loadStaffReportRuns() =>
      _requireWorkflow('reports:read').staffReportRuns();

  Future<StaffReportRunInfo> createStaffReportRun({
    required String reportKey,
    required String format,
    required Map<String, Object?> params,
    List<int> recipientIds = const [],
  }) => _requireWorkflow('reports:write', write: true).createStaffReportRun(
    reportKey: reportKey,
    format: format,
    params: params,
    recipientIds: recipientIds,
  );

  BranchTransferGateway _requireBranchTransfer() {
    if (!canTransferBranches) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'Branch movement is unavailable for this account.',
        statusCode: 403,
      );
    }
    return _gateway as BranchTransferGateway;
  }

  Future<List<BranchChoiceInfo>> loadTransferBranches({
    required int currentBranchId,
  }) async {
    final branches = await _requireBranchTransfer().transferBranches();
    return branches
        .where((branch) => branch.id != currentBranchId && branch.isActive)
        .toList(growable: false);
  }

  Future<void> transferGroupBranch({
    required LearningGroup group,
    required int destinationBranchId,
    required String reason,
  }) async {
    final groupId = group.remoteId;
    final currentBranchId = group.branchId;
    if (groupId == null ||
        currentBranchId == null ||
        destinationBranchId == currentBranchId ||
        reason.trim().isEmpty) {
      throw const StarforgeException(
        code: 'validation_error',
        message: 'Choose another branch and record a reason.',
      );
    }
    await _requireBranchTransfer().transferBranchSubject(
      subjectKind: 'cohort',
      subjectId: groupId,
      toBranchId: destinationBranchId,
      reason: reason,
      confirmImpacts: true,
    );
    _groupsLoaded = false;
    await loadGroups(refresh: true);
  }

  Future<void> transferStudentBranch({
    required Student student,
    required LearningGroup group,
    required int destinationBranchId,
    required String reason,
  }) async {
    final studentId = int.tryParse(student.id);
    final currentBranchId = group.branchId;
    if (studentId == null ||
        studentId <= 0 ||
        currentBranchId == null ||
        destinationBranchId == currentBranchId ||
        reason.trim().isEmpty) {
      throw const StarforgeException(
        code: 'validation_error',
        message: 'Choose another branch and record a reason.',
      );
    }
    await _requireBranchTransfer().transferBranchSubject(
      subjectKind: 'student',
      subjectId: studentId,
      toBranchId: destinationBranchId,
      reason: reason,
      confirmImpacts: true,
    );
    _groups = _groups
        .map(
          (item) => item.id == group.id
              ? item.copyWith(
                  students: item.students
                      .where((candidate) => candidate.id != student.id)
                      .toList(growable: false),
                )
              : item,
        )
        .toList(growable: false);
    notifyListeners();
  }

  Future<StudentLeadershipInfo?> loadStudentLeadership(Student student) {
    final id = int.tryParse(student.id);
    final gateway = _gateway;
    if (id == null ||
        id <= 0 ||
        !can('students:read') ||
        gateway is! StudentLeadershipGateway) {
      return Future.value();
    }
    return (gateway as StudentLeadershipGateway).studentLeadershipProfile(id);
  }

  Future<AttendanceMonth> loadAttendanceMonth(
    LearningGroup group,
    DateTime month,
  ) async {
    final id = group.remoteId;
    if (id == null || !can('attendance:read')) {
      return AttendanceMonth.empty(month);
    }
    return _gateway.attendanceForMonth(id, month);
  }

  Future<List<ExamInfo>> loadExams(LearningGroup group) async {
    final id = group.remoteId;
    if (id == null || !can('academics:read')) return const [];
    return _gateway.examsForGroup(id);
  }

  Future<CohortCycleProgressInfo?> loadCohortCycleProgress(
    LearningGroup group,
  ) {
    final id = group.remoteId;
    final gateway = _gateway;
    if (id == null ||
        _account?.principalKind != 'teacher' ||
        !can('cohorts:read') ||
        gateway is! CohortCycleProgressGateway) {
      return Future.value();
    }
    return (gateway as CohortCycleProgressGateway).cohortCycleProgress(id);
  }

  bool canEditCohortTeachingProgress(LearningGroup group) {
    final account = _account;
    return account != null &&
        account.principalKind == 'teacher' &&
        account.id == group.primaryTeacherId &&
        canMutate('academics:write') &&
        group.remoteId != null &&
        _gateway is CohortTeachingProgressGateway;
  }

  Future<LearningGroup> updateCohortTeachingProgress({
    required LearningGroup group,
    required String level,
    required int studyMonth,
    required int lessonCycleLength,
  }) async {
    _requireMutable('academics:write');
    final id = group.remoteId;
    final gateway = _gateway;
    if (id == null || !canEditCohortTeachingProgress(group)) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This group progress cannot be changed by this account.',
        statusCode: 403,
      );
    }
    final info = await (gateway as CohortTeachingProgressGateway)
        .updateCohortTeachingProgress(
          cohortId: id,
          level: level,
          studyMonth: studyMonth,
          lessonCycleLength: lessonCycleLength,
        );
    final updated = group.copyWith(
      level: info.level,
      studyMonth: info.studyMonth,
      lessonCycleLength: info.lessonCycleLength,
    );
    _groups = _groups
        .map((item) => item.remoteId == id ? updated : item)
        .toList(growable: false);
    notifyListeners();
    return updated;
  }

  Future<List<ExamResultInfo>> loadExamResults(int examId) {
    if (examId <= 0 || !can('academics:read')) return Future.value(const []);
    return _gateway.examResults(examId);
  }

  Future<void> saveAttendance(
    int lessonId,
    List<Map<String, Object?>> records,
  ) async {
    _requireMutable('attendance:write');
    if (lessonId <= 0 || records.isEmpty) {
      throw const StarforgeException(
        code: 'invalid_attendance',
        message: 'Attendance information is incomplete.',
      );
    }
    await _gateway.markAttendance(lessonId, records);
  }

  Future<TeacherDashboardData?> loadTeacherDashboard() async {
    if (_account?.principalKind == 'teacher') {
      return _gateway.teacherDashboard();
    }
    if (!hasTeachingWorkspace) return null;

    // Assistants can legitimately be assigned teaching access without owning a
    // TeacherProfile, so the teacher-only dashboard endpoint rejects them. Build
    // the same truthful summary from their already-scoped cohort APIs.
    final groups = await loadGroups();
    final now = DateTime.now();
    final currentMonth = DateTime(now.year, now.month);
    final nextMonth = DateTime(now.year, now.month + 1);
    final studentIds = <String>{};
    final lessons = <LessonInfo>[];
    final canReadStudents = can('students:read');
    final summaries = await Future.wait(
      groups.where((group) => group.remoteId != null).map((group) async {
        final groupId = group.remoteId!;
        return Future.wait<Object>([
          canReadStudents
              ? _gateway.studentsForGroup(groupId)
              : Future.value(const <Student>[]),
          _gateway.attendanceForMonth(groupId, currentMonth),
          _gateway.attendanceForMonth(groupId, nextMonth),
        ]);
      }),
    );
    for (final summary in summaries) {
      studentIds.addAll((summary[0] as List<Student>).map((item) => item.id));
      lessons.addAll((summary[1] as AttendanceMonth).lessons);
      lessons.addAll((summary[2] as AttendanceMonth).lessons);
    }
    lessons.removeWhere(
      (lesson) => !lesson.startsAt.isAfter(now) || lesson.isCancelled,
    );
    lessons.sort((left, right) => left.startsAt.compareTo(right.startsAt));
    final meetings = can('meetings:read')
        ? await _gateway.upcomingMeetings()
        : const <MeetingInfo>[];
    return TeacherDashboardData(
      groupsCount: groups.length,
      studentsCount: canReadStudents ? studentIds.length : null,
      nextLessons: lessons,
      nextMeeting: meetings.isEmpty
          ? const <String, dynamic>{}
          : meetings.first.toDashboardMap(),
    );
  }

  Future<List<FeatureAvailabilityInfo>> loadFeatureAvailability() =>
      _gateway.featureAvailability();

  Future<List<StaffTask>> loadTasks({bool mineOnly = false}) {
    if (!can('tasks:read')) return Future.value(const []);
    return _gateway.tasks(mineOnly: mineOnly);
  }

  Future<StaffTask> createTask({
    required String title,
    required String description,
    required bool highPriority,
    DateTime? dueAt,
  }) {
    final account = _account;
    if (account == null || !canMutate('tasks:write')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot create tasks.',
      );
    }
    return _gateway.createTask(
      title: title,
      description: description,
      highPriority: highPriority,
      principalKind: account.principalKind,
      principalId: account.id,
      dueAt: dueAt,
    );
  }

  Future<StaffTask> transitionTask(StaffTask task, TaskStage stage) {
    _requireMutable('tasks:write');
    final account = _account;
    final isAssignee =
        account != null &&
        task.isAssignedTo(
          principalKind: account.principalKind,
          principalId: account.id,
        );
    if (!isAssignee &&
        !can('tasks:transition_any') &&
        !can('tasks:assign_any')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot change this task.',
        statusCode: 403,
      );
    }
    final remoteId = task.remoteId;
    if (remoteId == null) return Future.value(task.copyWith(stage: stage));
    final status = switch (stage) {
      TaskStage.todo => 'open',
      TaskStage.inProgress => 'in_progress',
      TaskStage.blocked => 'blocked',
      TaskStage.cancelled => 'cancelled',
      TaskStage.done => 'done',
    };
    return _gateway.transitionTask(remoteId, status);
  }

  Future<MessagingWorkspace> loadMessagingWorkspace() async {
    if (!can('messaging:read')) return const MessagingWorkspace.empty();
    final responses = await Future.wait<Object?>([
      _gateway.messageContacts(),
      _gateway.messageThreads(),
    ]);
    final remoteContacts = responses[0] as List<MessageContactInfo>;
    final remoteThreads = responses[1] as List<MessageThreadInfo>;
    final contacts = remoteContacts
        .map(_contactFromDirectory)
        .toList(growable: false);
    final byUser = {
      for (final contact in contacts) contact.remoteUserId!: contact,
    };
    final threads = remoteThreads
        .map((thread) => _contactFromThread(thread, byUser))
        .toList(growable: false);
    _messageThreadsById
      ..clear()
      ..addEntries(
        threads
            .where((thread) => thread.threadId != null)
            .map((thread) => MapEntry(thread.threadId!, thread)),
      );
    _directMessageThreadsByUser
      ..clear()
      ..addEntries(
        threads
            .where(
              (thread) =>
                  thread.participantUserIds.length == 1 &&
                  thread.participantUserIds.first > 0,
            )
            .map((thread) => MapEntry(thread.participantUserIds.first, thread)),
      );
    return MessagingWorkspace(threads: threads, contacts: contacts);
  }

  Future<ChatContact> prepareConversation(ChatContact requested) async {
    if (!can('messaging:read')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'Messaging is not available for this account.',
      );
    }
    if (requested.threadId case final threadId?) {
      return _messageThreadsById[threadId] ?? requested;
    }
    final workspace = await loadMessagingWorkspace();
    ChatContact? directoryContact;
    final requestedProfileId =
        requested.profileId ?? int.tryParse(requested.id);
    for (final contact in workspace.contacts) {
      final matchesUser =
          requested.remoteUserId != null &&
          contact.remoteUserId == requested.remoteUserId;
      final matchesProfile =
          requestedProfileId != null &&
          contact.profileId == requestedProfileId &&
          (requested.principalKind.isEmpty ||
              contact.principalKind == requested.principalKind);
      if (matchesUser || matchesProfile) {
        directoryContact = contact;
        break;
      }
    }
    if (directoryContact == null) {
      throw const StarforgeException(
        code: 'contact_unavailable',
        message: 'This person is not available in your conversations.',
      );
    }
    return _directMessageThreadsByUser[directoryContact.remoteUserId] ??
        directoryContact;
  }

  Future<List<ChatMessage>> loadConversation(ChatContact contact) async {
    return (await loadConversationPage(contact)).messages;
  }

  Future<ConversationHistoryPage> loadConversationPage(
    ChatContact contact,
  ) async {
    final resolved = _resolvedMessageThread(contact);
    final threadId = resolved?.threadId;
    if (threadId == null || !can('messaging:read')) {
      return const ConversationHistoryPage.empty();
    }
    final MessageHistoryPageInfo page;
    if (_gateway case final PaginatedMessageHistoryGateway paginated) {
      page = await paginated.recentMessagesForThread(threadId);
    } else {
      final messages = await _gateway.messagesForThread(threadId);
      page = MessageHistoryPageInfo(
        messages: messages,
        nextOlderPage: null,
        total: messages.length,
      );
    }
    await _acknowledgeMessages(threadId, page.messages);
    return ConversationHistoryPage(
      messages: page.messages
          .map((message) => _chatMessageFromRemote(message, resolved))
          .toList(growable: false),
      nextOlderPage: page.nextOlderPage,
    );
  }

  Future<ConversationHistoryPage> loadOlderConversationPage(
    ChatContact contact, {
    required int page,
  }) async {
    final resolved = _resolvedMessageThread(contact);
    final threadId = resolved?.threadId;
    if (threadId == null ||
        page < 1 ||
        !can('messaging:read') ||
        _gateway is! PaginatedMessageHistoryGateway) {
      return const ConversationHistoryPage.empty();
    }
    final history = await (_gateway as PaginatedMessageHistoryGateway)
        .olderMessagesForThread(threadId, page: page);
    return ConversationHistoryPage(
      messages: history.messages
          .map((message) => _chatMessageFromRemote(message, resolved))
          .toList(growable: false),
      nextOlderPage: history.nextOlderPage,
    );
  }

  Future<List<ChatMessage>> loadConversationUpdates(
    ChatContact contact, {
    required int afterId,
  }) async {
    final resolved = _resolvedMessageThread(contact);
    final threadId = resolved?.threadId;
    if (threadId == null || !can('messaging:read')) return const [];
    final messages = await _gateway.messagesForThread(
      threadId,
      afterId: afterId,
    );
    await _acknowledgeMessages(threadId, messages);
    return messages
        .map((message) => _chatMessageFromRemote(message, resolved))
        .toList(growable: false);
  }

  Future<MessageRealtimeConnection?> connectConversationRealtime(
    ChatContact contact,
  ) {
    final resolved = _resolvedMessageThread(contact);
    final threadId = resolved?.threadId;
    if (threadId == null ||
        !can('messaging:read') ||
        _gateway is! RealtimeMessageGateway) {
      return Future.value();
    }
    return (_gateway as RealtimeMessageGateway).connectMessageRealtime(
      threadId,
    );
  }

  Future<MessageEventPageInfo?> recoverConversationEvents(
    ChatContact contact, {
    required int after,
  }) {
    final resolved = _resolvedMessageThread(contact);
    final threadId = resolved?.threadId;
    if (threadId == null ||
        after < 0 ||
        !can('messaging:read') ||
        _gateway is! RealtimeMessageGateway) {
      return Future.value();
    }
    return (_gateway as RealtimeMessageGateway).recoverMessageEvents(
      threadId,
      after: after,
    );
  }

  int loadConversationEventCursor(ChatContact contact) {
    final account = _account;
    final threadId = _resolvedMessageThread(contact)?.threadId;
    if (account == null || threadId == null) return 0;
    final saved = _preferences.getInt(_messageCursorKey(account, threadId));
    return saved != null && saved >= 0 ? saved : 0;
  }

  Future<void> saveConversationEventCursor(
    ChatContact contact,
    int cursor,
  ) async {
    final account = _account;
    final threadId = _resolvedMessageThread(contact)?.threadId;
    if (account == null || threadId == null || cursor < 0) return;
    await _preferences.setInt(_messageCursorKey(account, threadId), cursor);
  }

  Future<void> handleMessagingRealtimeClosure(int? closeCode) async {
    if (closeCode != 4401 || !_isSignedIn) return;
    await _gateway.clearSession();
    _expireSession();
  }

  Future<void> _acknowledgeMessages(
    int threadId,
    List<MessageInfo> messages,
  ) async {
    if (messages.isEmpty || _account?.readOnly == true) return;
    try {
      await _gateway.markMessageThreadRead(
        threadId,
        throughMessageId: messages
            .map((message) => message.id)
            .reduce((left, right) => left > right ? left : right),
      );
    } catch (_) {
      // Reading remains available when acknowledgement is temporarily delayed.
    }
  }

  Future<ChatMessage> sendTextMessage(ChatContact contact, String text) async {
    if (!canMutate('messaging:write')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot send messages.',
      );
    }
    final resolved = await _ensureMessageThread(contact);
    final threadId = resolved.threadId!;
    final sent = await _gateway.sendMessage(threadId: threadId, body: text);
    return _chatMessageFromRemote(sent, resolved);
  }

  Future<ChatMessage> sendAttachmentMessage({
    required ChatContact contact,
    required String filePath,
    required String filename,
    required String contentType,
  }) async {
    if (!canMutate('messaging:write')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot send messages.',
      );
    }
    final resolved = await _ensureMessageThread(contact);
    final threadId = resolved.threadId!;
    final key = await _gateway.uploadMessageAttachment(
      filePath: filePath,
      filename: filename,
      contentType: contentType,
    );
    final sent = await _gateway.sendMessage(
      threadId: threadId,
      attachments: [key],
    );
    return _chatMessageFromRemote(sent, resolved);
  }

  Future<ChatMessage> prepareMessageAttachment(
    ChatContact contact,
    ChatMessage message,
  ) async {
    if (message.attachmentKey.isEmpty) return message;
    final resolved = _resolvedMessageThread(contact);
    final threadId = resolved?.threadId;
    if (threadId == null) return message;
    final url = await _gateway.messageAttachmentUrl(
      threadId: threadId,
      key: message.attachmentKey,
    );
    return message.copyWith(attachmentUrl: url);
  }

  bool isMessageThreadArchived(int? threadId) =>
      threadId != null && _archivedMessageThreadIds.contains(threadId);

  Future<void> setMessageThreadArchived(int threadId, bool archived) async {
    final updated = {..._archivedMessageThreadIds};
    if (archived) {
      updated.add(threadId);
    } else {
      updated.remove(threadId);
    }
    _archivedMessageThreadIds = Set.unmodifiable(updated);
    final account = _account;
    if (account != null) {
      final values = updated.map((id) => '$id').toList()..sort();
      await _preferences.setStringList(_messageArchiveKey(account), values);
    }
    notifyListeners();
  }

  Future<LibraryWorkspace> loadLibrary() async {
    if (!can('content:read')) return const LibraryWorkspace.empty();
    final responses = await Future.wait<Object?>([
      _gateway.contentFiles(),
      _gateway.libraryMaterials(),
      _gateway.contentFolders(),
    ]);
    final files = responses[0] as List<ContentFileInfo>;
    final materials = responses[1] as List<LibraryMaterialInfo>;
    final remoteFolders = responses[2] as List<ContentFolderInfo>;
    final resources =
        <LibraryResource>[
          ...files.map(_libraryFileFromRemote),
          ...materials.map(_libraryMaterialFromRemote),
        ]..sort((a, b) {
          final left = a.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          final right = b.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
          return right.compareTo(left);
        });
    final folders = remoteFolders
        .map(
          (folder) => LibraryFolder(
            id: folder.id,
            name: folder.name,
            libraryName: folder.libraryName,
            parentName: folder.parentName,
            visibility: folder.libraryVisibility,
            cohortId: folder.libraryCohortId,
            cohortName: folder.libraryCohortName,
          ),
        )
        .toList(growable: false);
    return LibraryWorkspace(resources: resources, folders: folders);
  }

  Future<LibraryResource> prepareLibraryResource(
    LibraryResource resource,
  ) async {
    final fileId = resource.remoteFileId;
    if (fileId == null || resource.remoteUrl.isNotEmpty) return resource;
    final url = await _gateway.contentFileUrl(fileId);
    return resource.copyWith(remoteUrl: url);
  }

  Future<void> trackLibraryResource(LibraryResource resource) async {
    final fileId = resource.remoteFileId;
    if (fileId == null) return;
    await _gateway.trackContentFileView(fileId);
  }

  Future<LibraryResource> approveLibraryResource(
    LibraryResource resource,
  ) async {
    final fileId = resource.remoteFileId;
    if (fileId == null || !canMutate('content:approve')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot approve this resource.',
      );
    }
    final approved = await _gateway.approveContentFileAsTeacher(fileId);
    return _libraryFileFromRemote(
      approved,
    ).copyWith(remoteUrl: resource.remoteUrl);
  }

  Future<void> uploadLibraryResource({
    required String filePath,
    required String filename,
    required String contentType,
    required String title,
    required int folderId,
    required String audience,
    required bool downloadable,
  }) async {
    if (_account?.principalKind != 'teacher' || !canMutate('content:write')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot upload learning resources.',
      );
    }
    await _gateway.uploadContentFile(
      filePath: filePath,
      filename: filename,
      contentType: contentType,
      title: title,
      folderId: folderId,
      audience: audience,
      downloadable: downloadable,
    );
  }

  Future<PrintWorkspace> loadPrintWorkspace() async {
    if (!can('printing:read')) return const PrintWorkspace.empty();
    final responses = await Future.wait<Object?>([
      _gateway.printers(),
      _gateway.printJobs(),
    ]);
    final remotePrinters = responses[0] as List<PrinterInfo>;
    final remoteJobs = responses[1] as List<PrintJobInfo>;
    final busyPrinterIds = remoteJobs
        .where((job) => const {'picked', 'printing'}.contains(job.status))
        .map((job) => job.printerId)
        .whereType<int>()
        .toSet();
    return PrintWorkspace(
      printers: remotePrinters
          .map(
            (printer) => PrinterDevice(
              id: printer.id.toString(),
              name: printer.name,
              location: printer.modelName,
              toner: printer.active ? 1 : 0,
              paper: printer.paperSizes.join(', '),
              isBusy: busyPrinterIds.contains(printer.id),
              isOffline: !printer.active,
              supportsColor: printer.supportsColor,
              supportsDuplex: printer.supportsDuplex,
              branchId: printer.branchId,
            ),
          )
          .toList(growable: false),
      jobs: remoteJobs
          .map(
            (job) => StaffPrintJob(
              id: job.id,
              status: job.status,
              source: job.source,
              pages: job.pages,
              copies: job.copies,
              color: job.color,
              duplex: job.duplex,
              createdAt: job.createdAt,
              finishedAt: job.finishedAt,
              scheduledFor: job.scheduledFor,
            ),
          )
          .toList(growable: false),
    );
  }

  Future<void> submitPrintJob({
    required String filePath,
    required String filename,
    required String contentType,
    required int sizeBytes,
    required PrinterDevice printer,
    required int copies,
    required bool color,
    required bool duplex,
    DateTime? scheduledFor,
  }) async {
    if (_account?.readOnly == true || !can('printing:write')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot submit print jobs.',
        statusCode: 403,
      );
    }
    final printerId = int.tryParse(printer.id);
    final branchId = printer.branchId;
    if (printerId == null ||
        printerId <= 0 ||
        branchId == null ||
        branchId <= 0 ||
        printer.isOffline ||
        sizeBytes <= 0 ||
        copies < 1 ||
        copies > 100) {
      throw const StarforgeException(
        code: 'printer_unavailable',
        message: 'The selected printer is unavailable.',
      );
    }
    _assertPrintCapabilities(printer, color: color, duplex: duplex);
    await _gateway.submitUploadedPrintJob(
      filePath: filePath,
      filename: filename,
      contentType: contentType,
      sizeBytes: sizeBytes,
      branchId: branchId,
      printerId: printerId,
      copies: copies,
      color: color,
      duplex: duplex,
      scheduledFor: scheduledFor,
    );
  }

  Future<void> submitLibraryPrintJob({
    required LibraryResource resource,
    required PrinterDevice printer,
    required int copies,
    required bool color,
    required bool duplex,
    DateTime? scheduledFor,
  }) async {
    if (_account?.readOnly == true || !can('printing:write')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot submit print jobs.',
        statusCode: 403,
      );
    }
    final printerId = int.tryParse(printer.id);
    final fileId = resource.remoteFileId;
    if (printerId == null ||
        printerId <= 0 ||
        printer.isOffline ||
        copies < 1 ||
        copies > 100) {
      throw const StarforgeException(
        code: 'printer_unavailable',
        message: 'The selected printer is unavailable.',
      );
    }
    _assertPrintCapabilities(printer, color: color, duplex: duplex);
    if (fileId == null ||
        fileId <= 0 ||
        !resource.downloadable ||
        resource.status != 'clean') {
      throw const StarforgeException(
        code: 'content_unavailable',
        message: 'This resource is not available for printing.',
      );
    }
    await _gateway.submitLibraryPrintJob(
      fileId: fileId,
      printerId: printerId,
      copies: copies,
      color: color,
      duplex: duplex,
      scheduledFor: scheduledFor,
    );
  }

  void _assertPrintCapabilities(
    PrinterDevice printer, {
    required bool color,
    required bool duplex,
  }) {
    if (color && !printer.supportsColor) {
      throw const StarforgeException(
        code: 'printer_color_unsupported',
        message: 'The selected printer does not support color printing.',
      );
    }
    if (duplex && !printer.supportsDuplex) {
      throw const StarforgeException(
        code: 'printer_duplex_unsupported',
        message: 'The selected printer does not support double-sided printing.',
      );
    }
  }

  Future<List<PayrollPayslipInfo>> loadOwnPayslips() {
    if (_account?.principalKind != 'teacher') return Future.value(const []);
    return _gateway.ownPayslips();
  }

  Future<List<ComplianceRuleInfo>> loadOwnRules() {
    if (!can('rulebook:read')) return Future.value(const []);
    return _gateway.ownRules();
  }

  Future<void> acknowledgeRule(int ruleId) {
    if (!canMutate('rulebook:read')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This account cannot acknowledge this rule.',
        statusCode: 403,
      );
    }
    return _gateway.acknowledgeRule(ruleId);
  }

  Future<List<NotificationInfo>> loadNotifications() {
    if (!can('notifications:read')) return Future.value(const []);
    return _gateway.notifications();
  }

  Future<int> loadUnreadNotificationCount() {
    if (!can('notifications:read')) return Future.value(0);
    return _gateway.unreadNotificationCount();
  }

  Future<void> markNotificationRead(int notificationId) {
    _requireMutable('notifications:read');
    return _gateway.markNotificationRead(notificationId);
  }

  Future<void> markAllNotificationsRead() {
    _requireMutable('notifications:read');
    return _gateway.markAllNotificationsRead();
  }

  Future<List<NotificationPreferenceInfo>> loadNotificationPreferences() {
    if (!can('notifications:read')) return Future.value(const []);
    return _gateway.notificationPreferences();
  }

  Future<List<NotificationPreferenceInfo>> updateNotificationPreferences(
    List<NotificationPreferenceInfo> preferences,
  ) {
    if (_account?.readOnly == true) {
      throw const StarforgeException(
        code: 'read_only',
        message: 'This session is read-only.',
      );
    }
    if (!can('notifications:read')) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'Notification preferences are unavailable for this account.',
        statusCode: 403,
      );
    }
    return _gateway.updateNotificationPreferences(preferences);
  }

  Future<List<MeetingInfo>> loadUpcomingMeetings() {
    if (!can('meetings:read')) return Future.value(const []);
    return _gateway.upcomingMeetings();
  }

  Future<List<CrmLeadInfo>> loadCrmLeads() {
    if (!can('crm:read')) return Future.value(const []);
    return _gateway.crmLeads();
  }

  Future<List<FinanceInvoiceInfo>> loadFinanceInvoices() {
    if (!can('finance:read')) return Future.value(const []);
    return _gateway.financeInvoices();
  }

  Future<List<CashierShiftInfo>> loadOwnCashierShifts() {
    if (!can('finance:read')) return Future.value(const []);
    return _gateway.ownCashierShifts();
  }

  Future<bool> submitStudentRequest({
    required String action,
    required LearningGroup group,
    required Student student,
    required String description,
  }) async {
    if (!canMutate('approvals:write') || description.trim().isEmpty) {
      return false;
    }
    try {
      final membershipBranchIds =
          _account?.memberships
              .map((membership) => membership.branchId)
              .whereType<int>()
              .toSet() ??
          const <int>{};
      await _gateway.submitStudentRequest(
        action: action,
        group: group,
        student: student,
        description: description,
        branchId:
            group.branchId ??
            (membershipBranchIds.length == 1
                ? membershipBranchIds.single
                : null),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  ChatContact? _resolvedMessageThread(ChatContact contact) {
    final threadId = contact.threadId;
    if (threadId != null) return _messageThreadsById[threadId] ?? contact;
    final userId = contact.remoteUserId;
    return userId == null ? null : _directMessageThreadsByUser[userId];
  }

  Future<ChatContact> _ensureMessageThread(ChatContact contact) async {
    final existing = _resolvedMessageThread(contact);
    if (existing?.threadId != null) return existing!;
    final prepared = await prepareConversation(contact);
    final preparedThread = _resolvedMessageThread(prepared);
    if (preparedThread?.threadId != null) return preparedThread!;
    final userId = prepared.remoteUserId;
    if (userId == null) {
      throw const StarforgeException(
        code: 'contact_unavailable',
        message: 'This person is not available in your conversations.',
      );
    }
    final inFlight = _messageThreadCreations[userId];
    if (inFlight != null) return inFlight;
    final creation = () async {
      final created = await _gateway.createMessageThread(
        participantUserId: userId,
      );
      final mapped = _contactFromThread(created, {userId: prepared});
      final threadId = mapped.threadId;
      if (threadId != null) _messageThreadsById[threadId] = mapped;
      _directMessageThreadsByUser[userId] = mapped;
      return mapped;
    }();
    _messageThreadCreations[userId] = creation;
    try {
      return await creation;
    } finally {
      _messageThreadCreations.remove(userId);
    }
  }

  String _messageArchiveKey(StaffAccount account) =>
      'archivedMessageThreads:${account.principalKind}:${account.id}';

  String _messageCursorKey(StaffAccount account, int threadId) =>
      'messageEventCursor:${account.principalKind}:${account.id}:$threadId';

  ChatContact _contactFromDirectory(MessageContactInfo contact) => ChatContact(
    id: 'contact-${contact.userId}',
    name: contact.displayName,
    role: contact.roleLabel,
    preview: '',
    time: '',
    online: contact.recentlyActive,
    isStudent: contact.category == 'student',
    remoteUserId: contact.userId,
    profileId: contact.profileId,
    principalKind: contact.principalKind,
  );

  ChatContact _contactFromThread(
    MessageThreadInfo thread,
    Map<int, ChatContact> byUser,
  ) {
    final account = _account;
    final otherParticipants = thread.participants
        .where((participant) {
          return account == null ||
              participant.principalKind != account.principalKind ||
              participant.principalId != account.id;
        })
        .toList(growable: false);
    final matched = otherParticipants
        .map((participant) => byUser[participant.userId])
        .whereType<ChatContact>()
        .toList(growable: false);
    final participantIds = otherParticipants
        .map((participant) => participant.userId)
        .toList(growable: false);
    final single = otherParticipants.length == 1 && matched.length == 1
        ? matched.first
        : null;
    final joinedNames = matched.map((contact) => contact.name).join(', ');
    final joinedRoles = matched
        .map((contact) => contact.role)
        .where((role) => role.isNotEmpty)
        .toSet()
        .join(' · ');
    final name =
        single?.name ??
        (thread.subject.isNotEmpty ? thread.subject : joinedNames);
    return ChatContact(
      id: 'thread-${thread.id}',
      name: name,
      role: single?.role ?? joinedRoles,
      preview: thread.subject,
      time: _compactDateTime(thread.lastMessageAt),
      unread: thread.unreadCount,
      online: single?.online ?? false,
      isStudent: matched.any((contact) => contact.isStudent),
      remoteUserId: single?.remoteUserId,
      profileId: single?.profileId,
      principalKind: single?.principalKind ?? '',
      threadId: thread.id,
      participantUserIds: participantIds,
      participantNames: {
        for (final participant in otherParticipants)
          if (byUser[participant.userId]?.name case final name?
              when name.isNotEmpty)
            participant.userId: name,
      },
    );
  }

  ChatMessage _chatMessageFromRemote(
    MessageInfo message,
    ChatContact? contact,
  ) {
    final account = _account;
    final mine =
        account != null &&
        message.senderPrincipalKind == account.principalKind &&
        message.senderPrincipalId == account.id;
    final attachment = message.attachments.isEmpty
        ? ''
        : _attachmentFilename(message.attachments.first);
    final extension = attachment.contains('.')
        ? attachment.split('.').last.toLowerCase()
        : '';
    final type = message.attachments.isEmpty
        ? MessageType.text
        : const {
            'jpg',
            'jpeg',
            'png',
            'webp',
            'gif',
            'heic',
          }.contains(extension)
        ? MessageType.image
        : const {'m4a', 'aac', 'mp3', 'wav', 'ogg'}.contains(extension)
        ? MessageType.voice
        : const {'mp4', 'mov'}.contains(extension)
        ? MessageType.video
        : MessageType.file;
    final senderName = mine
        ? ''
        : contact?.participantNames[message.senderUserId] ??
              (contact?.isGroup == false ? contact?.name ?? '' : '');
    return ChatMessage(
      id: message.id.toString(),
      text: message.body.isNotEmpty ? message.body : attachment,
      time: _compactTime(message.createdAt),
      isMine: mine,
      type: type,
      senderName: senderName,
      sentAt: message.createdAt,
      attachmentKey: message.attachments.isEmpty
          ? ''
          : message.attachments.first,
    );
  }

  String _compactDateTime(DateTime? value) {
    if (value == null) return '';
    final local = value.toLocal();
    final now = DateTime.now();
    if (local.year == now.year &&
        local.month == now.month &&
        local.day == now.day) {
      return _compactTime(local);
    }
    return '${local.day.toString().padLeft(2, '0')}.${local.month.toString().padLeft(2, '0')}';
  }

  String _compactTime(DateTime value) {
    final local = value.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  String _attachmentFilename(String key) {
    final path = Uri.tryParse(key)?.path ?? key;
    if (path.isEmpty) return '';
    return Uri.decodeComponent(path.split('/').last);
  }

  LibraryResource _libraryFileFromRemote(ContentFileInfo file) {
    final type = file.contentType.toLowerCase();
    final kind = type.startsWith('video/')
        ? LibraryKind.video
        : type.startsWith('audio/')
        ? LibraryKind.podcast
        : LibraryKind.book;
    final icon = switch (kind) {
      LibraryKind.video => Icons.play_circle_outline_rounded,
      LibraryKind.podcast => Icons.podcasts_rounded,
      LibraryKind.playlist => Icons.graphic_eq_rounded,
      LibraryKind.book =>
        type.startsWith('image/')
            ? Icons.image_outlined
            : Icons.menu_book_outlined,
    };
    return LibraryResource(
      id: 'file-${file.id}',
      title: file.title,
      subtitle: [
        if (file.locationName.isNotEmpty) file.locationName,
        _compactFileSize(file.sizeBytes),
      ].join(' · '),
      author: file.author,
      kind: kind,
      color: _libraryColor(file.id),
      icon: icon,
      downloadable: file.downloadable,
      remoteFileId: file.id,
      contentType: file.contentType,
      status: file.status,
      thumbnailUrl: file.thumbnailUrl,
      createdAt: file.createdAt,
      teacherApproved: file.teacherApproved,
      managerApproved: file.managerApproved,
      rejectReason: file.rejectReason,
    );
  }

  LibraryResource _libraryMaterialFromRemote(LibraryMaterialInfo material) =>
      LibraryResource(
        id: 'material-${material.id}',
        title: material.title,
        subtitle: material.topic.isNotEmpty
            ? material.topic
            : material.libraryName,
        author: material.author,
        kind: LibraryKind.book,
        color: _libraryColor(material.id + 2),
        icon: Icons.auto_stories_outlined,
        downloadable: false,
        remoteMaterialId: material.id,
        contentType: 'text/plain',
        body: material.body,
        status: material.status,
        createdAt: material.createdAt,
      );

  Color _libraryColor(int seed) {
    const colors = [
      Color(0xFF6559D5),
      Color(0xFF138A7A),
      Color(0xFFD45F73),
      Color(0xFFC3782C),
      Color(0xFF3976B8),
    ];
    return colors[seed.abs() % colors.length];
  }

  String _compactFileSize(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
    return '$bytes B';
  }

  bool _isAllowedAccount(StaffAccount account) {
    if (account.principalKind != 'teacher' &&
        account.principalKind != 'staff') {
      return false;
    }
    const blockedRoleTokens = {
      'ceo',
      'owner',
      'director',
      'manager',
      'administrator',
      'admin',
    };
    const blockedRolePhrases = {
      'chief-executive',
      'head-of-department',
      'head-of-dept',
    };
    final memberships = account.memberships.expand(
      (membership) => [membership.slug, membership.name],
    );
    return !memberships.any((value) {
      final normalized = value
          .trim()
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
          .replaceAll(RegExp(r'^-+|-+$'), '');
      final tokens = normalized.split('-').where((token) => token.isNotEmpty);
      return tokens.any(blockedRoleTokens.contains) ||
          blockedRolePhrases.any(normalized.contains);
    });
  }

  Future<void> _applyAccount(StaffAccount account) async {
    _account = account;
    _displayName = account.fullName;
    _roleDisplayName = account.roleName;
    _mustChangePassword = account.mustChangePassword;
    _role = _resolveRole(account);
    _messageThreadsById.clear();
    _directMessageThreadsByUser.clear();
    _messageThreadCreations.clear();
    _archivedMessageThreadIds = Set.unmodifiable(
      (_preferences.getStringList(_messageArchiveKey(account)) ?? const [])
          .map(int.tryParse)
          .whereType<int>(),
    );
    await _preferences.remove('displayName');
    if (const {'uz', 'ru', 'en'}.contains(account.preferredLanguage) &&
        account.preferredLanguage != _locale.languageCode) {
      _locale = Locale(account.preferredLanguage);
      await _preferences.setString('locale', account.preferredLanguage);
    }
    if (_gateway case final RemoteStarforgeGateway remote) {
      remote.language = _locale.languageCode;
    }
  }

  void _expireSession() {
    if (!_isSignedIn && _account == null && _displayName.isEmpty) return;
    _isSignedIn = false;
    _mustChangePassword = false;
    _pendingCurrentPassword = null;
    _account = null;
    _displayName = '';
    _roleDisplayName = '';
    _role = StaffRole.staff;
    _groups = const [];
    _groupsLoaded = false;
    _messageThreadsById.clear();
    _directMessageThreadsByUser.clear();
    _messageThreadCreations.clear();
    _archivedMessageThreadIds = const {};
    notifyListeners();
  }

  Future<void> _revokeRejectedSession() async {
    try {
      await _gateway.logout();
    } catch (_) {
      await _gateway.clearSession();
    }
  }

  void _requireMutable(String permission) {
    if (!canMutate(permission)) {
      throw const StarforgeException(
        code: 'forbidden',
        message: 'This action is not available for this account.',
        statusCode: 403,
      );
    }
  }

  StaffRole _resolveRole(StaffAccount account) {
    final labels = account.memberships
        .expand((item) => [item.slug, item.name])
        .join(' ')
        .toLowerCase();
    bool hasAny(List<String> values) => values.any(labels.contains);
    if (hasAny(['assistant', 'support teacher', 'co-teacher'])) {
      return StaffRole.assistant;
    }
    if (account.principalKind == 'teacher') return StaffRole.teacher;
    if (hasAny(['media', 'content', 'smm', 'photograph', 'videograph'])) {
      return StaffRole.media;
    }
    if (hasAny(['reception', 'registrar', 'front desk'])) {
      return StaffRole.reception;
    }
    if (hasAny(['sales', 'consultant'])) return StaffRole.sales;
    if (hasAny(['print', 'copy'])) return StaffRole.printer;
    if (hasAny(['cashier', 'accountant'])) return StaffRole.cashier;
    return StaffRole.staff;
  }
}

class AppControllerScope extends InheritedNotifier<AppController> {
  const AppControllerScope({
    super.key,
    required AppController controller,
    required super.child,
  }) : super(notifier: controller);

  static AppController of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<AppControllerScope>();
    assert(scope != null, 'AppControllerScope is missing above this context.');
    return scope!.notifier!;
  }
}

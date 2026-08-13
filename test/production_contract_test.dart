import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('authorization contracts', () {
    test('resource wildcards authorize only their own resource', () {
      final account = _account(
        permissions: const {'attendance:*', 'content:*'},
      );

      expect(account.can('attendance:read'), isTrue);
      expect(account.can('attendance:write'), isTrue);
      expect(account.can('content:approve'), isTrue);
      expect(account.can('cohorts:read'), isFalse);
      expect(account.can('attendance'), isFalse);
    });

    test('global wildcard authorizes every resource action', () {
      final account = _account(permissions: const {'*:*'});

      expect(account.can('attendance:write'), isTrue);
      expect(account.can('content:approve'), isTrue);
      expect(account.can('finance:read'), isTrue);
    });

    test('Admissions is allowed and is not mistaken for Admin', () async {
      final gateway = _ContractGateway(
        account: _account(name: 'Admissions', slug: 'admissions'),
      );
      final controller = await AppController.load(
        gateway: gateway,
        restoreSession: false,
      );

      final result = await controller.signIn(
        username: 'admissions.staff',
        password: 'correct-password',
      );

      expect(result, AuthResult.success);
      expect(controller.isSignedIn, isTrue);
      expect(gateway.clearCalls, 0);
    });

    for (final blocked in const [
      ('Admin', 'admin'),
      ('Branch Manager', 'branch-manager'),
      ('Chief Executive Officer', 'chief-executive-officer'),
    ]) {
      test('${blocked.$1} membership is rejected from the staff app', () async {
        final gateway = _ContractGateway(
          account: _account(name: blocked.$1, slug: blocked.$2),
        );
        final controller = await AppController.load(
          gateway: gateway,
          restoreSession: false,
        );

        final result = await controller.signIn(
          username: blocked.$2,
          password: 'correct-password',
        );

        expect(result, AuthResult.restricted);
        expect(controller.isSignedIn, isFalse);
        expect(gateway.clearCalls, 1);
      });
    }
  });

  group('session and profile synchronization', () {
    test('temporary restore failure preserves the saved session', () async {
      final gateway = _ContractGateway(
        hasSession: true,
        currentAccountError: const StarforgeException(
          code: 'connection_unavailable',
          message: 'Offline',
          statusCode: 503,
        ),
      );

      final controller = await AppController.load(gateway: gateway);

      expect(controller.isSignedIn, isFalse);
      expect(controller.restoring, isFalse);
      expect(gateway.hasSession, isTrue);
      expect(gateway.clearCalls, 0);
    });

    test('rejected token is cleared during session restore', () async {
      final gateway = _ContractGateway(
        hasSession: true,
        currentAccountError: const StarforgeException(
          code: 'authentication_failed',
          message: 'Expired',
          statusCode: 401,
        ),
      );

      final controller = await AppController.load(gateway: gateway);

      expect(controller.isSignedIn, isFalse);
      expect(gateway.hasSession, isFalse);
      expect(gateway.clearCalls, 1);
    });

    test(
      'account language restores locally and changes sync to profile',
      () async {
        final gateway = _ContractGateway(
          account: _account(preferredLanguage: 'en'),
        );
        final controller = await AppController.load(
          gateway: gateway,
          restoreSession: false,
        );

        expect(
          await controller.signIn(
            username: 'staff',
            password: 'correct-password',
          ),
          AuthResult.success,
        );
        expect(controller.locale, const Locale('en'));

        await controller.setLocale(const Locale('ru'));

        final preferences = await SharedPreferences.getInstance();
        expect(controller.locale, const Locale('ru'));
        expect(preferences.getString('locale'), 'ru');
        expect(gateway.profileChanges, [
          {'preferred_language': 'ru'},
        ]);
      },
    );

    test(
      'read-only account keeps locale local without mutating profile',
      () async {
        final gateway = _ContractGateway(account: _account(readOnly: true));
        final controller = await AppController.load(
          gateway: gateway,
          restoreSession: false,
        );
        await controller.signIn(
          username: 'observer',
          password: 'correct-password',
        );

        await controller.setLocale(const Locale('ru'));

        expect(controller.locale, const Locale('ru'));
        expect(gateway.profileChanges, isEmpty);
      },
    );
  });

  group('teaching workspace contracts', () {
    test(
      'assistant dashboard aggregates scoped groups without teacher endpoint',
      () async {
        final firstLesson = _lesson(
          1,
          DateTime.now().add(const Duration(hours: 2)),
        );
        final secondLesson = _lesson(
          2,
          DateTime.now().add(const Duration(days: 2)),
        );
        final gateway = _ContractGateway(
          account: _account(
            name: 'Teaching Assistant',
            slug: 'assistant',
            permissions: const {
              'cohorts:*',
              'students:*',
              'attendance:*',
              'meetings:read',
            },
          ),
          groupsData: [_group(id: 1), _group(id: 2)],
          studentsByGroup: {
            1: [_student(11), _student(12)],
            2: [_student(12), _student(13)],
          },
          attendanceLoader: (groupId, month) {
            final lesson = groupId == 1 ? firstLesson : secondLesson;
            if (lesson.startsAt.year != month.year ||
                lesson.startsAt.month != month.month) {
              return AttendanceMonth.empty(month);
            }
            return AttendanceMonth(
              month: month,
              lessons: [lesson],
              records: const [],
              rate: 0,
              students: const [],
            );
          },
          meetingsData: [
            MeetingInfo(
              id: 8,
              title: 'Weekly sync',
              agenda: '',
              branchName: 'Central',
              startsAt: DateTime.now().add(const Duration(days: 1)),
              endsAt: DateTime.now().add(const Duration(days: 1, hours: 1)),
              location: 'Room 4',
              status: 'scheduled',
            ),
          ],
        );
        final controller = await AppController.load(
          gateway: gateway,
          restoreSession: false,
        );
        await controller.signIn(
          username: 'assistant',
          password: 'correct-password',
        );

        final dashboard = await controller.loadTeacherDashboard();

        expect(controller.role, StaffRole.assistant);
        expect(controller.hasTeachingWorkspace, isTrue);
        expect(dashboard, isNotNull);
        expect(dashboard!.groupsCount, 2);
        expect(dashboard.studentsCount, 3);
        expect(dashboard.nextLessons.map((item) => item.id), [1, 2]);
        expect(dashboard.nextMeeting['title'], 'Weekly sync');
        expect(gateway.teacherDashboardCalls, 0);
      },
    );

    test(
      'assistant dashboard never requests ungranted student or meeting data',
      () async {
        final gateway = _ContractGateway(
          account: _account(
            name: 'Teaching Assistant',
            slug: 'assistant',
            permissions: const {'cohorts:read', 'attendance:read'},
          ),
        );
        final controller = await AppController.load(
          gateway: gateway,
          restoreSession: false,
        );
        await controller.signIn(
          username: 'assistant',
          password: 'correct-password',
        );

        final dashboard = await controller.loadTeacherDashboard();

        expect(dashboard, isNotNull);
        expect(dashboard!.studentsCount, isNull);
        expect(dashboard.nextMeeting, isEmpty);
        expect(gateway.studentCalls, 0);
        expect(gateway.meetingCalls, 0);
      },
    );

    test(
      'task transitions require write permission even for assignee',
      () async {
        final gateway = _ContractGateway(
          account: _account(permissions: const {'tasks:read'}),
        );
        final controller = await AppController.load(
          gateway: gateway,
          restoreSession: false,
        );
        await controller.signIn(
          username: 'staff',
          password: 'correct-password',
        );
        const task = StaffTask(
          id: '5',
          remoteId: 5,
          title: 'Read-only task',
          description: '',
          due: '',
          assignee: 'Taylor Staff',
          creator: '',
          stage: TaskStage.todo,
          assigneePrincipalKind: 'staff',
          assigneePrincipalId: 7,
        );

        expect(
          () => controller.transitionTask(task, TaskStage.done),
          throwsA(isA<StarforgeException>()),
        );
        expect(gateway.transitionCalls, 0);
      },
    );

    test('group detail preserves unknown and real zero attendance', () async {
      final month = DateTime.now();
      final gateway = _ContractGateway(
        account: _account(
          principalKind: 'teacher',
          name: 'Teacher',
          slug: 'teacher',
          permissions: const {'students:read', 'attendance:read'},
        ),
        studentsByGroup: {
          9: [_student(21), _student(22)],
        },
        attendanceLoader: (groupId, requestedMonth) => AttendanceMonth(
          month: DateTime(month.year, month.month),
          lessons: const [],
          records: const [],
          rate: 0,
          students: requestedMonth.month == month.month
              ? const [
                  StudentAttendanceSummary(
                    studentId: 21,
                    name: 'Student 21',
                    present: 0,
                    absent: 1,
                    late: 0,
                    excused: 0,
                    total: 1,
                    percentPresent: 0,
                  ),
                ]
              : const [],
        ),
      );
      final controller = await AppController.load(
        gateway: gateway,
        restoreSession: false,
      );
      await controller.signIn(
        username: 'teacher',
        password: 'correct-password',
      );

      final detail = await controller.loadGroupDetails(_group(id: 9));

      expect(detail.students[0].attendance, 0);
      expect(detail.students[1].attendance, isNull);
    });

    test(
      'student request uses the group branch over account memberships',
      () async {
        final gateway = _ContractGateway(
          account: _account(
            permissions: const {'approvals:*'},
            memberships: const [
              RoleMembership(
                id: 1,
                name: 'Teacher',
                slug: 'teacher',
                kind: 'teacher',
                branchName: 'North',
                departmentName: 'English',
                branchId: 1,
                departmentId: 1,
              ),
              RoleMembership(
                id: 2,
                name: 'Teacher',
                slug: 'teacher',
                kind: 'teacher',
                branchName: 'South',
                departmentName: 'English',
                branchId: 2,
                departmentId: 1,
              ),
            ],
          ),
        );
        final controller = await AppController.load(
          gateway: gateway,
          restoreSession: false,
        );
        await controller.signIn(
          username: 'teacher',
          password: 'correct-password',
        );

        final sent = await controller.submitStudentRequest(
          action: 'move',
          group: _group(id: 9, branchId: 77),
          student: _student(21),
          description: 'Please move this student after the current unit.',
        );

        expect(sent, isTrue);
        expect(gateway.requestedBranchId, 77);
        expect(gateway.requestedGroupId, 9);
      },
    );
  });
}

class _ContractGateway implements StarforgeGateway {
  _ContractGateway({
    StaffAccount? account,
    this.hasSession = false,
    this.currentAccountError,
    this.groupsData = const [],
    this.studentsByGroup = const {},
    this.attendanceLoader,
    this.meetingsData = const [],
  }) : account = account ?? _account();

  StaffAccount account;
  bool hasSession;
  final Object? currentAccountError;
  final List<LearningGroup> groupsData;
  final Map<int, List<Student>> studentsByGroup;
  final AttendanceMonth Function(int groupId, DateTime month)? attendanceLoader;
  final List<MeetingInfo> meetingsData;
  int clearCalls = 0;
  int teacherDashboardCalls = 0;
  int studentCalls = 0;
  int meetingCalls = 0;
  int transitionCalls = 0;
  int? requestedBranchId;
  int? requestedGroupId;
  final List<Map<String, Object?>> profileChanges = [];

  @override
  Future<bool> hasSavedSession() async => hasSession;

  @override
  Future<LoginSession> login(String username, String password) async {
    hasSession = true;
    return LoginSession(
      access: 'access',
      principalKind: account.principalKind,
      mustChangePassword: false,
    );
  }

  @override
  Future<StaffAccount> currentAccount() async {
    if (currentAccountError case final error?) throw error;
    return account;
  }

  @override
  Future<void> clearSession() async {
    clearCalls++;
    hasSession = false;
  }

  @override
  Future<StaffAccount> updateProfile(Map<String, Object?> changes) async {
    profileChanges.add(Map<String, Object?>.from(changes));
    final language = changes['preferred_language']?.toString();
    if (language != null) {
      account = _copyAccount(account, preferredLanguage: language);
    }
    return account;
  }

  @override
  Future<List<LearningGroup>> groups() async => groupsData;

  @override
  Future<List<Student>> studentsForGroup(int groupId) async {
    studentCalls++;
    return studentsByGroup[groupId] ?? const [];
  }

  @override
  Future<AttendanceMonth> attendanceForMonth(
    int groupId,
    DateTime month,
  ) async =>
      attendanceLoader?.call(groupId, month) ?? AttendanceMonth.empty(month);

  @override
  Future<List<MeetingInfo>> upcomingMeetings() async {
    meetingCalls++;
    return meetingsData;
  }

  @override
  Future<StaffTask> transitionTask(int taskId, String status) async {
    transitionCalls++;
    throw StateError('transition should not be reached in this fake');
  }

  @override
  Future<TeacherDashboardData> teacherDashboard() async {
    teacherDashboardCalls++;
    return const TeacherDashboardData(
      groupsCount: 0,
      studentsCount: 0,
      nextLessons: [],
      nextMeeting: {},
    );
  }

  @override
  Future<void> submitStudentRequest({
    required String action,
    required LearningGroup group,
    required Student student,
    required String description,
    int? branchId,
  }) async {
    requestedBranchId = branchId;
    requestedGroupId = group.remoteId;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

StaffAccount _account({
  String principalKind = 'staff',
  String name = 'Staff',
  String slug = 'staff',
  String preferredLanguage = 'uz',
  Set<String> permissions = const {},
  bool readOnly = false,
  List<RoleMembership>? memberships,
}) => StaffAccount(
  id: 7,
  principalKind: principalKind,
  username: 'staff.user',
  fullName: 'Taylor Staff',
  firstName: 'Taylor',
  lastName: 'Staff',
  phone: '',
  email: '',
  preferredLanguage: preferredLanguage,
  mustChangePassword: false,
  memberships:
      memberships ??
      [
        RoleMembership(
          id: 1,
          name: name,
          slug: slug,
          kind: principalKind,
          branchName: 'Central',
          departmentName: 'English',
          branchId: 1,
          departmentId: 1,
        ),
      ],
  permissions: permissions,
  readOnly: readOnly,
);

StaffAccount _copyAccount(
  StaffAccount source, {
  required String preferredLanguage,
}) => StaffAccount(
  id: source.id,
  principalKind: source.principalKind,
  username: source.username,
  fullName: source.fullName,
  firstName: source.firstName,
  middleName: source.middleName,
  lastName: source.lastName,
  phone: source.phone,
  email: source.email,
  preferredLanguage: preferredLanguage,
  mustChangePassword: source.mustChangePassword,
  memberships: source.memberships,
  permissions: source.permissions,
  readOnly: source.readOnly,
);

LearningGroup _group({required int id, int? branchId}) => LearningGroup(
  id: '$id',
  name: 'Group $id',
  course: 'English',
  level: 'B1',
  studyMonth: 2,
  schedule: '',
  room: '4',
  branch: 'Central',
  department: 'English',
  mainTeacher: 'Teacher',
  progress: 0,
  attendance: 0,
  nextLesson: '',
  students: const [],
  remoteId: id,
  branchId: branchId ?? 1,
);

Student _student(int id) => Student(
  id: '$id',
  name: 'Student $id',
  phone: '',
  guardian: '',
  guardianPhone: '',
  birthDate: '',
  joinedDate: '',
);

LessonInfo _lesson(int id, DateTime startsAt) => LessonInfo(
  id: id,
  cohortId: id,
  cohortName: 'Group $id',
  title: 'Lesson $id',
  roomName: 'Room $id',
  typeName: 'Regular',
  startsAt: startsAt,
  endsAt: startsAt.add(const Duration(hours: 1)),
  status: 'scheduled',
);

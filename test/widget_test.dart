import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/app.dart';
import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/features/groups/attendance_page.dart';
import 'package:starforge_staff/features/groups/group_detail_page.dart';
import 'package:starforge_staff/features/library/library_page.dart';
import 'package:starforge_staff/features/messages/conversation_page.dart';
import 'package:starforge_staff/features/print/print_page.dart';
import 'package:starforge_staff/features/profile/settings_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

import 'support/demo_data.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('collection requests respect the production page-size limit', () async {
    var requests = 0;
    final client = MockClient((request) async {
      requests++;
      expect(request.url.path, '/api/v1/cohorts/');
      expect(request.url.queryParameters['page_size'], '100');
      expect(request.headers['Authorization'], 'Bearer test-access');
      return http.Response(
        jsonEncode({
          'success': true,
          'data': [
            {
              'id': 1,
              'name': 'Orion',
              'level': 'B1',
              'branch_name': 'Chilonzor',
              'department_name': 'English',
            },
          ],
          'pagination': {
            'total': 1,
            'page': 1,
            'page_size': 100,
            'pages': 1,
            'has_next': false,
            'has_prev': false,
          },
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    final gateway = RemoteStarforgeGateway(
      client: client,
      sessionStore: MemorySessionStore(access: 'test-access'),
      baseUrl: 'https://example.test',
    );

    final groups = await gateway.groups();

    expect(groups.single.name, 'Orion');
    expect(requests, 1);
  });

  test('executive memberships are rejected from the staff app', () async {
    final controller = await AppController.load(
      gateway: _FakeGateway(),
      restoreSession: false,
    );

    final result = await controller.signIn(
      username: 'director.samir',
      password: 'secure-password',
    );

    expect(result, AuthResult.restricted);
    expect(controller.isSignedIn, isFalse);
  });

  testWidgets('staff member can sign in without choosing a role', (
    tester,
  ) async {
    final controller = await AppController.load(
      gateway: _FakeGateway(),
      restoreSession: false,
    );
    await tester.pumpWidget(StarforgeApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 80));

    expect(find.text('Xush kelibsiz'), findsOneWidget);
    expect(find.text('Xodim lavozimi'), findsNothing);

    await tester.enterText(
      find.byKey(const ValueKey('usernameField')),
      'teacher.aziza',
    );
    await tester.enterText(
      find.byKey(const ValueKey('passwordField')),
      'starforge-password',
    );
    await tester.ensureVisible(find.byKey(const ValueKey('loginButton')));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.tap(find.byKey(const ValueKey('loginButton')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));

    expect(controller.isSignedIn, isTrue);
    expect(controller.role, StaffRole.teacher);
    expect(find.text('Asosiy'), findsOneWidget);
  });

  testWidgets('teacher can open an assigned group on a phone layout', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await AppController.load(
      gateway: _FakeGateway(),
      restoreSession: false,
    );
    await controller.signIn(
      username: 'teacher.aziza',
      password: 'starforge-password',
    );
    await tester.pumpWidget(StarforgeApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 900));

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Guruhlar'),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    expect(find.text('Sizning guruhlaringiz'), findsOneWidget);

    final groupCard = find.byKey(const ValueKey('group-g1'));
    expect(groupCard, findsOneWidget);
    await tester.tap(groupCard);
    await tester.pumpAndSettle();
    expect(find.byType(GroupDetailPage), findsOneWidget);

    await tester.drag(
      find.byType(CustomScrollView).last,
      const Offset(0, -650),
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('O‘quvchilar ro‘yxati'), findsOneWidget);
    expect(find.text('Madina Akramova'), findsOneWidget);
  });

  testWidgets('sales membership receives its operational workspace', (
    tester,
  ) async {
    final controller = await AppController.load(
      gateway: _FakeGateway(),
      restoreSession: false,
    );
    await controller.signIn(
      username: 'sales.nodira',
      password: 'starforge-password',
    );
    await tester.pumpWidget(StarforgeApp(controller: controller));
    await tester.pump(const Duration(milliseconds: 900));

    expect(controller.role, StaffRole.sales);
    expect(find.byKey(const ValueKey('shell-page-home')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Xabarlar'),
      ),
      findsNothing,
    );
    expect(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Vazifalar'),
      ),
      findsOneWidget,
    );

    await tester.tap(
      find.descendant(
        of: find.byType(NavigationBar),
        matching: find.text('Ish'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('shell-page-work')), findsOneWidget);
    expect(find.text('To‘liq ish maydoningiz'), findsOneWidget);
  });

  testWidgets('critical detail pages fit a compact phone', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await AppController.load(
      gateway: _FakeGateway(),
      restoreSession: false,
    );
    await controller.signIn(
      username: 'teacher.aziza',
      password: 'starforge-password',
    );

    Future<void> pumpPage(Widget page) async {
      await tester.pumpWidget(
        AppControllerScope(
          controller: controller,
          child: MaterialApp(
            theme: AppTheme.light(controller.accent),
            locale: controller.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: page,
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
    }

    await pumpPage(AttendancePage(group: DemoData.groups.first));
    expect(find.text('Davomat tarixi'), findsOneWidget);

    await pumpPage(ConversationPage(contact: DemoData.contacts.first));
    expect(find.text('Malika Yoqubova'), findsOneWidget);

    await pumpPage(const LibraryPage());
    expect(find.text('Kutubxona'), findsWidgets);

    await pumpPage(const PrintPage());
    expect(find.text('Mavjud printerlar'), findsOneWidget);

    await pumpPage(const SettingsPage());
    expect(find.text('Sozlamalar'), findsOneWidget);
  });
}

class _FakeGateway implements StarforgeGateway {
  StaffAccount _account = _teacherAccount();
  bool _hasSession = false;

  @override
  Future<void> clearSession() async => _hasSession = false;

  @override
  Future<List<ContentFileInfo>> contentFiles() async => const [];

  @override
  Future<String> contentFileUrl(int fileId) async => 'https://example.test';

  @override
  Future<void> trackContentFileView(int fileId) async {}

  @override
  Future<ContentFileInfo> approveContentFileAsTeacher(int fileId) =>
      throw UnimplementedError();

  @override
  Future<List<ContentFolderInfo>> contentFolders() async => const [];

  @override
  Future<LoginSession> changePassword(
    String oldPassword,
    String newPassword,
  ) async => const LoginSession(
    access: 'replacement-session',
    principalKind: 'teacher',
    mustChangePassword: false,
  );

  @override
  Future<StaffTask> createTask({
    required String title,
    required String description,
    required bool highPriority,
    required String principalKind,
    required int principalId,
    DateTime? dueAt,
  }) async => StaffTask(
    id: '99',
    remoteId: 99,
    title: title,
    description: description,
    due: dueAt?.toIso8601String() ?? '',
    assignee: _account.fullName,
    creator: _account.fullName,
    stage: TaskStage.todo,
    highPriority: highPriority,
  );

  @override
  Future<StaffAccount> currentAccount() async => _account;

  @override
  Future<List<ExamResultInfo>> examResults(int examId) async => const [];

  @override
  Future<List<ExamInfo>> examsForGroup(int groupId) async => const [];

  @override
  Future<List<LearningGroup>> groups() async => DemoData.groups;

  @override
  Future<bool> hasSavedSession() async => _hasSession;

  @override
  Future<LoginSession> login(String username, String password) async {
    _hasSession = true;
    if (username.contains('director')) {
      _account = _staffAccount('Director', 'director');
    } else if (username.contains('sales')) {
      _account = _staffAccount('Sales consultant', 'sales');
    } else {
      _account = _teacherAccount();
    }
    return LoginSession(
      access: 'test-session',
      principalKind: _account.principalKind,
      mustChangePassword: false,
    );
  }

  @override
  Future<MessageThreadInfo> createMessageThread({
    required int participantUserId,
    String subject = '',
  }) async => const MessageThreadInfo(
    id: 1,
    subject: '',
    participants: [],
    unreadCount: 0,
    lastMessageAt: null,
    notificationsMuted: false,
  );

  @override
  Future<List<MessageContactInfo>> messageContacts() async => const [];

  @override
  Future<List<MessageThreadInfo>> messageThreads() async => const [];

  @override
  Future<List<MessageInfo>> messagesForThread(
    int threadId, {
    int? afterId,
  }) async => const [];

  @override
  Future<String> messageAttachmentUrl({
    required int threadId,
    required String key,
  }) async => 'https://example.test/attachment';

  @override
  Future<List<PrintJobInfo>> printJobs() async => const [];

  @override
  Future<PrintJobInfo> submitUploadedPrintJob({
    required String filePath,
    required String filename,
    required String contentType,
    required int sizeBytes,
    required int branchId,
    required int printerId,
    required int copies,
    required bool color,
    required bool duplex,
    DateTime? scheduledFor,
  }) async => PrintJobInfo(
    id: 1,
    printerId: printerId,
    status: 'queued',
    source: filename,
    pages: 1,
    copies: copies,
    color: color,
    duplex: duplex,
    createdAt: DateTime(2026, 8, 12),
    finishedAt: null,
    scheduledFor: scheduledFor,
  );

  @override
  Future<PrintJobInfo> submitLibraryPrintJob({
    required int fileId,
    required int printerId,
    required int copies,
    required bool color,
    required bool duplex,
    DateTime? scheduledFor,
  }) async => PrintJobInfo(
    id: 2,
    printerId: printerId,
    status: 'queued',
    source: 'library-file-$fileId',
    pages: 1,
    copies: copies,
    color: color,
    duplex: duplex,
    createdAt: DateTime(2026, 8, 12),
    finishedAt: null,
    scheduledFor: scheduledFor,
  );

  @override
  Future<List<PayrollPayslipInfo>> ownPayslips() async => const [];

  @override
  Future<List<ComplianceRuleInfo>> ownRules() async => const [];

  @override
  Future<void> acknowledgeRule(int ruleId) async {}

  @override
  Future<List<NotificationInfo>> notifications() async => const [];

  @override
  Future<int> unreadNotificationCount() async => 0;

  @override
  Future<void> markNotificationRead(int notificationId) async {}

  @override
  Future<void> markAllNotificationsRead() async {}

  @override
  Future<List<NotificationPreferenceInfo>> notificationPreferences() async =>
      const [];

  @override
  Future<List<NotificationPreferenceInfo>> updateNotificationPreferences(
    List<NotificationPreferenceInfo> preferences,
  ) async => preferences;

  @override
  Future<List<MeetingInfo>> upcomingMeetings() async => const [];

  @override
  Future<List<CrmLeadInfo>> crmLeads() async => const [];

  @override
  Future<List<FinanceInvoiceInfo>> financeInvoices() async => const [];

  @override
  Future<List<CashierShiftInfo>> ownCashierShifts() async => const [];

  @override
  Future<List<PrinterInfo>> printers() async => const [];

  @override
  Future<void> markMessageThreadRead(
    int threadId, {
    int? throughMessageId,
  }) async {}

  @override
  Future<MessageInfo> sendMessage({
    required int threadId,
    String body = '',
    List<String> attachments = const [],
  }) async => MessageInfo(
    id: 1,
    threadId: threadId,
    senderUserId: 1,
    senderPrincipalKind: _account.principalKind,
    senderPrincipalId: _account.id,
    body: body,
    attachments: attachments,
    createdAt: DateTime.now(),
  );

  @override
  Future<void> logout() async => _hasSession = false;

  @override
  Future<List<LibraryMaterialInfo>> libraryMaterials() async => const [];

  @override
  Future<List<AttendanceRecordInfo>> markAttendance(
    int lessonId,
    List<Map<String, Object?>> records,
  ) async => const [];

  @override
  Future<List<Student>> studentsForGroup(int groupId) async =>
      DemoData.groups.first.students;

  @override
  Future<void> submitStudentRequest({
    required String action,
    required LearningGroup group,
    required Student student,
    required String description,
    int? branchId,
  }) async {}

  @override
  Future<List<StaffTask>> tasks({bool mineOnly = false}) async =>
      DemoData.tasks;

  @override
  Future<TeacherDashboardData> teacherDashboard() async =>
      const TeacherDashboardData(
        groupsCount: 3,
        studentsCount: 24,
        nextLessons: [],
        nextMeeting: {},
      );

  @override
  Future<List<FeatureAvailabilityInfo>> featureAvailability() async => const [
    FeatureAvailabilityInfo(
      feature: 'ai',
      status: FeatureAvailabilityStatus.available,
    ),
  ];

  @override
  Future<StaffTask> transitionTask(int taskId, String status) async {
    final task = DemoData.tasks.first;
    return task.copyWith(
      stage: switch (status) {
        'in_progress' => TaskStage.inProgress,
        'done' => TaskStage.done,
        _ => TaskStage.todo,
      },
      rawStatus: status,
    );
  }

  @override
  Future<StaffAccount> updateProfile(Map<String, Object?> changes) async =>
      _account;

  @override
  Future<String> uploadMessageAttachment({
    required String filePath,
    required String filename,
    required String contentType,
  }) async => 'messages/$filename';

  @override
  Future<int> uploadContentFile({
    required String filePath,
    required String filename,
    required String contentType,
    required String title,
    required int folderId,
    required String audience,
    required bool downloadable,
  }) async => 1;

  @override
  Future<AttendanceMonth> attendanceForMonth(
    int groupId,
    DateTime month,
  ) async => AttendanceMonth.empty(month);
}

StaffAccount _teacherAccount() => StaffAccount(
  id: 17,
  principalKind: 'teacher',
  username: 'teacher.aziza',
  fullName: 'Aziza Karimova',
  phone: '+998900000000',
  email: 'aziza@example.test',
  preferredLanguage: 'uz',
  mustChangePassword: false,
  memberships: const [
    RoleMembership(
      id: 1,
      name: 'Teacher',
      slug: 'teacher',
      kind: 'teacher',
      branchName: 'Chilonzor',
      departmentName: 'English',
      branchId: 1,
      departmentId: 1,
    ),
  ],
  permissions: const {
    'cohorts:read',
    'students:read',
    'schedule:read',
    'attendance:read',
    'attendance:write',
    'academics:read',
  },
  readOnly: false,
);

StaffAccount _staffAccount(String name, String slug) => StaffAccount(
  id: 22,
  principalKind: 'staff',
  username: slug,
  fullName: 'Nodira Saidova',
  phone: '+998901111111',
  email: 'nodira@example.test',
  preferredLanguage: 'uz',
  mustChangePassword: false,
  memberships: [
    RoleMembership(
      id: 2,
      name: name,
      slug: slug,
      kind: 'staff',
      branchName: 'Chilonzor',
      departmentName: 'Operations',
      branchId: 1,
      departmentId: 2,
    ),
  ],
  permissions: const {'tasks:read'},
  readOnly: false,
);

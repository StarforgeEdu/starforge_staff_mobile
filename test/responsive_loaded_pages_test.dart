import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/features/dashboard/dashboard_page.dart';
import 'package:starforge_staff/features/dashboard/notifications_page.dart';
import 'package:starforge_staff/features/groups/groups_page.dart';
import 'package:starforge_staff/features/library/library_page.dart';
import 'package:starforge_staff/features/role_workspace/role_workspace_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('loaded groups fit a narrow Russian layout at 200% text', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    final semantics = tester.ensureSemantics();
    final controller = await _signedInController(
      const Locale('ru'),
      username: 'teacher',
    );
    await controller.loadGroups();

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('ru'),
        child: const GroupsPage(),
      ),
    );
    await tester.pumpAndSettle();

    final firstGroup = find.byKey(const ValueKey('group-1'));
    await _scrollUntilBuilt(tester, firstGroup);
    expect(firstGroup, findsOneWidget);
    expect(
      tester
          .getSemantics(firstGroup)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -1200),
      1200,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('loaded library fits English landscape at 200% text', (
    tester,
  ) async {
    _setViewport(tester, const Size(844, 390));
    final semantics = tester.ensureSemantics();
    final controller = await _signedInController(
      const Locale('en'),
      username: 'teacher',
    );

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('en'),
        child: const LibraryPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final openButton = find.byTooltip('Open resource');
    await _scrollUntilBuilt(tester, openButton, step: 140);
    expect(openButton, findsOneWidget);
    expect(tester.getSize(openButton).shortestSide, greaterThanOrEqualTo(48));
    final resource = find.byKey(const ValueKey('library-resource-file-1'));
    await _scrollUntilBuilt(tester, resource, step: 140);
    expect(resource, findsOneWidget);
    expect(
      tester
          .getSemantics(resource)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -950),
      1200,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('high-cardinality Uzbek role layouts reflow at 200% text', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    final semantics = tester.ensureSemantics();
    final controller = await _signedInController(
      const Locale('uz'),
      username: 'sales',
    );

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('uz'),
        child: RoleDashboardPage(onOpenWorkspace: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final metrics = find.byKey(const ValueKey('role-metrics'));
    await _scrollUntilBuilt(tester, metrics, step: 120);
    expect(metrics, findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -900),
      1100,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    _setViewport(tester, const Size(844, 390));
    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('uz'),
        child: const RoleWorkspacePage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Mijozlar'), findsWidgets);
    expect(tester.takeException(), isNull);
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -1200),
      1200,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('dashboard stays API-truthful and routes profile at large text', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    final gateway = _ResponsiveGateway();
    final controller = await _signedInController(
      const Locale('en'),
      username: 'teacher',
      gateway: gateway,
    );
    var selectedIndex = -1;

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('en'),
        child: DashboardPage(onNavigate: (index) => selectedIndex = index),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('Profile'), findsOneWidget);
    await tester.tap(find.byTooltip('Profile'));
    expect(selectedIndex, 4);
    expect(find.byType(Badge), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(controller.can('tasks:read'), isTrue);
    expect(controller.can('content:read'), isTrue);
    expect(controller.can('attendance:read'), isFalse);
    expect(controller.can('printing:read'), isFalse);
    final permittedQuickAction = find.text('Open tasks');
    await _jumpUntilBuilt(tester, permittedQuickAction);
    expect(permittedQuickAction, findsOneWidget);
    expect(find.text('Library'), findsOneWidget);
    expect(find.text('Take attendance'), findsNothing);
    expect(find.text('Print center'), findsNothing);

    final aiMessage = find.text(
      'AI is available. There is no verified recommendation for you right now.',
    );
    await _scrollUntilBuilt(tester, aiMessage, step: 220, attempts: 24);
    expect(aiMessage, findsOneWidget);
    expect(find.textContaining('Group B2 responds best'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification rows open real details and save read status', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 760));
    final gateway = _ResponsiveGateway();
    final controller = await _signedInController(
      const Locale('en'),
      username: 'teacher',
      gateway: gateway,
    );

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('en'),
        child: const NotificationsPage(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Important operational notification 1'));
    await tester.pumpAndSettle();

    expect(
      find.text('Detailed notification body for the current staff member.'),
      findsWidgets,
    );
    expect(find.text('Close'), findsOneWidget);
    expect(gateway.markReadCalls, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('notification failure is not presented as a genuine empty feed', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 760));
    final gateway = _ResponsiveGateway(failNotifications: true);
    final controller = await _signedInController(
      const Locale('en'),
      username: 'teacher',
      gateway: gateway,
    );

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('en'),
        child: const NotificationsPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Notifications could not be loaded. Please try again.'),
      findsOneWidget,
    );
    expect(find.text('You’re all caught up'), findsNothing);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _scrollUntilBuilt(
  WidgetTester tester,
  Finder finder, {
  double step = 180,
  int attempts = 10,
}) async {
  for (
    var attempt = 0;
    attempt < attempts && finder.evaluate().isEmpty;
    attempt++
  ) {
    await tester.drag(find.byType(CustomScrollView).last, Offset(0, -step));
    await tester.pumpAndSettle();
  }
}

Future<void> _jumpUntilBuilt(WidgetTester tester, Finder finder) async {
  final scrollable = tester.state<ScrollableState>(
    find.descendant(
      of: find.byType(CustomScrollView).last,
      matching: find.byType(Scrollable),
    ),
  );
  final position = scrollable.position;
  for (
    var offset = position.minScrollExtent;
    offset <= position.maxScrollExtent && finder.evaluate().isEmpty;
    offset += 60
  ) {
    position.jumpTo(offset);
    await tester.pump();
  }
}

Future<AppController> _signedInController(
  Locale locale, {
  required String username,
  _ResponsiveGateway? gateway,
}) async {
  final controller = await AppController.load(
    gateway: gateway ?? _ResponsiveGateway(),
    restoreSession: false,
  );
  expect(
    await controller.signIn(username: username, password: 'valid-password'),
    AuthResult.success,
  );
  await controller.setLocale(locale);
  return controller;
}

Widget _harness({
  required AppController controller,
  required Locale locale,
  required Widget child,
}) => AppControllerScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light(controller.accent),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: true,
        textScaler: const TextScaler.linear(2),
      ),
      child: child!,
    ),
    home: child,
  ),
);

class _ResponsiveGateway implements StarforgeGateway {
  _ResponsiveGateway({this.failNotifications = false});

  final bool failNotifications;
  int markReadCalls = 0;

  StaffAccount _account = _teacherAccount;

  @override
  Future<LoginSession> login(String username, String password) async {
    _account = username == 'sales' ? _salesAccount : _teacherAccount;
    return LoginSession(
      access: 'responsive-test-session',
      principalKind: _account.principalKind,
      mustChangePassword: false,
    );
  }

  @override
  Future<StaffAccount> currentAccount() async => _account;

  @override
  Future<StaffAccount> updateProfile(Map<String, Object?> changes) async =>
      _account;

  @override
  Future<List<LearningGroup>> groups() async => List.generate(
    40,
    (index) => LearningGroup(
      id: '${index + 1}',
      remoteId: index + 1,
      branchId: 3,
      name: 'International conversation cohort ${index + 1}',
      course: 'General English and communication',
      level: 'Upper intermediate',
      studyMonth: 4,
      schedule: 'Monday · Wednesday · Friday',
      room: 'Room ${200 + index}',
      branch: 'Chilonzor central branch',
      department: 'English language department',
      mainTeacher: 'Aziza Karimova',
      progress: .6,
      attendance: .9,
      nextLesson: 'Today',
      students: const [],
      capacity: 24,
      primaryTeacherId: 17,
      teacherIds: const [17],
    ),
  );

  @override
  Future<List<ContentFileInfo>> contentFiles() async => List.generate(40, (
    index,
  ) {
    final published = index == 0;
    return ContentFileInfo(
      id: index + 1,
      title:
          'A comprehensive language learning resource with a long title ${index + 1}',
      contentType: published ? 'video/mp4' : 'application/pdf',
      sizeBytes: 2048 * (index + 1),
      status: published
          ? 'clean'
          : index.isEven
          ? 'pending'
          : 'rejected',
      locationName: 'International curriculum collection',
      author: 'Academic content team with a long display name',
      thumbnailUrl: '',
      downloadable: index.isEven,
      createdAt: DateTime(2026, 8, 12).subtract(Duration(days: index)),
      teacherApproved: published,
      managerApproved: published,
      rejectReason: '',
    );
  });

  @override
  Future<List<LibraryMaterialInfo>> libraryMaterials() async => const [];

  @override
  Future<List<ContentFolderInfo>> contentFolders() async => const [
    ContentFolderInfo(
      id: 1,
      libraryId: 1,
      libraryName: 'Staff library',
      name: 'English',
      parentId: null,
      parentName: '',
      libraryVisibility: 'tenant',
      libraryCohortId: null,
      libraryCohortName: '',
    ),
  ];

  @override
  Future<List<StaffTask>> tasks({bool mineOnly = false}) async => List.generate(
    35,
    (index) => StaffTask(
      id: 'task-$index',
      title: 'Follow up on the detailed operational task ${index + 1}',
      description:
          'A longer task explanation that must remain readable at large text sizes.',
      due: DateTime(2026, 8, 20, 14).toIso8601String(),
      assignee: _account.fullName,
      creator: 'Operations lead',
      stage: TaskStage.todo,
      highPriority: index.isEven,
    ),
  );

  @override
  Future<List<NotificationInfo>> notifications() async {
    if (failNotifications) {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'Offline',
      );
    }
    return List.generate(
      20,
      (index) => NotificationInfo(
        id: index + 1,
        eventType: index == 0 ? 'cohorts.announcement' : 'operations',
        title: 'Important operational notification ${index + 1}',
        body: 'Detailed notification body for the current staff member.',
        data: const {},
        readAt: null,
        createdAt: DateTime(2026, 8, 12, 10),
      ),
    );
  }

  @override
  Future<void> markNotificationRead(int notificationId) async {
    markReadCalls += 1;
  }

  @override
  Future<TeacherDashboardData> teacherDashboard() async =>
      const TeacherDashboardData(
        groupsCount: 7,
        studentsCount: 123,
        nextLessons: [],
        nextMeeting: {},
      );

  @override
  Future<List<FeatureAvailabilityInfo>> featureAvailability() async => const [
    FeatureAvailabilityInfo(
      feature: 'ai',
      status: FeatureAvailabilityStatus.available,
    ),
    FeatureAvailabilityInfo(
      feature: 'notifications',
      status: FeatureAvailabilityStatus.available,
    ),
    FeatureAvailabilityInfo(
      feature: 'attendance',
      status: FeatureAvailabilityStatus.available,
    ),
    FeatureAvailabilityInfo(
      feature: 'library',
      status: FeatureAvailabilityStatus.available,
    ),
    FeatureAvailabilityInfo(
      feature: 'printing',
      status: FeatureAvailabilityStatus.available,
    ),
    FeatureAvailabilityInfo(
      feature: 'tasks',
      status: FeatureAvailabilityStatus.available,
    ),
  ];

  @override
  Future<List<MeetingInfo>> upcomingMeetings() async => List.generate(
    12,
    (index) => MeetingInfo(
      id: index + 1,
      title: 'Staff coordination meeting ${index + 1}',
      agenda: 'Weekly coordination',
      branchName: 'Chilonzor',
      startsAt: DateTime(2026, 8, 14 + index, 9),
      endsAt: DateTime(2026, 8, 14 + index, 10),
      location: 'Conference room with a long location name',
      status: 'scheduled',
    ),
  );

  @override
  Future<List<CrmLeadInfo>> crmLeads() async => List.generate(
    45,
    (index) => CrmLeadInfo(
      id: index + 1,
      studentName: 'Prospective learner with a long name ${index + 1}',
      phone: '+998 90 000 00 00',
      branchName: 'Chilonzor central branch',
      departmentName: 'English language department',
      stageName: 'Consultation and placement assessment',
      state: 'active',
      nextFollowUpAt: DateTime(2026, 8, 13, 11),
    ),
  );

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _teacherAccount = StaffAccount(
  id: 17,
  principalKind: 'teacher',
  username: 'teacher.aziza',
  fullName: 'Aziza Karimova',
  phone: '+998900000000',
  email: 'aziza@example.test',
  preferredLanguage: 'uz',
  mustChangePassword: false,
  memberships: [
    RoleMembership(
      id: 1,
      name: 'Teacher',
      slug: 'teacher',
      kind: 'teacher',
      branchName: 'Chilonzor',
      departmentName: 'English',
      branchId: 3,
      departmentId: 4,
    ),
  ],
  permissions: {
    'cohorts:read',
    'content:read',
    'content:write',
    'tasks:read',
    'notifications:read',
  },
  readOnly: false,
);

const _salesAccount = StaffAccount(
  id: 22,
  principalKind: 'staff',
  username: 'sales.nodira',
  fullName: 'Nodira Saidova',
  phone: '+998901111111',
  email: 'nodira@example.test',
  preferredLanguage: 'uz',
  mustChangePassword: false,
  memberships: [
    RoleMembership(
      id: 2,
      name: 'Sales consultant',
      slug: 'sales',
      kind: 'staff',
      branchName: 'Chilonzor',
      departmentName: 'Operations',
      branchId: 3,
      departmentId: 5,
    ),
  ],
  permissions: {'crm:read', 'tasks:read'},
  readOnly: false,
);

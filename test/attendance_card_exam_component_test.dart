import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/features/groups/attendance_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'attendance, exam and duration copy is localized in every app language',
    () {
      for (final locale in AppLocalizations.supportedLocales) {
        final translations = AppLocalizations(locale);
        for (final key in const [
          'feedbackCard',
          'smartCard',
          'warningCard',
          'skillBreakdown',
          'overallScore',
          'durationHoursMinutes',
          'durationMinutes',
        ]) {
          expect(
            translations.tr(key),
            isNot(key),
            reason: '${locale.languageCode}: $key',
          );
        }
        expect(
          translations.format('durationHoursMinutes', {
            'hours': 1,
            'minutes': 25,
          }),
          isNot(contains('{hours}')),
        );
      }
    },
  );

  test('attendance and result contracts parse authoritative detail only', () {
    final record = AttendanceRecordInfo.fromJson({
      'id': 4,
      'student': 7,
      'student_name': 'Madina',
      'lesson': 8,
      'lesson_starts_at': '2026-08-12T10:00:00Z',
      'status': 'present',
      'note': '',
      'card_type': 'smart',
    });
    final result = ExamResultInfo.fromJson({
      'student': 7,
      'student_name': 'Madina',
      'score': '81.00',
      'note': 'Good progress',
      'components': [
        {'name': 'Listening', 'score': '67', 'max_score': '100'},
        {'name': '', 'score': '2', 'max_score': '5'},
      ],
    });

    expect(record.cardType, 'smart');
    expect(record.hasIssuedCard, isTrue);
    expect(result.score, 81);
    expect(result.components, hasLength(1));
    expect(result.components.single.name, 'Listening');
    expect(result.components.single.fraction, .67);
  });

  testWidgets(
    'teacher can preserve, change and clear lesson cards on a compact accessible layout',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _EvidenceGateway();
      final controller = await _signedInController(gateway);
      final lesson = _lesson();
      final initial = AttendanceRecordInfo(
        id: 5,
        studentId: 7,
        studentName: 'Madina Akramova',
        lessonId: lesson.id,
        lessonStartsAt: lesson.startsAt,
        status: 'present',
        note: '',
        cardType: 'smart',
      );

      await tester.pumpWidget(
        _testApp(
          controller,
          TakeAttendancePage(
            group: _group(),
            lesson: lesson,
            initialRecords: [initial],
          ),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      final smartChip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Smart card'),
      );
      expect(smartChip.selected, isTrue);

      final warningChip = find.widgetWithText(ChoiceChip, 'Warning card');
      tester.widget<ChoiceChip>(warningChip).onSelected!(true);
      await tester.pump();
      await tester.ensureVisible(find.text('Save attendance'));
      await tester.tap(find.text('Save attendance'));
      await tester.pumpAndSettle();

      expect(gateway.saved, hasLength(1));
      expect(gateway.saved.single['card_type'], 'warning');
      expect(gateway.saved.single['status'], 'present');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'exam history renders real component scores responsively and accessibly',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final gateway = _EvidenceGateway();
      final controller = await _signedInController(gateway);
      final semantics = tester.ensureSemantics();

      await tester.pumpWidget(
        _testApp(
          controller,
          AttendancePage(group: _group(), initialExamTab: true),
          textScale: 2,
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('August checkpoint'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('August checkpoint'), findsOneWidget);

      await tester.tap(find.text('August checkpoint'));
      await tester.pumpAndSettle();

      expect(find.text('Skill breakdown'), findsOneWidget);
      expect(find.text('Listening'), findsOneWidget);
      expect(find.bySemanticsLabel('Listening: 67 / 100'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

Future<AppController> _signedInController(_EvidenceGateway gateway) async {
  final controller = await AppController.load(
    gateway: gateway,
    restoreSession: false,
  );
  await controller.signIn(username: 'teacher.aziza', password: 'password');
  return controller;
}

Widget _testApp(
  AppController controller,
  Widget home, {
  double textScale = 1,
}) => AppControllerScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light(controller.accent),
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: home,
    ),
  ),
);

LearningGroup _group() => LearningGroup(
  id: '12',
  remoteId: 12,
  branchId: 2,
  name: 'Aurora B2',
  course: 'English',
  level: 'B2',
  studyMonth: 3,
  schedule: 'Mon · Wed · Fri',
  room: 'A-204',
  branch: 'Oybek',
  department: 'English',
  mainTeacher: 'Aziza Karimova',
  progress: .6,
  attendance: .9,
  nextLesson: '',
  students: const [
    Student(
      id: '7',
      name: 'Madina Akramova',
      phone: '',
      guardian: '',
      guardianPhone: '',
      birthDate: '',
      joinedDate: '',
    ),
  ],
);

LessonInfo _lesson() {
  final now = DateTime.now();
  return LessonInfo(
    id: 55,
    cohortId: 12,
    cohortName: 'Aurora B2',
    title: 'English',
    roomName: 'A-204',
    typeName: 'Lesson',
    startsAt: now.subtract(const Duration(minutes: 30)),
    endsAt: now.add(const Duration(minutes: 30)),
    status: 'scheduled',
  );
}

class _EvidenceGateway implements StarforgeGateway {
  List<Map<String, Object?>> saved = [];

  @override
  Future<LoginSession> login(String username, String password) async =>
      const LoginSession(
        access: 'session',
        principalKind: 'teacher',
        mustChangePassword: false,
      );

  @override
  Future<StaffAccount> currentAccount() async => _account;

  @override
  Future<AttendanceMonth> attendanceForMonth(
    int groupId,
    DateTime month,
  ) async => AttendanceMonth(
    month: month,
    lessons: const [],
    records: const [],
    rate: 0,
    students: const [],
  );

  @override
  Future<List<ExamInfo>> examsForGroup(int groupId) async => [
    ExamInfo(
      id: 9,
      title: 'August checkpoint',
      date: DateTime.now(),
      maxScore: 100,
      published: true,
      subjectName: 'English',
      termName: 'Month 3',
      typeName: 'Progress exam',
    ),
  ];

  @override
  Future<List<ExamResultInfo>> examResults(int examId) async => const [
    ExamResultInfo(
      studentId: 7,
      studentName: 'Madina Akramova',
      score: 81,
      note: 'Good progress',
      components: [
        ExamSkillComponentInfo(name: 'Listening', score: 67, maxScore: 100),
      ],
    ),
  ];

  @override
  Future<List<AttendanceRecordInfo>> markAttendance(
    int lessonId,
    List<Map<String, Object?>> records,
  ) async {
    saved = records;
    return const [];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _account = StaffAccount(
  id: 1,
  principalKind: 'teacher',
  username: 'teacher.aziza',
  fullName: 'Aziza Karimova',
  phone: '',
  email: '',
  preferredLanguage: 'en',
  mustChangePassword: false,
  memberships: [
    RoleMembership(
      id: 1,
      name: 'Teacher',
      slug: 'teacher',
      kind: 'teacher',
      branchName: 'Oybek',
      departmentName: 'English',
      branchId: 2,
      departmentId: 3,
    ),
  ],
  permissions: {
    'attendance:read',
    'attendance:write',
    'academics:read',
    'academics:write',
    'cohorts:read',
    'students:read',
  },
  readOnly: false,
);

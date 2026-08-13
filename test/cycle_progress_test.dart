import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/features/groups/group_detail_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'cohort list and cycle endpoint map only authoritative progress',
    () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        if (request.url.path == '/api/v1/cohorts/') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'id': 17,
                  'name': 'English A2',
                  'level': 'Elementary',
                  'study_month': 2,
                  'lesson_cycle_length': 8,
                  'start_date': '2026-08-01',
                  'end_date': '2026-12-01',
                  'teachers': <Object?>[],
                },
              ],
              'pagination': {'has_next': false},
            }),
            200,
          );
        }
        if (request.url.path == '/api/v1/cohorts/17/cycle-progress/') {
          return http.Response(
            jsonEncode({'success': true, 'data': _cycleJson()}),
            200,
          );
        }
        expect(request.url.path, '/api/v1/cohorts/17/teaching-progress/');
        expect(request.method, 'PATCH');
        expect(jsonDecode(request.body), {
          'level': 'Pre-intermediate',
          'study_month': 3,
          'lesson_cycle_length': 12,
        });
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'cohort': 17,
              'level': 'Pre-intermediate',
              'study_month': 3,
              'lesson_cycle_length': 12,
              'updated_at': '2026-08-12T12:00:00Z',
            },
          }),
          200,
        );
      });
      final gateway = RemoteStarforgeGateway(
        client: client,
        sessionStore: MemorySessionStore(access: 'access'),
        baseUrl: 'https://example.test',
      );

      final groups = await gateway.groups();
      final progress = await gateway.cohortCycleProgress(17);
      final updated = await gateway.updateCohortTeachingProgress(
        cohortId: 17,
        level: 'Pre-intermediate',
        studyMonth: 3,
        lessonCycleLength: 12,
      );

      expect(groups.single.lessonCycleLength, 8);
      expect(groups.single.studyMonth, 2);
      expect(progress.completedLessons, 7);
      expect(progress.currentStudyMonth, 2);
      expect(progress.completedInCurrentCycle, 7);
      expect(progress.examDayDue, isTrue);
      expect(progress.examReminderDue, isTrue);
      expect(progress.completionDataComplete, isFalse);
      expect(progress.nextScheduledLesson?.cycleLessonNumber, 8);
      expect(updated.level, 'Pre-intermediate');
      expect(updated.studyMonth, 3);
      expect(updated.lessonCycleLength, 12);
      expect(requests.map((uri) => uri.path), [
        '/api/v1/cohorts/',
        '/api/v1/cohorts/17/cycle-progress/',
        '/api/v1/cohorts/17/teaching-progress/',
      ]);
    },
  );

  test('cycle parser rejects arithmetic that invents progress', () {
    final invalid = _cycleJson()..['completed_in_current_cycle'] = 6;
    expect(
      () => CohortCycleProgressInfo.fromJson(invalid),
      throwsFormatException,
    );
  });

  testWidgets('cycle and exam evidence fits narrow 200 percent text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final gateway = _CycleGateway();
    final controller = await AppController.load(
      gateway: gateway,
      restoreSession: false,
    );
    expect(
      await controller.signIn(username: 'teacher', password: 'password'),
      AuthResult.success,
    );
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    final scroll = find.byType(CustomScrollView);
    for (var attempt = 0; attempt < 12; attempt++) {
      if (find
          .text('The next completed lesson is the exam lesson')
          .evaluate()
          .isNotEmpty) {
        break;
      }
      await tester.drag(scroll, const Offset(0, -260));
      await tester.pump();
    }

    expect(find.text('Lesson cycle'), findsOneWidget);
    expect(
      find.text('The next completed lesson is the exam lesson'),
      findsOneWidget,
    );
    expect(
      find.textContaining('Aug 15, 2026', findRichText: true),
      findsOneWidget,
    );
    expect(find.text('Month 2'), findsOneWidget);
    expect(find.byTooltip('Update month & level'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Update month & level'));
    await tester.pump();
    await tester.tap(find.byTooltip('Update month & level'));
    await tester.pumpAndSettle();
    expect(find.text('Update month & level'), findsOneWidget);
    final fields = find.byType(TextFormField);
    expect(fields, findsNWidgets(2));
    await tester.enterText(fields.at(0), 'Pre-intermediate');
    await tester.enterText(fields.at(1), '5');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(gateway.updatedLevel, 'Pre-intermediate');
    expect(gateway.updatedMonth, 5);
    expect(find.text('Month 5'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

Map<String, dynamic> _cycleJson() => {
  'cohort': 17,
  'current_level': 'Elementary',
  'current_study_month': 2,
  'lesson_cycle_length': 8,
  'completed_lessons': 7,
  'completed_cycles': 0,
  'completed_in_current_cycle': 7,
  'next_cycle_lesson_number': 8,
  'lessons_remaining_in_cycle': 1,
  'exam_day_due': true,
  'exam_reminder_due': true,
  'exam_reminder_window_days': 7,
  'next_scheduled_lesson': {
    'id': 88,
    'title': 'Cycle assessment',
    'starts_at': '2026-08-15T10:30:00Z',
    'ends_at': '2026-08-15T12:00:00Z',
    'room': 3,
    'room_name': 'Room 204',
    'teacher': 7,
    'teacher_name': 'Taylor Teacher',
    'cycle_lesson_number': 8,
    'is_cycle_exam_day': true,
  },
  'past_scheduled_lessons_without_completion': 1,
  'completion_data_complete': false,
  'level_progression_mode': 'manual',
  'automatic_level_progression': false,
};

Widget _harness(AppController controller) => AppControllerScope(
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
      data: const MediaQueryData(
        size: Size(320, 568),
        textScaler: TextScaler.linear(2),
        disableAnimations: true,
      ),
      child: const GroupDetailPage(group: _group),
    ),
  ),
);

const _group = LearningGroup(
  id: '17',
  remoteId: 17,
  name: 'English A2',
  course: 'English',
  level: 'Elementary',
  studyMonth: null,
  schedule: '',
  room: 'Room 204',
  branch: 'Central',
  department: 'Languages',
  mainTeacher: 'Taylor Teacher',
  progress: null,
  attendance: null,
  nextLesson: '',
  students: [],
  primaryTeacherId: 7,
  lessonCycleLength: 8,
);

class _CycleGateway
    implements
        StarforgeGateway,
        CohortCycleProgressGateway,
        CohortTeachingProgressGateway {
  String updatedLevel = 'Elementary';
  int updatedMonth = 2;
  int updatedCycleLength = 8;

  static const _account = StaffAccount(
    id: 7,
    principalKind: 'teacher',
    username: 'teacher',
    fullName: 'Taylor Teacher',
    phone: '',
    email: '',
    preferredLanguage: 'en',
    mustChangePassword: false,
    memberships: [],
    permissions: {
      'cohorts:read',
      'attendance:read',
      'academics:read',
      'academics:write',
    },
    readOnly: false,
  );

  @override
  Future<LoginSession> login(String username, String password) async =>
      const LoginSession(
        access: 'access',
        principalKind: 'teacher',
        mustChangePassword: false,
      );

  @override
  Future<StaffAccount> currentAccount() async => _account;

  @override
  Future<List<Student>> studentsForGroup(int groupId) async => const [];

  @override
  Future<AttendanceMonth> attendanceForMonth(
    int groupId,
    DateTime month,
  ) async => AttendanceMonth.empty(month);

  @override
  Future<CohortCycleProgressInfo> cohortCycleProgress(int cohortId) async {
    final data = _cycleJson()
      ..['current_level'] = updatedLevel
      ..['current_study_month'] = updatedMonth
      ..['lesson_cycle_length'] = updatedCycleLength;
    if (updatedCycleLength == 12) {
      data
        ..['completed_in_current_cycle'] = 7
        ..['completed_cycles'] = 0
        ..['next_cycle_lesson_number'] = 8
        ..['lessons_remaining_in_cycle'] = 5
        ..['exam_day_due'] = false
        ..['exam_reminder_due'] = false;
      (data['next_scheduled_lesson'] as Map<String, dynamic>)
        ..['cycle_lesson_number'] = 8
        ..['is_cycle_exam_day'] = false;
    }
    return CohortCycleProgressInfo.fromJson(data);
  }

  @override
  Future<CohortTeachingProgressInfo> updateCohortTeachingProgress({
    required int cohortId,
    required String level,
    required int studyMonth,
    required int lessonCycleLength,
  }) async {
    updatedLevel = level;
    updatedMonth = studyMonth;
    updatedCycleLength = lessonCycleLength;
    return CohortTeachingProgressInfo.fromJson({
      'cohort': cohortId,
      'level': level,
      'study_month': studyMonth,
      'lesson_cycle_length': lessonCycleLength,
      'updated_at': '2026-08-12T12:00:00Z',
    });
  }

  @override
  Future<void> clearSession() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

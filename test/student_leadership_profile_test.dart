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
import 'package:starforge_staff/features/groups/student_detail_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'student leadership profile uses scoped read endpoint and maps sections',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'GET');
        expect(request.url.path, '/api/v1/students/17/leadership-profile/');
        expect(request.url.queryParameters, isEmpty);
        expect(request.headers['Authorization'], 'Bearer test-access');
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'identity': {
                'email': 'student@example.test',
                'status': 'active',
                'academic_level': 'B1',
                'location': 'Chilonzor',
                'previous_school': 'School 42',
                'branch': {'id': 3, 'name': 'Central'},
                'current_group': {'id': 7, 'name': 'Orion', 'level': 'B1'},
              },
              'attendance': {
                'present': 8,
                'late': 1,
                'absent': 2,
                'excused': 1,
                'countable_sessions': 11,
                'attendance_rate_fraction': .8182,
                'current_attendance_streak': 3,
              },
              'learning': {
                'recent_exam_results': [
                  {
                    'exam': {
                      'id': 5,
                      'title': 'August exam',
                      'date': '2026-08-08',
                    },
                    'subject': {'id': 2, 'name': 'English'},
                    'score': '78.00',
                    'maximum': '100.00',
                  },
                ],
                'assignments': {
                  'assigned': 6,
                  'completed': 4,
                  'open': 2,
                  'late': 1,
                },
              },
              'family': {
                'guardians': [
                  {
                    'name': 'Parent One',
                    'relationship': 'mother',
                    'is_primary': true,
                    'contacts': {
                      'phone': '+998901234567',
                      'email': 'parent@example.test',
                    },
                  },
                ],
              },
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

      final profile = await gateway.studentLeadershipProfile(17);

      expect(profile.email, 'student@example.test');
      expect(profile.attendance?.rate, closeTo(.8182, .00001));
      expect(profile.recentExams.single.title, 'August exam');
      expect(profile.assignments?.completed, 4);
      expect(profile.guardians.single.phone, '+998901234567');
      expect(profile.learningAvailable, isTrue);
      expect(profile.familyAvailable, isTrue);
    },
  );

  test(
    'omitted protected sections stay unavailable instead of looking empty',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'identity': {
                'email': '',
                'status': 'active',
                'academic_level': '',
                'location': '',
                'previous_school': '',
                'branch': {'id': 1, 'name': 'Central'},
                'current_group': null,
              },
              'coverage': {
                'learning': {'status': 'not_authorized'},
                'family': {'status': 'not_authorized'},
              },
            },
          }),
          200,
        ),
      );
      final gateway = RemoteStarforgeGateway(
        client: client,
        sessionStore: MemorySessionStore(access: 'test-access'),
        baseUrl: 'https://example.test',
      );

      final profile = await gateway.studentLeadershipProfile(17);

      expect(profile.learningAvailable, isFalse);
      expect(profile.familyAvailable, isFalse);
      expect(profile.attendance, isNull);
      expect(profile.recentExams, isEmpty);
      expect(profile.guardians, isEmpty);
    },
  );

  testWidgets('loaded student profile remains usable at 200% text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      if (request.url.path == '/api/v1/auth/role-login/') {
        return _response({
          'access': 'test-access',
          'role': 'teacher',
          'must_change_password': false,
        });
      }
      if (request.url.path == '/api/v1/users/me/') {
        return _response({
          'id': 8,
          'principal_kind': 'teacher',
          'username': 'teacher',
          'full_name': 'Teacher One',
          'phone': '',
          'email': '',
          'preferred_language': 'en',
          'must_change_password': false,
          'read_only_session': false,
          'effective_permissions': [
            'students:read',
            'messaging:write',
            'approvals:write',
          ],
          'role_memberships': [
            {
              'id': 1,
              'account_type_name': 'Teacher',
              'account_type_slug': 'teacher',
              'account_kind': 'teacher',
              'branch_name': 'Central',
              'department_name': 'English',
              'branch': 1,
              'department': 1,
            },
          ],
        });
      }
      if (request.url.path == '/api/v1/students/17/leadership-profile/') {
        return _response({
          'identity': {
            'email': 'student@example.test',
            'status': 'active',
            'academic_level': 'B1',
            'location': 'Chilonzor',
            'previous_school': 'School 42',
            'branch': {'id': 1, 'name': 'Central'},
            'current_group': {'id': 7, 'name': 'Orion', 'level': 'B1'},
          },
          'attendance': {
            'present': 8,
            'late': 1,
            'absent': 2,
            'excused': 1,
            'countable_sessions': 11,
            'attendance_rate_fraction': .8182,
            'current_attendance_streak': 3,
          },
          'learning': {
            'recent_exam_results': [
              {
                'exam': {'id': 5, 'title': 'August exam', 'date': '2026-08-08'},
                'subject': {'id': 2, 'name': 'English'},
                'score': '78.00',
                'maximum': '100.00',
              },
            ],
            'assignments': {
              'assigned': 6,
              'completed': 4,
              'open': 2,
              'late': 1,
            },
          },
          'family': {
            'guardians': [
              {
                'name': 'Parent One',
                'relationship': 'mother',
                'is_primary': true,
                'contacts': {'phone': '+998901234567', 'email': ''},
              },
            ],
          },
        });
      }
      return http.Response('Not found', 404);
    });
    final controller = await AppController.load(
      gateway: RemoteStarforgeGateway(
        client: client,
        sessionStore: MemorySessionStore(),
        baseUrl: 'https://example.test',
      ),
      restoreSession: false,
    );
    expect(
      await controller.signIn(username: 'teacher', password: 'valid-password'),
      AuthResult.success,
    );
    const student = Student(
      id: '17',
      name: 'Student One',
      phone: '',
      guardian: '',
      guardianPhone: '',
      birthDate: '',
      joinedDate: '',
      attendance: null,
      lastExam: null,
    );
    const group = LearningGroup(
      id: '7',
      name: 'Orion',
      course: 'English',
      level: 'B1',
      studyMonth: 1,
      schedule: '',
      room: 'A1',
      branch: 'Central',
      department: 'English',
      mainTeacher: 'Teacher One',
      progress: 0,
      attendance: 0,
      nextLesson: '',
      students: [student],
      remoteId: 7,
    );
    await tester.pumpWidget(
      AppControllerScope(
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
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              disableAnimations: true,
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const StudentDetailPage(student: student, group: group),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final scrollable = find.byType(SingleChildScrollView);
    for (var index = 0; index < 10; index++) {
      await tester.drag(scrollable, const Offset(0, -250));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text('Parent One'), findsOneWidget);
    expect(find.text('August exam'), findsOneWidget);
  });
}

http.Response _response(Object? data) => http.Response(
  jsonEncode({'success': true, 'data': data}),
  200,
  headers: const {'content-type': 'application/json'},
);

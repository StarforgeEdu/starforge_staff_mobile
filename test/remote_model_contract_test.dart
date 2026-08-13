import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  group('fail-closed operational identity contracts', () {
    test('integer parsing rejects fractional and non-finite values', () {
      expect(jsonInt(7), 7);
      expect(jsonInt(' 7 '), 7);
      expect(jsonInt(7.0), 7);
      expect(jsonInt(7.5), isNull);
      expect(jsonInt(double.nan), isNull);
      expect(jsonInt(double.infinity), isNull);
    });

    test('operational rows never turn missing identifiers into zero', () {
      final invalidParsers = <Object? Function()>[
        () => StudentAttendanceSummary.fromJson(const {}),
        () => ExamResultInfo.fromJson(const {}),
        () => ContentFolderInfo.fromJson(const {'id': 1}),
        () => LibraryMaterialInfo.fromJson(const {}),
        () => PrinterInfo.fromJson(const {'id': 1}),
        () => PayrollPayslipInfo.fromJson(const {}),
        () => CrmLeadInfo.fromJson(const {}),
        () => FinanceInvoiceInfo.fromJson(const {}),
        () => CashierShiftInfo.fromJson(const {}),
        () => taskFromJson(const {}),
      ];

      for (final parse in invalidParsers) {
        expect(parse, throwsFormatException);
      }
    });

    test(
      'print counts and optional foreign keys reject poisoned zero values',
      () {
        expect(
          () => PrintJobInfo.fromJson({
            'id': 1,
            'pages': 0,
            'copies': 1,
            'created_at': '2026-08-12T10:00:00Z',
          }),
          throwsFormatException,
        );
        expect(
          () => groupFromJson(const {'id': 1, 'branch': 0}),
          throwsFormatException,
        );
      },
    );
  });

  group('feature availability contracts', () {
    test(
      'staff availability uses the privacy-minimized production route',
      () async {
        final client = MockClient((request) async {
          expect(request.method, 'GET');
          expect(request.url.path, '/api/v1/org/app-status/');
          expect(request.headers['Authorization'], 'Bearer staff-access');
          return http.Response(
            jsonEncode({
              'success': true,
              'data': {
                'features': [
                  {'feature': 'ai', 'status': 'degraded'},
                  {'feature': 'notifications', 'status': 'available'},
                  {'feature': 'printing', 'status': 'unavailable'},
                ],
              },
            }),
            200,
          );
        });
        final gateway = RemoteStarforgeGateway(
          client: client,
          sessionStore: MemorySessionStore(access: 'staff-access'),
          baseUrl: 'https://example.test',
        );

        final features = await gateway.featureAvailability();

        expect(features.map((item) => item.feature), [
          'ai',
          'notifications',
          'printing',
        ]);
        expect(features[0].status, FeatureAvailabilityStatus.degraded);
        expect(features[1].isAvailable, isTrue);
        expect(features[2].status, FeatureAvailabilityStatus.unavailable);
      },
    );

    test('unknown status fails closed as unavailable', () {
      final feature = FeatureAvailabilityInfo.fromJson({
        'feature': 'ai',
        'status': 'future-state',
      });

      expect(feature.status, FeatureAvailabilityStatus.unavailable);
    });
  });

  group('attendance contracts', () {
    test(
      'month history follows every attendance page beyond the generic limit',
      () async {
        var attendancePages = 0;
        final client = MockClient((request) async {
          Map<String, Object?> pageEnvelope(
            List<Map<String, Object?>> data, {
            required bool hasNext,
          }) => {
            'success': true,
            'data': data,
            'pagination': {'has_next': hasNext},
          };

          if (request.url.path == '/api/v1/schedule/lessons/') {
            return http.Response(
              jsonEncode(pageEnvelope([], hasNext: false)),
              200,
            );
          }
          if (request.url.path == '/api/v1/attendance/records/') {
            final page = int.parse(request.url.queryParameters['page']!);
            attendancePages++;
            return http.Response(
              jsonEncode(
                pageEnvelope([
                  {
                    'id': page,
                    'student': page,
                    'student_name': 'Student $page',
                    'lesson': 44,
                    'lesson_starts_at': '2026-08-12T10:00:00Z',
                    'status': 'present',
                    'note': '',
                    'card_type': '',
                  },
                ], hasNext: page < 51),
              ),
              200,
            );
          }
          if (request.url.path == '/api/v1/attendance/cohorts/7/dashboard/') {
            return http.Response(
              jsonEncode({
                'success': true,
                'data': {'rate': 100, 'students': <Object>[]},
              }),
              200,
            );
          }
          return http.Response('', 404);
        });
        final gateway = RemoteStarforgeGateway(
          client: client,
          sessionStore: MemorySessionStore(access: 'staff-access'),
          baseUrl: 'https://example.test',
        );

        final month = await gateway.attendanceForMonth(7, DateTime(2026, 8));

        expect(attendancePages, 51);
        expect(month.records, hasLength(51));
        expect(month.records.last.id, 51);
      },
    );

    test(
      'bounded lists fail explicitly instead of returning partial data',
      () async {
        var pages = 0;
        final client = MockClient((request) async {
          pages++;
          return http.Response(
            jsonEncode({
              'success': true,
              'data': <Object>[],
              'pagination': {'has_next': true},
            }),
            200,
          );
        });
        final gateway = RemoteStarforgeGateway(
          client: client,
          sessionStore: MemorySessionStore(access: 'staff-access'),
          baseUrl: 'https://example.test',
        );

        await expectLater(
          gateway.groups(),
          throwsA(
            isA<StarforgeException>().having(
              (error) => error.code,
              'code',
              'response_too_large',
            ),
          ),
        );
        expect(pages, 50);
      },
    );

    test('new students remain unmarked until a teacher chooses a state', () {
      final student = studentFromJson({
        'id': 17,
        'full_name': 'Madina Akramova',
      });

      expect(student.state, StudentState.unmarked);
      expect(student.attendance, isNull);
      expect(student.lastExam, isNull);
    });

    test('a partially recorded roster is not a complete register', () {
      final lessonDate = DateTime(2026, 8, 12, 10);
      final month = AttendanceMonth(
        month: DateTime(2026, 8),
        lessons: const [],
        records: [
          AttendanceRecordInfo(
            id: 1,
            studentId: 17,
            studentName: 'Madina',
            lessonId: 44,
            lessonStartsAt: lessonDate,
            status: 'present',
            note: '',
          ),
        ],
        rate: 100,
        students: const [
          StudentAttendanceSummary(
            studentId: 17,
            name: 'Madina',
            present: 1,
            absent: 0,
            late: 0,
            excused: 0,
            total: 1,
            percentPresent: 100,
          ),
          StudentAttendanceSummary(
            studentId: 18,
            name: 'Aziz',
            present: 0,
            absent: 0,
            late: 0,
            excused: 0,
            total: 0,
            percentPresent: 0,
          ),
        ],
      );

      expect(month.isRegisterComplete(44), isFalse);
      expect(month.isRegisterComplete(44, expectedRosterCount: 1), isFalse);
    });

    test(
      'a register is complete only after every roster student is recorded',
      () {
        final lessonDate = DateTime(2026, 8, 12, 10);
        final month = AttendanceMonth(
          month: DateTime(2026, 8),
          lessons: const [],
          records: [
            AttendanceRecordInfo(
              id: 1,
              studentId: 17,
              studentName: 'Madina',
              lessonId: 44,
              lessonStartsAt: lessonDate,
              status: 'present',
              note: '',
            ),
            AttendanceRecordInfo(
              id: 2,
              studentId: 18,
              studentName: 'Aziz',
              lessonId: 44,
              lessonStartsAt: lessonDate,
              status: 'absent',
              note: '',
            ),
          ],
          rate: 50,
          students: const [
            StudentAttendanceSummary(
              studentId: 17,
              name: 'Madina',
              present: 1,
              absent: 0,
              late: 0,
              excused: 0,
              total: 1,
              percentPresent: 100,
            ),
            StudentAttendanceSummary(
              studentId: 18,
              name: 'Aziz',
              present: 0,
              absent: 1,
              late: 0,
              excused: 0,
              total: 1,
              percentPresent: 0,
            ),
          ],
        );

        expect(month.isRegisterComplete(44), isTrue);
        expect(month.isRegisterComplete(44, expectedRosterCount: 3), isFalse);
      },
    );

    test('duplicate records do not make a partial register complete', () {
      final lessonDate = DateTime(2026, 8, 12, 10);
      final month = AttendanceMonth(
        month: DateTime(2026, 8),
        lessons: const [],
        records: [
          AttendanceRecordInfo(
            id: 1,
            studentId: 17,
            studentName: 'Madina',
            lessonId: 44,
            lessonStartsAt: lessonDate,
            status: 'present',
            note: '',
          ),
          AttendanceRecordInfo(
            id: 2,
            studentId: 17,
            studentName: 'Madina',
            lessonId: 44,
            lessonStartsAt: lessonDate,
            status: 'late',
            note: '',
          ),
        ],
        rate: 100,
        students: const [],
      );

      expect(month.isRegisterComplete(44, expectedRosterCount: 2), isFalse);
    });
  });

  group('group and assessment contracts', () {
    test('group keeps its backend branch identity', () {
      final group = groupFromJson({
        'id': 9,
        'name': 'Orion',
        'branch': 3,
        'branch_name': 'Chilonzor',
      });

      expect(group.remoteId, 9);
      expect(group.branchId, 3);
    });

    test('exam keeps subject, term, type and republish state', () {
      final exam = ExamInfo.fromJson({
        'id': 5,
        'title': 'August checkpoint',
        'exam_date': '2026-08-10',
        'max_score': '100.00',
        'is_published': true,
        'subject_name': 'English',
        'term_name': 'Month 2',
        'exam_type_detail': {'id': 2, 'name': 'Progress exam'},
        'requires_republish': true,
      });

      expect(exam.subjectName, 'English');
      expect(exam.termName, 'Month 2');
      expect(exam.typeName, 'Progress exam');
      expect(exam.requiresRepublish, isTrue);
    });
  });

  group('task contracts', () {
    test('principal identities and blocked status survive parsing', () {
      final task = taskFromJson({
        'id': 81,
        'title': 'Prepare level test',
        'status': 'blocked',
        'assignee_principal': {
          'kind': 'teacher',
          'id': 17,
          'display_name': 'Aziza Karimova',
        },
        'created_by': {
          'kind': 'staff',
          'id': 4,
          'display_name': 'Otabek Rahimov',
        },
      });

      expect(task.stage, TaskStage.blocked);
      expect(task.rawStatus, 'blocked');
      expect(
        task.isAssignedTo(principalKind: 'teacher', principalId: 17),
        isTrue,
      );
      expect(task.isCreatedBy(principalKind: 'staff', principalId: 4), isTrue);
    });

    test('cancelled is not collapsed into completed', () {
      final task = taskFromJson({
        'id': 82,
        'title': 'Retired task',
        'status': 'cancelled',
      });

      expect(task.stage, TaskStage.cancelled);
      expect(task.stage, isNot(TaskStage.done));
      expect(task.rawStatus, 'cancelled');
    });
  });
}

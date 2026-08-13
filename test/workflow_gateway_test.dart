import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('staff workflow gateway uses human-facing API contracts', () async {
    final seen = <String>[];
    final client = MockClient((request) async {
      seen.add('${request.method} ${request.url.path}');
      expect(request.headers['Authorization'], 'Bearer test-access');
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/approvals/requests/') {
        expect(request.url.queryParameters['page_size'], '100');
        return _envelope([
          {
            'id': 41,
            'kind': 'leave_request',
            'title': 'Family appointment',
            'description': 'Need the afternoon away.',
            'status': 'pending',
            'amount_uzs': null,
          },
        ]);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/approvals/requests/') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['kind'], 'schedule_change');
        expect(body['branch'], 7);
        expect(body.containsKey('payload'), isTrue);
        return _envelope({
          'id': 42,
          ...body,
          'status': 'pending',
          'decision_note': '',
        }, status: 201);
      }
      if (request.method == 'GET' && request.url.path == '/api/v1/forms/') {
        return _envelope([
          {
            'id': 9,
            'title': 'Weekly feedback',
            'description': 'Help improve the staff week.',
            'status': 'published',
            'is_anonymous': true,
            'allow_multiple': false,
            'response_submitted': false,
            'form_fields': [
              {
                'id': 91,
                'label': 'How was this week?',
                'field_type': 'rating',
                'required': true,
                'options': [],
              },
            ],
          },
        ]);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/forms/9/submit/') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['answers'], [
          {'field': 91, 'value': 5},
        ]);
        return _envelope({'id': 901}, status: 201);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/reports/runs/') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['report_key'], 'attendance');
        expect(body['recipient_ids'], [2001]);
        expect((body['params'] as Map)['cohort_id'], 12);
        return _envelope({
          'id': 77,
          'report_key': 'attendance',
          'format': 'pdf',
          'status': 'queued',
          'download_url': null,
          'error': '',
        }, status: 202);
      }
      if (request.method == 'GET' &&
          request.url.path == '/api/v1/org/branches/') {
        expect(request.url.queryParameters['ordering'], 'name');
        return _envelope([
          {'id': 1, 'name': 'Main Branch', 'is_active': true},
          {'id': 2, 'name': 'Chilonzor', 'is_active': true},
        ]);
      }
      if (request.method == 'POST' &&
          request.url.path == '/api/v1/org/transfers/') {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body['to_branch'], 2);
        expect(body['confirm_impacts'], isTrue);
        expect(body['reason'], isNotEmpty);
        if (body['subject_kind'] == 'cohort') {
          expect(body['subject'], 12);
          expect(body.containsKey('student'), isFalse);
        } else {
          expect(body['subject_kind'], 'student');
          expect(body['student'], 33);
          expect(body.containsKey('subject'), isFalse);
        }
        return _envelope({'id': 81}, status: 201);
      }
      fail('Unexpected request: ${request.method} ${request.url}');
    });
    final gateway = RemoteStarforgeGateway(
      client: client,
      sessionStore: MemorySessionStore(access: 'test-access'),
      baseUrl: 'https://example.test',
    );

    final requests = await gateway.staffRequests();
    expect(requests.single.title, 'Family appointment');

    final created = await gateway.createStaffRequest(
      kind: 'schedule_change',
      title: 'Move Thursday lesson',
      description: 'Please move it to Friday.',
      branchId: 7,
    );
    expect(created.id, 42);

    final forms = await gateway.staffForms();
    expect(forms.single.fields.single.type, 'rating');
    await gateway.submitStaffForm(9, {91: 5});

    final run = await gateway.createStaffReportRun(
      reportKey: 'attendance',
      format: 'pdf',
      params: const {'cohort_id': 12},
      recipientIds: const [2001],
    );
    expect(run.status, 'queued');
    final branches = await gateway.transferBranches();
    expect(branches.map((branch) => branch.name), ['Main Branch', 'Chilonzor']);
    await gateway.transferBranchSubject(
      subjectKind: 'cohort',
      subjectId: 12,
      toBranchId: 2,
      reason: 'Move the teaching group',
      confirmImpacts: true,
    );
    await gateway.transferBranchSubject(
      subjectKind: 'student',
      subjectId: 33,
      toBranchId: 2,
      reason: 'Family changed branch',
      confirmImpacts: true,
    );
    expect(seen, contains('POST /api/v1/forms/9/submit/'));
    expect(
      seen.where((request) => request == 'POST /api/v1/org/transfers/'),
      hasLength(2),
    );
  });
}

http.Response _envelope(Object? data, {int status = 200}) => http.Response(
  jsonEncode({
    'success': true,
    'data': data,
    if (data is List)
      'pagination': {
        'total': data.length,
        'page': 1,
        'page_size': 100,
        'pages': 1,
        'has_next': false,
        'has_prev': false,
      },
  }),
  status,
  headers: const {'content-type': 'application/json'},
);

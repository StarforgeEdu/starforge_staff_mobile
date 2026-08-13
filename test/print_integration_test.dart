import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show SemanticsAction, Tristate;

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
import 'package:starforge_staff/features/print/print_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('remote print contract', () {
    test('uploaded print obtains a grant, uses the injected multipart client, '
        'and creates a UTC-scheduled job', () async {
      final bytes = utf8.encode('STARFORGE-PRINT-CONTENT');
      final directory = await Directory.systemTemp.createTemp(
        'starforge-print-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/handout.pdf');
      await file.writeAsBytes(bytes, flush: true);

      final apiBodies = <Map<String, dynamic>>[];
      Uint8List? multipartBody;
      String? multipartContentType;
      var storageRequests = 0;
      final schedule = DateTime(2026, 8, 20, 10, 30);
      final expectedSchedule = schedule.toUtc().toIso8601String();
      final client = MockClient.streaming((request, bodyStream) async {
        final requestBytes = await bodyStream.toBytes();
        if (request.url.host == 'storage.example') {
          storageRequests++;
          expect(request.method, 'POST');
          expect(request.headers['authorization'], isNull);
          multipartContentType = request.headers['content-type'];
          multipartBody = requestBytes;
          return _streamedResponse(const [], 204);
        }

        expect(request.url.host, 'api.example');
        expect(request.headers['authorization'], 'Bearer test-access');
        expect(request.headers['accept-language'], 'uz');
        final body = jsonDecode(utf8.decode(requestBytes));
        expect(body, isA<Map<String, dynamic>>());
        apiBodies.add((body as Map).cast<String, dynamic>());
        if (request.url.path == '/api/v1/printing/upload-url/') {
          return _jsonResponse({
            'success': true,
            'data': {
              'grant_id': 88,
              'url': 'https://storage.example/print-upload',
              'method': 'POST',
              'fields': {
                'key': 'printing/88/handout.pdf',
                'policy': 'signed-policy',
                'x-amz-signature': 'signed-value',
              },
              'expires_at': '2026-08-12T12:00:00Z',
            },
          });
        }
        expect(request.url.path, '/api/v1/printing/jobs/');
        return _jsonResponse({
          'success': true,
          'data': {
            'id': 901,
            'preferred_printer': 7,
            'status': 'queued',
            'source': 'upload',
            'pages': 12,
            'copies': 3,
            'color': true,
            'duplex': true,
            'created_at': '2026-08-12T06:00:00Z',
            'finished_at': null,
            'scheduled_for': expectedSchedule,
          },
        });
      });
      final gateway = RemoteStarforgeGateway(
        client: client,
        sessionStore: MemorySessionStore(access: 'test-access'),
        baseUrl: 'https://api.example',
      );

      final result = await gateway.submitUploadedPrintJob(
        filePath: file.path,
        filename: 'handout.pdf',
        contentType: 'application/pdf',
        sizeBytes: bytes.length,
        branchId: 3,
        printerId: 7,
        copies: 3,
        color: true,
        duplex: true,
        scheduledFor: schedule,
      );

      expect(apiBodies, hasLength(2));
      expect(apiBodies.first, {
        'branch': 3,
        'filename': 'handout.pdf',
        'content_type': 'application/pdf',
        'size_bytes': bytes.length,
      });
      expect(apiBodies.last, {
        'source': 'upload',
        'source_id': 88,
        'copies': 3,
        'color': true,
        'duplex': true,
        'printer': 7,
        'scheduled_for': expectedSchedule,
      });
      expect(apiBodies.last, isNot(contains('pages')));
      expect(expectedSchedule, endsWith('Z'));
      expect(storageRequests, 1);
      expect(multipartContentType, startsWith('multipart/form-data;'));
      final multipartText = latin1.decode(multipartBody!);
      expect(multipartText, contains('name="key"'));
      expect(multipartText, contains('printing/88/handout.pdf'));
      expect(multipartText, contains('name="policy"'));
      expect(multipartText, contains('signed-policy'));
      expect(multipartText, contains('name="file"'));
      expect(multipartText, contains('filename="handout.pdf"'));
      expect(multipartText, contains('STARFORGE-PRINT-CONTENT'));
      expect(result.id, 901);
      expect(result.pages, 12);
      expect(result.scheduledFor, DateTime.parse(expectedSchedule));
    });

    test('library print creates an exact content-source job', () async {
      Map<String, dynamic>? body;
      final schedule = DateTime.utc(2026, 8, 25, 5, 45);
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/api/v1/printing/jobs/');
        expect(request.headers['Authorization'], 'Bearer test-access');
        body = (jsonDecode(request.body) as Map).cast<String, dynamic>();
        return http.Response(
          jsonEncode({
            'success': true,
            'data': {
              'id': 902,
              'preferred_printer': 11,
              'status': 'queued',
              'source': 'content',
              'pages': 24,
              'copies': 20,
              'color': false,
              'duplex': true,
              'created_at': '2026-08-12T06:00:00Z',
              'finished_at': null,
              'scheduled_for': schedule.toIso8601String(),
            },
          }),
          201,
          headers: const {'content-type': 'application/json'},
        );
      });
      final gateway = RemoteStarforgeGateway(
        client: client,
        sessionStore: MemorySessionStore(access: 'test-access'),
        baseUrl: 'https://api.example',
      );

      final result = await gateway.submitLibraryPrintJob(
        fileId: 42,
        printerId: 11,
        copies: 20,
        color: false,
        duplex: true,
        scheduledFor: schedule,
      );

      expect(body, {
        'source': 'content',
        'source_id': 42,
        'copies': 20,
        'color': false,
        'duplex': true,
        'printer': 11,
        'scheduled_for': '2026-08-25T05:45:00.000Z',
      });
      expect(body, isNot(contains('pages')));
      expect(result.source, 'content');
      expect(result.pages, 24);
    });

    test(
      'uploaded print refuses a file that changed after selection',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'starforge-print-test-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final file = File('${directory.path}/changed.pdf');
        await file.writeAsString('changed');
        var requests = 0;
        final gateway = RemoteStarforgeGateway(
          client: MockClient((request) async {
            requests++;
            return http.Response('', 500);
          }),
          sessionStore: MemorySessionStore(access: 'test-access'),
          baseUrl: 'https://api.example',
        );

        await expectLater(
          gateway.submitUploadedPrintJob(
            filePath: file.path,
            filename: 'changed.pdf',
            contentType: 'application/pdf',
            sizeBytes: 1,
            branchId: 3,
            printerId: 7,
            copies: 1,
            color: false,
            duplex: false,
          ),
          throwsA(
            isA<StarforgeException>().having(
              (error) => error.code,
              'code',
              'file_changed',
            ),
          ),
        );
        expect(requests, 0);
      },
    );
  });

  group('print controller', () {
    test(
      'maps printer capabilities, branch, availability, and job schedule',
      () async {
        final scheduled = DateTime.utc(2026, 8, 19, 5, 30);
        final gateway = _PrintGateway(
          account: _account({'printing:read'}),
          printerData: const [
            PrinterInfo(
              id: 7,
              branchId: 3,
              name: 'Orion Color',
              modelName: 'HP Enterprise',
              supportsColor: true,
              supportsDuplex: true,
              paperSizes: ['A4', 'A3'],
              active: true,
            ),
            PrinterInfo(
              id: 8,
              branchId: 4,
              name: 'Offline Mono',
              modelName: 'Canon',
              supportsColor: false,
              supportsDuplex: false,
              paperSizes: ['A4'],
              active: false,
            ),
          ],
          jobData: [
            PrintJobInfo(
              id: 90,
              printerId: 7,
              status: 'printing',
              source: 'content',
              pages: 8,
              copies: 2,
              color: true,
              duplex: true,
              createdAt: DateTime.utc(2026, 8, 12),
              finishedAt: null,
              scheduledFor: scheduled,
            ),
          ],
        );
        final controller = await _signedInController(gateway);

        final workspace = await controller.loadPrintWorkspace();

        expect(gateway.printerReads, 1);
        expect(gateway.jobReads, 1);
        expect(workspace.printers, hasLength(2));
        expect(workspace.printers.first.branchId, 3);
        expect(workspace.printers.first.location, 'HP Enterprise');
        expect(workspace.printers.first.paper, 'A4, A3');
        expect(workspace.printers.first.supportsColor, isTrue);
        expect(workspace.printers.first.supportsDuplex, isTrue);
        expect(workspace.printers.first.isBusy, isTrue);
        expect(workspace.printers.last.isOffline, isTrue);
        expect(workspace.jobs.single.scheduledFor, scheduled);
      },
    );

    test('does not call print APIs without read or write permission', () async {
      final gateway = _PrintGateway(account: _account(const {}));
      final controller = await _signedInController(gateway);

      expect(
        await controller.loadPrintWorkspace(),
        const PrintWorkspace.empty(),
      );
      expect(gateway.printerReads, 0);
      expect(gateway.jobReads, 0);
      await expectLater(
        controller.submitPrintJob(
          filePath: '/tmp/ignored.pdf',
          filename: 'ignored.pdf',
          contentType: 'application/pdf',
          sizeBytes: 12,
          printer: _printer(),
          copies: 1,
          color: false,
          duplex: false,
        ),
        throwsA(
          isA<StarforgeException>().having(
            (error) => error.code,
            'code',
            'forbidden',
          ),
        ),
      );
      expect(gateway.uploadSubmissions, 0);
    });

    test(
      'rejects unavailable and unsupported printer requests locally',
      () async {
        final gateway = _PrintGateway(account: _account({'printing:write'}));
        final controller = await _signedInController(gateway);

        Future<void> upload(PrinterDevice printer, {bool color = false}) =>
            controller.submitPrintJob(
              filePath: '/tmp/ignored.pdf',
              filename: 'ignored.pdf',
              contentType: 'application/pdf',
              sizeBytes: 12,
              printer: printer,
              copies: 1,
              color: color,
              duplex: false,
            );
        await expectLater(
          upload(_printer(isOffline: true)),
          throwsA(
            isA<StarforgeException>().having(
              (error) => error.code,
              'code',
              'printer_unavailable',
            ),
          ),
        );
        await expectLater(
          upload(_printer(id: '0')),
          throwsA(
            isA<StarforgeException>().having(
              (error) => error.code,
              'code',
              'printer_unavailable',
            ),
          ),
        );
        await expectLater(
          upload(_printer(branchId: 0)),
          throwsA(
            isA<StarforgeException>().having(
              (error) => error.code,
              'code',
              'printer_unavailable',
            ),
          ),
        );
        await expectLater(
          upload(_printer(), color: true),
          throwsA(
            isA<StarforgeException>().having(
              (error) => error.code,
              'code',
              'printer_color_unsupported',
            ),
          ),
        );
        await expectLater(
          controller.submitLibraryPrintJob(
            resource: _resource(),
            printer: _printer(),
            copies: 1,
            color: false,
            duplex: true,
          ),
          throwsA(
            isA<StarforgeException>().having(
              (error) => error.code,
              'code',
              'printer_duplex_unsupported',
            ),
          ),
        );
        expect(gateway.uploadSubmissions, 0);
        expect(gateway.librarySubmissions, 0);
      },
    );

    test('delegates valid upload and clean library print requests', () async {
      final gateway = _PrintGateway(account: _account({'printing:write'}));
      final controller = await _signedInController(gateway);
      final printer = _printer(supportsColor: true, supportsDuplex: true);
      final schedule = DateTime.utc(2026, 8, 28, 6);

      await controller.submitPrintJob(
        filePath: '/tmp/handout.pdf',
        filename: 'handout.pdf',
        contentType: 'application/pdf',
        sizeBytes: 1234,
        printer: printer,
        copies: 4,
        color: true,
        duplex: true,
        scheduledFor: schedule,
      );
      await controller.submitLibraryPrintJob(
        resource: _resource(),
        printer: printer,
        copies: 2,
        color: false,
        duplex: true,
      );

      expect(gateway.lastUpload, {
        'filePath': '/tmp/handout.pdf',
        'filename': 'handout.pdf',
        'contentType': 'application/pdf',
        'sizeBytes': 1234,
        'branchId': 3,
        'printerId': 7,
        'copies': 4,
        'color': true,
        'duplex': true,
        'scheduledFor': schedule,
      });
      expect(gateway.lastLibrary, {
        'fileId': 42,
        'printerId': 7,
        'copies': 2,
        'color': false,
        'duplex': true,
        'scheduledFor': null,
      });
    });
  });

  testWidgets(
    'print page fits narrow 200% text and exposes printer semantics',
    (tester) async {
      tester.view.physicalSize = const Size(320, 568);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final semantics = tester.ensureSemantics();
      final gateway = _PrintGateway(
        account: _account({'printing:read', 'printing:write'}),
        printerData: const [
          PrinterInfo(
            id: 7,
            branchId: 3,
            name: 'Orion color printer',
            modelName: 'Learning center second floor',
            supportsColor: true,
            supportsDuplex: true,
            paperSizes: ['A4'],
            active: true,
          ),
        ],
        jobData: [
          PrintJobInfo(
            id: 77,
            printerId: 7,
            status: 'queued',
            source: 'content',
            pages: 24,
            copies: 20,
            color: false,
            duplex: true,
            createdAt: DateTime.utc(2026, 8, 12, 6),
            finishedAt: null,
            scheduledFor: DateTime.utc(2026, 8, 20, 5, 30),
          ),
        ],
      );
      final controller = await _signedInController(gateway);

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
            home: const PrintPage(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(gateway.printerReads, 1);
      expect(gateway.jobReads, 1);
      for (
        var attempt = 0;
        attempt < 6 && find.text('Orion color printer').evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -140));
        await tester.pumpAndSettle();
      }
      expect(find.text('Orion color printer'), findsOneWidget);
      final printerSemantics = find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.label?.contains('Orion color printer') == true,
      );
      expect(printerSemantics, findsOneWidget);
      final semanticsWidget = tester.widget<Semantics>(printerSemantics);
      expect(semanticsWidget.properties.button, isTrue);
      expect(semanticsWidget.properties.selected, isTrue);
      expect(semanticsWidget.properties.enabled, isTrue);
      final semanticsData = tester
          .getSemantics(printerSemantics)
          .getSemanticsData();
      expect(semanticsData.hasAction(SemanticsAction.tap), isTrue);
      expect(semanticsData.flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.takeException(), isNull);

      await tester.fling(
        find.byType(CustomScrollView),
        const Offset(0, -1200),
        1200,
      );
      await tester.pumpAndSettle();
      expect(find.text('Print now'), findsOneWidget);
      for (
        var attempt = 0;
        attempt < 8 && find.textContaining('24 pages').evaluate().isEmpty;
        attempt++
      ) {
        await tester.drag(find.byType(CustomScrollView), const Offset(0, -180));
        await tester.pumpAndSettle();
      }
      expect(find.textContaining('24 pages'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    },
  );
}

http.StreamedResponse _streamedResponse(List<int> body, int statusCode) =>
    http.StreamedResponse(Stream.value(body), statusCode);

http.StreamedResponse _jsonResponse(Map<String, Object?> body) {
  final bytes = utf8.encode(jsonEncode(body));
  return http.StreamedResponse(
    Stream.value(bytes),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

Future<AppController> _signedInController(_PrintGateway gateway) async {
  final controller = await AppController.load(
    gateway: gateway,
    restoreSession: false,
  );
  expect(
    await controller.signIn(
      username: 'teacher.aziza',
      password: 'valid-password',
    ),
    AuthResult.success,
  );
  return controller;
}

StaffAccount _account(Set<String> permissions, {bool readOnly = false}) =>
    StaffAccount(
      id: 17,
      principalKind: 'teacher',
      username: 'teacher.aziza',
      fullName: 'Aziza Karimova',
      phone: '+998900000000',
      email: 'aziza@example.test',
      preferredLanguage: 'en',
      mustChangePassword: false,
      memberships: const [
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
      permissions: permissions,
      readOnly: readOnly,
    );

PrinterDevice _printer({
  String id = '7',
  int branchId = 3,
  bool isOffline = false,
  bool supportsColor = false,
  bool supportsDuplex = false,
}) => PrinterDevice(
  id: id,
  name: 'Orion',
  location: 'Second floor',
  toner: 1,
  paper: 'A4',
  isOffline: isOffline,
  supportsColor: supportsColor,
  supportsDuplex: supportsDuplex,
  branchId: branchId,
);

LibraryResource _resource() => const LibraryResource(
  id: 'file-42',
  title: 'Workbook',
  subtitle: 'A4 PDF',
  author: 'Aziza Karimova',
  kind: LibraryKind.book,
  color: Colors.indigo,
  icon: Icons.menu_book_outlined,
  downloadable: true,
  remoteFileId: 42,
  contentType: 'application/pdf',
  status: 'clean',
);

class _PrintGateway implements StarforgeGateway {
  _PrintGateway({
    required this.account,
    this.printerData = const [],
    this.jobData = const [],
  });

  StaffAccount account;
  final List<PrinterInfo> printerData;
  final List<PrintJobInfo> jobData;
  int printerReads = 0;
  int jobReads = 0;
  int uploadSubmissions = 0;
  int librarySubmissions = 0;
  Map<String, Object?>? lastUpload;
  Map<String, Object?>? lastLibrary;

  @override
  Future<LoginSession> login(String username, String password) async =>
      const LoginSession(
        access: 'test-access',
        principalKind: 'teacher',
        mustChangePassword: false,
      );

  @override
  Future<StaffAccount> currentAccount() async => account;

  @override
  Future<List<PrinterInfo>> printers() async {
    printerReads++;
    return printerData;
  }

  @override
  Future<List<PrintJobInfo>> printJobs() async {
    jobReads++;
    return jobData;
  }

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
  }) async {
    uploadSubmissions++;
    lastUpload = {
      'filePath': filePath,
      'filename': filename,
      'contentType': contentType,
      'sizeBytes': sizeBytes,
      'branchId': branchId,
      'printerId': printerId,
      'copies': copies,
      'color': color,
      'duplex': duplex,
      'scheduledFor': scheduledFor,
    };
    return PrintJobInfo(
      id: 1,
      printerId: printerId,
      status: 'queued',
      source: 'upload',
      pages: 1,
      copies: copies,
      color: color,
      duplex: duplex,
      createdAt: DateTime.utc(2026, 8, 12),
      finishedAt: null,
      scheduledFor: scheduledFor,
    );
  }

  @override
  Future<PrintJobInfo> submitLibraryPrintJob({
    required int fileId,
    required int printerId,
    required int copies,
    required bool color,
    required bool duplex,
    DateTime? scheduledFor,
  }) async {
    librarySubmissions++;
    lastLibrary = {
      'fileId': fileId,
      'printerId': printerId,
      'copies': copies,
      'color': color,
      'duplex': duplex,
      'scheduledFor': scheduledFor,
    };
    return PrintJobInfo(
      id: 2,
      printerId: printerId,
      status: 'queued',
      source: 'content',
      pages: 1,
      copies: copies,
      color: color,
      duplex: duplex,
      createdAt: DateTime.utc(2026, 8, 12),
      finishedAt: null,
      scheduledFor: scheduledFor,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

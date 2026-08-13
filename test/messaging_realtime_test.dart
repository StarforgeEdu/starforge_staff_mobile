import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:starforge_staff/features/messages/conversation_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'production realtime socket uses secure subprotocol auth and JSON',
    () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(server.close);
      final requestCompleter = Completer<HttpRequest>();
      final clientFrameCompleter = Completer<Object?>();
      final serverTask = server.first.then((request) async {
        requestCompleter.complete(request);
        final socket = await WebSocketTransformer.upgrade(
          request,
          protocolSelector: (protocols) =>
              protocols.contains('starforge.v1') ? 'starforge.v1' : null,
        );
        socket.add(
          jsonEncode({
            'type': 'thread.ready',
            'payload': {
              'protocol': 'starforge.messaging.thread.v1',
              'thread_id': 42,
              'high_watermark': 7,
              'recovery_floor': 1,
            },
          }),
        );
        clientFrameCompleter.complete(await socket.first);
        await socket.close();
      });
      final gateway = RemoteStarforgeGateway(
        sessionStore: MemorySessionStore(access: 'A' * 54),
        baseUrl: 'http://127.0.0.1:${server.port}',
      );

      final connection = await gateway.connectMessageRealtime(42);
      final ready = await connection.events.first;
      await connection.send(const {'type': 'pong'});
      final request = await requestCompleter.future;
      final clientFrame = await clientFrameCompleter.future;

      expect(request.uri.path, '/ws/messaging/threads/42/');
      final offered = request.headers.value('sec-websocket-protocol') ?? '';
      expect(offered, contains('bearer.${'A' * 54}'));
      expect(offered, contains('starforge.v1'));
      expect(ready.type, 'thread.ready');
      expect(ready.payload['high_watermark'], 7);
      expect(jsonDecode(clientFrame as String), {'type': 'pong'});
      await serverTask;
    },
  );

  test('durable event recovery validates and maps ordered pointers', () async {
    final client = MockClient((request) async {
      expect(request.url.path, '/api/v1/messaging/threads/42/events/');
      expect(request.url.queryParameters, {'after': '4', 'limit': '100'});
      return http.Response(
        jsonEncode({
          'success': true,
          'data': {
            'thread_id': 42,
            'events': [
              {
                'thread_id': 42,
                'sequence': 5,
                'kind': 'message.created',
                'message_id': 91,
                'actor_principal_kind': 'student',
                'actor_principal_id': 11,
                'created_at': '2026-08-12T12:00:00Z',
              },
              {
                'thread_id': 42,
                'sequence': 6,
                'kind': 'read.updated',
                'message_id': 91,
                'actor_principal_kind': 'teacher',
                'actor_principal_id': 7,
                'created_at': '2026-08-12T12:01:00Z',
              },
            ],
            'requested_after': 4,
            'next_cursor': 6,
            'high_watermark': 8,
            'recovery_floor': 1,
            'has_more': true,
            'reset_required': false,
            'generated_at': '2026-08-12T12:01:00Z',
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

    final page = await gateway.recoverMessageEvents(42, after: 4);

    expect(page.events.map((event) => event.sequence), [5, 6]);
    expect(page.events.first.kind, 'message.created');
    expect(page.nextCursor, 6);
    expect(page.highWatermark, 8);
    expect(page.hasMore, isTrue);
    expect(page.resetRequired, isFalse);
  });

  testWidgets('live pointer refreshes once, answers ping, and reconnects', (
    tester,
  ) async {
    final gateway = _RealtimeGateway();
    final controller = await _signedInController(gateway);
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();
    expect(gateway.connections, hasLength(1));

    gateway.emit(
      const MessageRealtimeFrame(
        type: 'thread.ready',
        payload: {
          'protocol': 'starforge.messaging.thread.v1',
          'thread_id': 100,
          'high_watermark': 1,
          'recovery_floor': 1,
        },
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.text('Message 52'), findsOneWidget);
    expect(gateway.recoveryAfters, [0]);
    expect(gateway.incrementalCalls, 1);
    expect(controller.loadConversationEventCursor(_contact), 1);
    final restarted = await _signedInController(_RealtimeGateway());
    expect(restarted.loadConversationEventCursor(_contact), 1);

    gateway.emit(
      const MessageRealtimeFrame(
        type: 'thread.event',
        payload: {'thread_id': 100, 'sequence': 1},
      ),
    );
    gateway.emit(const MessageRealtimeFrame(type: 'ping', payload: {}));
    await tester.pump();
    expect(gateway.recoveryAfters, [0]);
    expect(gateway.sentCommands.single, {'type': 'pong'});

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pumpAndSettle();
    expect(gateway.closedConnections, 1);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(gateway.connections, hasLength(2));

    await tester.pumpWidget(const SizedBox.shrink());
  });

  test(
    'realtime authentication close clears the full signed-in session',
    () async {
      final gateway = _RealtimeGateway();
      final controller = await _signedInController(gateway);

      await controller.handleMessagingRealtimeClosure(4408);
      expect(controller.isSignedIn, isTrue);
      await controller.handleMessagingRealtimeClosure(4401);

      expect(controller.isSignedIn, isFalse);
      expect(controller.account, isNull);
      expect(gateway.sessionClears, 1);
    },
  );

  testWidgets('expired event floor resets from a fresh message snapshot', (
    tester,
  ) async {
    final gateway = _RealtimeGateway(resetRequired: true);
    final controller = await _signedInController(gateway);
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();
    expect(find.text('Message 51'), findsOneWidget);

    gateway.emit(
      const MessageRealtimeFrame(
        type: 'thread.ready',
        payload: {
          'protocol': 'starforge.messaging.thread.v1',
          'thread_id': 100,
          'high_watermark': 9,
          'recovery_floor': 8,
        },
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Message 51'), findsNothing);
    expect(find.text('Message 99'), findsOneWidget);
    expect(gateway.recoveryAfters, [0]);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Future<AppController> _signedInController(_RealtimeGateway gateway) async {
  final controller = await AppController.load(
    gateway: gateway,
    restoreSession: false,
  );
  expect(
    await controller.signIn(username: 'teacher', password: 'password'),
    AuthResult.success,
  );
  return controller;
}

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
    home: const ConversationPage(contact: _contact),
  ),
);

const _contact = ChatContact(
  id: 'thread-100',
  name: 'Alice',
  role: 'Student',
  preview: '',
  time: '',
  remoteUserId: 30,
  principalKind: 'student',
  threadId: 100,
  participantUserIds: [30],
);

class _RealtimeGateway
    implements
        StarforgeGateway,
        PaginatedMessageHistoryGateway,
        RealtimeMessageGateway {
  _RealtimeGateway({this.resetRequired = false});

  final bool resetRequired;
  final List<StreamController<MessageRealtimeFrame>> connections = [];
  final List<Map<String, Object?>> sentCommands = [];
  final List<int> recoveryAfters = [];
  int closedConnections = 0;
  int incrementalCalls = 0;
  int snapshotCalls = 0;
  int sessionClears = 0;

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
    permissions: {'messaging:read', 'messaging:write'},
    readOnly: false,
  );

  void emit(MessageRealtimeFrame frame) => connections.last.add(frame);

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
  Future<MessageHistoryPageInfo> recentMessagesForThread(int threadId) async {
    snapshotCalls++;
    final id = resetRequired && snapshotCalls > 1 ? 99 : 51;
    return MessageHistoryPageInfo(
      messages: [_message(id)],
      nextOlderPage: null,
      total: 1,
    );
  }

  @override
  Future<MessageHistoryPageInfo> olderMessagesForThread(
    int threadId, {
    required int page,
  }) async =>
      const MessageHistoryPageInfo(messages: [], nextOlderPage: null, total: 0);

  @override
  Future<List<MessageInfo>> messagesForThread(
    int threadId, {
    int? afterId,
  }) async {
    incrementalCalls++;
    return [_message(52)];
  }

  @override
  Future<MessageRealtimeConnection> connectMessageRealtime(int threadId) async {
    final stream = StreamController<MessageRealtimeFrame>();
    connections.add(stream);
    var closed = false;
    return MessageRealtimeConnection(
      threadId: threadId,
      events: stream.stream,
      send: (command) async => sentCommands.add(command),
      close: () async {
        if (closed) return;
        closed = true;
        closedConnections++;
        await stream.close();
      },
      closeCode: () => null,
    );
  }

  @override
  Future<MessageEventPageInfo> recoverMessageEvents(
    int threadId, {
    required int after,
    int limit = 100,
  }) async {
    recoveryAfters.add(after);
    if (resetRequired) {
      return const MessageEventPageInfo(
        events: [],
        nextCursor: 0,
        highWatermark: 9,
        recoveryFloor: 8,
        hasMore: false,
        resetRequired: true,
      );
    }
    return const MessageEventPageInfo(
      events: [
        MessageEventPointerInfo(
          sequence: 1,
          kind: 'message.created',
          messageId: 52,
        ),
      ],
      nextCursor: 1,
      highWatermark: 1,
      recoveryFloor: 1,
      hasMore: false,
      resetRequired: false,
    );
  }

  @override
  Future<void> markMessageThreadRead(
    int threadId, {
    int? throughMessageId,
  }) async {}

  @override
  Future<void> clearSession() async => sessionClears++;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MessageInfo _message(int id) => MessageInfo(
  id: id,
  threadId: 100,
  senderUserId: 30,
  senderPrincipalKind: 'student',
  senderPrincipalId: 30,
  body: 'Message $id',
  attachments: const [],
  createdAt: DateTime.utc(2026, 8, 12, 12).add(Duration(minutes: id)),
);

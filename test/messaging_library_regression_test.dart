import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction;

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
import 'package:starforge_staff/features/library/library_upload_filename.dart';
import 'package:starforge_staff/features/messages/conversation_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'recent message history is bounded to the final backend pages',
    () async {
      final requests = <String>[];
      final client = MockClient((request) async {
        expect(request.url.path, '/api/v1/messaging/threads/100/messages/');
        final page = int.parse(request.url.queryParameters['page']!);
        final size = int.parse(request.url.queryParameters['page_size']!);
        requests.add('$page/$size');
        final ids = switch ((page, size)) {
          (1, 1) => [1],
          (3, 50) => [101],
          (2, 50) => List.generate(50, (index) => index + 51),
          (1, 50) => List.generate(50, (index) => index + 1),
          _ => <int>[],
        };
        final pages = (101 + size - 1) ~/ size;
        return http.Response(
          jsonEncode({
            'success': true,
            'data': ids.map(_messageJson).toList(growable: false),
            'pagination': {
              'total': 101,
              'page': page,
              'page_size': size,
              'pages': pages,
              'has_next': page < pages,
              'has_prev': page > 1,
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

      final recent = await gateway.recentMessagesForThread(100);
      expect(recent.messages.map((message) => message.id), [
        ...List.generate(50, (index) => index + 51),
        101,
      ]);
      expect(recent.nextOlderPage, 1);
      expect(requests, ['1/1', '3/50', '2/50']);

      final older = await gateway.olderMessagesForThread(100, page: 1);
      expect(older.messages.first.id, 1);
      expect(older.messages.last.id, 50);
      expect(older.nextOlderPage, isNull);
      expect(requests, ['1/1', '3/50', '2/50', '1/50']);
    },
  );

  test(
    'one-to-one messaging excludes group threads and creates on send',
    () async {
      final gateway = _MessagingGateway();
      final controller = await AppController.load(
        gateway: gateway,
        restoreSession: false,
      );
      expect(
        await controller.signIn(username: 'teacher', password: 'password'),
        AuthResult.success,
      );

      final workspace = await controller.loadMessagingWorkspace();
      final alice = workspace.contacts.firstWhere(
        (contact) => contact.remoteUserId == 20,
      );
      final prepared = await controller.prepareConversation(alice);
      final bob = workspace.contacts.firstWhere(
        (contact) => contact.remoteUserId == 30,
      );
      final existingDirect = await controller.prepareConversation(bob);

      expect(prepared.threadId, isNull);
      expect(existingDirect.threadId, 101);
      expect(gateway.createCalls, 0);

      final first = await controller.sendTextMessage(prepared, 'Hello');
      final second = await controller.sendTextMessage(prepared, 'Again');

      expect(first.isMine, isTrue);
      expect(second.isMine, isTrue);
      expect(gateway.createCalls, 1);
      expect(gateway.sentThreadIds, [200, 200]);
    },
  );

  test('group messages retain the sender display name', () async {
    final gateway = _MessagingGateway();
    final controller = await AppController.load(
      gateway: gateway,
      restoreSession: false,
    );
    await controller.signIn(username: 'teacher', password: 'password');
    final workspace = await controller.loadMessagingWorkspace();

    final group = workspace.threads.firstWhere((thread) => thread.isGroup);
    final messages = await controller.loadConversation(group);

    expect(group.isGroup, isTrue);
    expect(messages.single.senderName, 'Bob');
    expect(messages.single.sentAt, isNotNull);
  });

  test('message archive choices survive a controller restart', () async {
    final first = await AppController.load(
      gateway: _MessagingGateway(),
      restoreSession: false,
    );
    await first.signIn(username: 'teacher', password: 'password');
    await first.setMessageThreadArchived(99, true);

    final restored = await AppController.load(
      gateway: _MessagingGateway(),
      restoreSession: false,
    );
    await restored.signIn(username: 'teacher', password: 'password');

    expect(restored.isMessageThreadArchived(99), isTrue);
  });

  test('library upload names are normalized for the content contract', () {
    expect(
      normalizeLibraryUploadFilename('  O‘zbek tili / dars № 1.PDF'),
      'dars_1.pdf',
    );
    expect(
      normalizeLibraryUploadFilename('Русский язык.pdf'),
      'starforge_file.pdf',
    );
    expect(
      normalizeLibraryUploadFilename('.hidden lesson.mp4'),
      'hidden_lesson.mp4',
    );
  });

  test(
    'library upload offers only internally renderable media including M4A',
    () {
      expect(
        libraryUploadExtensions,
        containsAll(<String>['pdf', 'mp3', 'm4a', 'mp4']),
      );
      expect(libraryUploadExtensions, isNot(contains('docx')));
      expect(libraryUploadExtensions, isNot(contains('pptx')));
      expect(libraryUploadContentType('voice lesson.M4A'), 'audio/mp4');
      expect(libraryUploadContentType('lesson.pdf'), 'application/pdf');
      expect(libraryUploadContentType('unsafe.exe'), isNull);
    },
  );

  test('content parser exposes review and rejection state', () {
    final file = ContentFileInfo.fromJson({
      'id': 8,
      'title': 'Grammar guide',
      'content_type': 'application/pdf',
      'size_bytes': 1200,
      'status': 'rejected',
      'folder_name': 'Teachers',
      'is_downloadable': false,
      'is_approved_teacher': true,
      'is_approved_manager': false,
      'reject_reason': 'Replace the cover image.',
    });

    expect(file.teacherApproved, isTrue);
    expect(file.managerApproved, isFalse);
    expect(file.downloadable, isFalse);
    expect(file.rejectReason, 'Replace the cover image.');
  });

  testWidgets('older messages load accessibly without duplicate bubbles', (
    tester,
  ) async {
    final gateway = _PagingMessagingGateway();
    final controller = await _signedInMessagingController(gateway);
    await tester.pumpWidget(_conversationHarness(controller));
    await tester.pumpAndSettle();

    final history = find.byKey(const ValueKey('loadOlderMessages'));
    expect(history, findsOneWidget);
    expect(
      tester
          .getSemantics(history)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );

    await tester.tap(history);
    await tester.pumpAndSettle();

    expect(gateway.olderCalls, 1);
    expect(find.text('Message 1'), findsOneWidget);
    expect(find.text('Message 51'), findsOneWidget);
    expect(find.byKey(const ValueKey('loadOlderMessages')), findsNothing);
  });

  testWidgets('conversation polling pauses in background and resumes safely', (
    tester,
  ) async {
    final gateway = _PagingMessagingGateway();
    final controller = await _signedInMessagingController(gateway);
    await tester.pumpWidget(_conversationHarness(controller));
    await tester.pumpAndSettle();

    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(gateway.incrementalCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    await tester.pump(const Duration(seconds: 12));
    expect(gateway.incrementalCalls, 1);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();
    expect(gateway.incrementalCalls, 2);

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('optimistic send stays loader-free and reconciles a poll race', (
    tester,
  ) async {
    final gateway = _PagingMessagingGateway(sendRace: true);
    final controller = await _signedInMessagingController(gateway);
    await tester.pumpWidget(_conversationHarness(controller));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'Race message');
    await tester.pump();
    await tester.tap(find.byIcon(Icons.arrow_upward_rounded));
    await tester.pump();
    expect(find.text('Race message'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    gateway.emitPendingSendFromPoll = true;
    await tester.pump(const Duration(seconds: 6));
    await tester.pump();
    expect(find.text('Race message'), findsNWidgets(2));

    gateway.completePendingSend();
    await tester.pump();
    await tester.pump();
    expect(find.text('Race message'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
  });
}

Map<String, Object?> _messageJson(int id) => {
  'id': id,
  'thread': 100,
  'sender': 30,
  'sender_principal_kind': 'student',
  'sender_principal_id': 30,
  'body': 'Message $id',
  'attachments': <String>[],
  'created_at': DateTime.utc(
    2026,
    8,
    12,
  ).add(Duration(minutes: id)).toIso8601String(),
};

Future<AppController> _signedInMessagingController(
  _PagingMessagingGateway gateway,
) async {
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

Widget _conversationHarness(AppController controller) => AppControllerScope(
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
    home: const ConversationPage(
      contact: ChatContact(
        id: 'thread-100',
        name: 'Alice',
        role: 'Student',
        preview: '',
        time: '',
        remoteUserId: 30,
        principalKind: 'student',
        threadId: 100,
        participantUserIds: [30],
      ),
    ),
  ),
);

class _PagingMessagingGateway
    implements StarforgeGateway, PaginatedMessageHistoryGateway {
  _PagingMessagingGateway({this.sendRace = false});

  final bool sendRace;
  int olderCalls = 0;
  int incrementalCalls = 0;
  bool emitPendingSendFromPoll = false;
  Completer<MessageInfo>? _pendingSend;

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
  Future<MessageHistoryPageInfo> recentMessagesForThread(int threadId) async =>
      MessageHistoryPageInfo(
        messages: [_messageInfo(51), _messageInfo(52)],
        nextOlderPage: 1,
        total: 3,
      );

  @override
  Future<MessageHistoryPageInfo> olderMessagesForThread(
    int threadId, {
    required int page,
  }) async {
    olderCalls++;
    return MessageHistoryPageInfo(
      messages: [_messageInfo(1), _messageInfo(51)],
      nextOlderPage: null,
      total: 3,
    );
  }

  @override
  Future<List<MessageInfo>> messagesForThread(
    int threadId, {
    int? afterId,
  }) async {
    if (afterId != null) incrementalCalls++;
    return emitPendingSendFromPoll ? [_sentMessageInfo()] : const [];
  }

  @override
  Future<MessageInfo> sendMessage({
    required int threadId,
    String body = '',
    List<String> attachments = const [],
  }) {
    if (!sendRace) return Future.value(_sentMessageInfo(body: body));
    _pendingSend ??= Completer<MessageInfo>();
    return _pendingSend!.future;
  }

  void completePendingSend() {
    _pendingSend?.complete(_sentMessageInfo());
  }

  @override
  Future<void> markMessageThreadRead(
    int threadId, {
    int? throughMessageId,
  }) async {}

  @override
  Future<void> clearSession() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MessageInfo _messageInfo(int id) => MessageInfo(
  id: id,
  threadId: 100,
  senderUserId: 30,
  senderPrincipalKind: 'student',
  senderPrincipalId: 30,
  body: 'Message $id',
  attachments: const [],
  createdAt: DateTime.utc(2026, 8, 12).add(Duration(minutes: id)),
);

MessageInfo _sentMessageInfo({String body = 'Race message'}) => MessageInfo(
  id: 300,
  threadId: 100,
  senderUserId: 10,
  senderPrincipalKind: 'teacher',
  senderPrincipalId: 7,
  body: body,
  attachments: const [],
  createdAt: DateTime.utc(2026, 8, 12, 12),
);

class _MessagingGateway implements StarforgeGateway {
  int createCalls = 0;
  final List<int> sentThreadIds = [];

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

  static const _contacts = [
    MessageContactInfo(
      userId: 20,
      profileId: 20,
      principalKind: 'student',
      category: 'student',
      displayName: 'Alice',
      username: 'alice',
      roleLabel: 'Student',
      recentlyActive: false,
    ),
    MessageContactInfo(
      userId: 30,
      profileId: 30,
      principalKind: 'student',
      category: 'student',
      displayName: 'Bob',
      username: 'bob',
      roleLabel: 'Student',
      recentlyActive: true,
    ),
  ];

  static const _group = MessageThreadInfo(
    id: 100,
    subject: 'Study group',
    participants: [
      MessageParticipantInfo(
        userId: 10,
        principalKind: 'teacher',
        principalId: 7,
      ),
      MessageParticipantInfo(
        userId: 20,
        principalKind: 'student',
        principalId: 20,
      ),
      MessageParticipantInfo(
        userId: 30,
        principalKind: 'student',
        principalId: 30,
      ),
    ],
    unreadCount: 1,
    lastMessageAt: null,
    notificationsMuted: false,
  );

  static const _direct = MessageThreadInfo(
    id: 101,
    subject: '',
    participants: [
      MessageParticipantInfo(
        userId: 10,
        principalKind: 'teacher',
        principalId: 7,
      ),
      MessageParticipantInfo(
        userId: 30,
        principalKind: 'student',
        principalId: 30,
      ),
    ],
    unreadCount: 0,
    lastMessageAt: null,
    notificationsMuted: false,
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
  Future<List<MessageContactInfo>> messageContacts() async => _contacts;

  @override
  Future<List<MessageThreadInfo>> messageThreads() async => const [
    _group,
    _direct,
  ];

  @override
  Future<MessageThreadInfo> createMessageThread({
    required int participantUserId,
    String subject = '',
  }) async {
    createCalls++;
    return MessageThreadInfo(
      id: 200,
      subject: subject,
      participants: [
        const MessageParticipantInfo(
          userId: 10,
          principalKind: 'teacher',
          principalId: 7,
        ),
        MessageParticipantInfo(
          userId: participantUserId,
          principalKind: 'student',
          principalId: participantUserId,
        ),
      ],
      unreadCount: 0,
      lastMessageAt: null,
      notificationsMuted: false,
    );
  }

  @override
  Future<MessageInfo> sendMessage({
    required int threadId,
    String body = '',
    List<String> attachments = const [],
  }) async {
    sentThreadIds.add(threadId);
    return MessageInfo(
      id: 300 + sentThreadIds.length,
      threadId: threadId,
      senderUserId: 10,
      senderPrincipalKind: 'teacher',
      senderPrincipalId: 7,
      body: body,
      attachments: attachments,
      createdAt: DateTime.utc(2026, 8, 12, 10),
    );
  }

  @override
  Future<List<MessageInfo>> messagesForThread(
    int threadId, {
    int? afterId,
  }) async => [
    MessageInfo(
      id: 44,
      threadId: threadId,
      senderUserId: 30,
      senderPrincipalKind: 'student',
      senderPrincipalId: 30,
      body: 'Hello group',
      attachments: const [],
      createdAt: DateTime.utc(2026, 8, 12, 9),
    ),
  ];

  @override
  Future<void> markMessageThreadRead(
    int threadId, {
    int? throughMessageId,
  }) async {}

  @override
  Future<void> clearSession() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

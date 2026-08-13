import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../data/models.dart';
import '../data/remote_models.dart';
import '../data/workflow_models.dart';

const starforgeBaseUrl = 'https://starforge.78.111.91.113.nip.io';

class StarforgeException implements Exception {
  const StarforgeException({
    required this.code,
    required this.message,
    this.statusCode,
    this.details,
  });

  final String code;
  final String message;
  final int? statusCode;
  final Object? details;

  bool get isAuthenticationFailure =>
      statusCode == 401 || code == 'authentication_failed';
  bool get isConnectionFailure =>
      code == 'connection_unavailable' || code == 'request_timeout';

  @override
  String toString() => 'StarforgeException($code, $statusCode)';
}

abstract interface class SessionStore {
  Future<String?> readAccess();
  Future<void> writeAccess(String value);
  Future<void> clearAccess();
  Future<String> deviceId();
}

class SecureSessionStore implements SessionStore {
  SecureSessionStore({FlutterSecureStorage? storage})
    : _storage =
          storage ??
          const FlutterSecureStorage(
            iOptions: IOSOptions(
              accessibility: KeychainAccessibility.unlocked_this_device,
            ),
          );

  static const _accessKey = 'starforge_staff_access';
  static const _deviceKey = 'starforge_staff_device';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> readAccess() => _storage.read(key: _accessKey);

  @override
  Future<void> writeAccess(String value) =>
      _storage.write(key: _accessKey, value: value);

  @override
  Future<void> clearAccess() => _storage.delete(key: _accessKey);

  @override
  Future<String> deviceId() async {
    final existing = await _storage.read(key: _deviceKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final random = Random.secure();
    final bytes = List<int>.generate(24, (_) => random.nextInt(256));
    final value = base64Url.encode(bytes).replaceAll('=', '');
    await _storage.write(key: _deviceKey, value: value);
    return value;
  }
}

class MemorySessionStore implements SessionStore {
  MemorySessionStore({this.access});
  String? access;
  final String _device = 'starforge-test-device';

  @override
  Future<void> clearAccess() async => access = null;

  @override
  Future<String> deviceId() async => _device;

  @override
  Future<String?> readAccess() async => access;

  @override
  Future<void> writeAccess(String value) async => access = value;
}

/// Optional notification emitted after an authenticated request proves that
/// the saved session is no longer valid. Login failures never emit this event.
abstract interface class SessionExpirySource {
  void addSessionExpiredListener(VoidCallback listener);
  void removeSessionExpiredListener(VoidCallback listener);
}

typedef VoidCallback = void Function();
typedef MessageSocketConnector =
    WebSocketChannel Function(Uri uri, {required Iterable<String> protocols});

abstract interface class StarforgeGateway {
  Future<bool> hasSavedSession();
  Future<LoginSession> login(String username, String password);
  Future<StaffAccount> currentAccount();
  Future<void> logout();
  Future<void> clearSession();
  Future<StaffAccount> updateProfile(Map<String, Object?> changes);
  Future<LoginSession> changePassword(String oldPassword, String newPassword);
  Future<List<LearningGroup>> groups();
  Future<List<Student>> studentsForGroup(int groupId);
  Future<AttendanceMonth> attendanceForMonth(int groupId, DateTime month);
  Future<List<ExamInfo>> examsForGroup(int groupId);
  Future<List<ExamResultInfo>> examResults(int examId);
  Future<List<AttendanceRecordInfo>> markAttendance(
    int lessonId,
    List<Map<String, Object?>> records,
  );
  Future<TeacherDashboardData> teacherDashboard();
  Future<List<FeatureAvailabilityInfo>> featureAvailability();
  Future<List<StaffTask>> tasks({bool mineOnly = false});
  Future<StaffTask> createTask({
    required String title,
    required String description,
    required bool highPriority,
    required String principalKind,
    required int principalId,
    DateTime? dueAt,
  });
  Future<StaffTask> transitionTask(int taskId, String status);
  Future<List<MessageContactInfo>> messageContacts();
  Future<List<MessageThreadInfo>> messageThreads();
  Future<List<MessageInfo>> messagesForThread(int threadId, {int? afterId});
  Future<MessageThreadInfo> createMessageThread({
    required int participantUserId,
    String subject = '',
  });
  Future<String> uploadMessageAttachment({
    required String filePath,
    required String filename,
    required String contentType,
  });
  Future<MessageInfo> sendMessage({
    required int threadId,
    String body = '',
    List<String> attachments = const [],
  });
  Future<void> markMessageThreadRead(int threadId, {int? throughMessageId});
  Future<String> messageAttachmentUrl({
    required int threadId,
    required String key,
  });
  Future<List<ContentFolderInfo>> contentFolders();
  Future<List<ContentFileInfo>> contentFiles();
  Future<List<LibraryMaterialInfo>> libraryMaterials();
  Future<String> contentFileUrl(int fileId);
  Future<void> trackContentFileView(int fileId);
  Future<ContentFileInfo> approveContentFileAsTeacher(int fileId);
  Future<int> uploadContentFile({
    required String filePath,
    required String filename,
    required String contentType,
    required String title,
    required int folderId,
    required String audience,
    required bool downloadable,
  });
  Future<List<PrinterInfo>> printers();
  Future<List<PrintJobInfo>> printJobs();
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
  });
  Future<PrintJobInfo> submitLibraryPrintJob({
    required int fileId,
    required int printerId,
    required int copies,
    required bool color,
    required bool duplex,
    DateTime? scheduledFor,
  });
  Future<List<PayrollPayslipInfo>> ownPayslips();
  Future<List<ComplianceRuleInfo>> ownRules();
  Future<void> acknowledgeRule(int ruleId);
  Future<List<NotificationInfo>> notifications();
  Future<int> unreadNotificationCount();
  Future<void> markNotificationRead(int notificationId);
  Future<void> markAllNotificationsRead();
  Future<List<NotificationPreferenceInfo>> notificationPreferences();
  Future<List<NotificationPreferenceInfo>> updateNotificationPreferences(
    List<NotificationPreferenceInfo> preferences,
  );
  Future<List<MeetingInfo>> upcomingMeetings();
  Future<List<CrmLeadInfo>> crmLeads();
  Future<List<FinanceInvoiceInfo>> financeInvoices();
  Future<List<CashierShiftInfo>> ownCashierShifts();
  Future<void> submitStudentRequest({
    required String action,
    required LearningGroup group,
    required Student student,
    required String description,
    int? branchId,
  });
}

/// Optional capability for gateways that expose the backend's stable,
/// oldest-first message pagination. Test/offline gateways can continue to
/// implement [StarforgeGateway.messagesForThread] without simulating metadata.
abstract interface class PaginatedMessageHistoryGateway {
  Future<MessageHistoryPageInfo> recentMessagesForThread(int threadId);
  Future<MessageHistoryPageInfo> olderMessagesForThread(
    int threadId, {
    required int page,
  });
}

/// Optional capability for the recoverable, pointer-only messaging stream.
/// Gateways without it keep the bounded REST fallback used by tests/offline
/// harnesses; the production gateway provides WebSocket hints plus durable
/// HTTP cursor recovery.
abstract interface class RealtimeMessageGateway {
  Future<MessageRealtimeConnection> connectMessageRealtime(int threadId);
  Future<MessageEventPageInfo> recoverMessageEvents(
    int threadId, {
    required int after,
    int limit = 100,
  });
}

class MessageRealtimeConnection {
  const MessageRealtimeConnection({
    required this.threadId,
    required this.events,
    required this.send,
    required this.close,
    required this.closeCode,
  });

  final int threadId;
  final Stream<MessageRealtimeFrame> events;
  final Future<void> Function(Map<String, Object?> command) send;
  final Future<void> Function() close;
  final int? Function() closeCode;
}

class MessageRealtimeFrame {
  const MessageRealtimeFrame({required this.type, required this.payload});

  final String type;
  final Map<String, dynamic> payload;
}

class MessageEventPageInfo {
  const MessageEventPageInfo({
    required this.events,
    required this.nextCursor,
    required this.highWatermark,
    required this.recoveryFloor,
    required this.hasMore,
    required this.resetRequired,
  });

  final List<MessageEventPointerInfo> events;
  final int nextCursor;
  final int highWatermark;
  final int recoveryFloor;
  final bool hasMore;
  final bool resetRequired;
}

class MessageEventPointerInfo {
  const MessageEventPointerInfo({
    required this.sequence,
    required this.kind,
    required this.messageId,
  });

  final int sequence;
  final String kind;
  final int messageId;
}

/// Optional, permission-pruned student profile read model. Keeping this as an
/// optional capability avoids forcing test and offline gateways to manufacture
/// sensitive student data.
abstract interface class StudentLeadershipGateway {
  Future<StudentLeadershipInfo> studentLeadershipProfile(int studentId);
}

/// Optional because older deployments may not yet expose the derived cycle
/// read model. The UI remains truthful and simply omits unknown progress.
abstract interface class CohortCycleProgressGateway {
  Future<CohortCycleProgressInfo> cohortCycleProgress(int cohortId);
}

/// Optional write capability introduced with the primary-teacher progress
/// contract. Older deployments remain readable while the UI hides mutation.
abstract interface class CohortTeachingProgressGateway {
  Future<CohortTeachingProgressInfo> updateCohortTeachingProgress({
    required int cohortId,
    required String level,
    required int studyMonth,
    required int lessonCycleLength,
  });
}

/// Optional teacher-facing workplace workflows. Keeping this separate from the
/// core gateway preserves compatibility with offline and test gateways while
/// the production app exposes the complete staff workspace.
abstract interface class StaffWorkflowGateway {
  Future<List<StaffRequestInfo>> staffRequests();
  Future<StaffRequestInfo> createStaffRequest({
    required String kind,
    required String title,
    required String description,
    int? branchId,
    double? amount,
  });
  Future<StaffRequestInfo> cancelStaffRequest(int requestId);
  Future<List<StaffFormInfo>> staffForms();
  Future<StaffFormInfo> staffForm(int formId);
  Future<void> submitStaffForm(int formId, Map<int, Object?> answers);
  Future<List<StaffAchievementInfo>> staffAchievements();
  Future<StaffAchievementInfo> createGroupAchievement({
    required int cohortId,
    required String name,
    required String description,
    required String emoji,
  });
  Future<void> grantStaffAchievement({
    required int achievementId,
    required int studentId,
    required String note,
  });
  Future<List<StaffReportInfo>> staffReports();
  Future<List<StaffReportRunInfo>> staffReportRuns();
  Future<StaffReportRunInfo> createStaffReportRun({
    required String reportKey,
    required String format,
    required Map<String, Object?> params,
    List<int> recipientIds = const [],
  });
}

/// Optional organization capability. Most teaching accounts do not receive
/// `org:write`, so both the controller and UI prune these controls unless the
/// signed-in role is explicitly authorized by the service.
abstract interface class BranchTransferGateway {
  Future<List<BranchChoiceInfo>> transferBranches();
  Future<void> transferBranchSubject({
    required String subjectKind,
    required int subjectId,
    int? fromBranchId,
    required int toBranchId,
    required String reason,
    required bool confirmImpacts,
  });
}

class MessageHistoryPageInfo {
  const MessageHistoryPageInfo({
    required this.messages,
    required this.nextOlderPage,
    required this.total,
  });

  final List<MessageInfo> messages;
  final int? nextOlderPage;
  final int total;
}

class RemoteStarforgeGateway
    implements
        StarforgeGateway,
        PaginatedMessageHistoryGateway,
        RealtimeMessageGateway,
        CohortCycleProgressGateway,
        CohortTeachingProgressGateway,
        StudentLeadershipGateway,
        StaffWorkflowGateway,
        BranchTransferGateway,
        SessionExpirySource {
  RemoteStarforgeGateway({
    http.Client? client,
    SessionStore? sessionStore,
    MessageSocketConnector? messageSocketConnector,
    this.baseUrl = starforgeBaseUrl,
    this.language = 'uz',
  }) : _client = client ?? http.Client(),
       _sessionStore = sessionStore ?? SecureSessionStore(),
       _messageSocketConnector =
           messageSocketConnector ??
           ((uri, {required protocols}) => IOWebSocketChannel.connect(
             uri,
             protocols: protocols,
             connectTimeout: const Duration(seconds: 12),
           ));

  final http.Client _client;
  final SessionStore _sessionStore;
  final MessageSocketConnector _messageSocketConnector;
  final String baseUrl;
  String language;

  String? _access;
  final Set<VoidCallback> _sessionExpiredListeners = {};

  @override
  void addSessionExpiredListener(VoidCallback listener) =>
      _sessionExpiredListeners.add(listener);

  @override
  void removeSessionExpiredListener(VoidCallback listener) =>
      _sessionExpiredListeners.remove(listener);

  void _notifySessionExpired() {
    for (final listener in List<VoidCallback>.of(_sessionExpiredListeners)) {
      listener();
    }
  }

  @override
  Future<bool> hasSavedSession() async {
    _access ??= await _sessionStore.readAccess();
    return _access?.isNotEmpty == true;
  }

  String get _platform {
    if (Platform.isIOS) return 'ios';
    if (Platform.isAndroid) return 'android';
    return 'web';
  }

  @override
  Future<LoginSession> login(String username, String password) async {
    final payload = await _request(
      'POST',
      '/api/v1/auth/role-login/',
      authenticated: false,
      body: {
        'username': username.trim(),
        'password': password,
        'device_id': await _sessionStore.deviceId(),
        'platform': _platform,
      },
    );
    final session = LoginSession.fromJson(_map(payload));
    if (session.access.isEmpty) {
      throw const StarforgeException(
        code: 'authentication_failed',
        message: 'Authentication could not be completed.',
      );
    }
    _access = session.access;
    await _sessionStore.writeAccess(session.access);
    return session;
  }

  @override
  Future<StaffAccount> currentAccount() async {
    final payload = await _request('GET', '/api/v1/users/me/');
    return StaffAccount.fromJson(_map(payload));
  }

  @override
  Future<void> logout() async {
    try {
      await _request('POST', '/api/v1/auth/logout/');
    } finally {
      await clearSession();
    }
  }

  @override
  Future<void> clearSession() async {
    _access = null;
    await _sessionStore.clearAccess();
  }

  @override
  Future<StaffAccount> updateProfile(Map<String, Object?> changes) async {
    final payload = await _request('PATCH', '/api/v1/users/me/', body: changes);
    return StaffAccount.fromJson(_map(payload));
  }

  @override
  Future<LoginSession> changePassword(
    String oldPassword,
    String newPassword,
  ) async {
    final payload = await _request(
      'POST',
      '/api/v1/auth/password/change/',
      body: {'old_password': oldPassword, 'new_password': newPassword},
    );
    final session = LoginSession.fromJson(_map(payload));
    if (session.access.isNotEmpty) {
      _access = session.access;
      await _sessionStore.writeAccess(session.access);
    }
    return session;
  }

  @override
  Future<List<LearningGroup>> groups() async {
    final items = await _getAll(
      '/api/v1/cohorts/',
      query: {'is_archived': 'false'},
    );
    return items.map(groupFromJson).toList(growable: false);
  }

  @override
  Future<List<Student>> studentsForGroup(int groupId) async {
    final items = await _getAll(
      '/api/v1/students/',
      query: {'cohort': '$groupId'},
    );
    return items.map(studentFromJson).toList(growable: false);
  }

  @override
  Future<CohortCycleProgressInfo> cohortCycleProgress(int cohortId) async {
    if (cohortId <= 0) {
      throw const StarforgeException(
        code: 'invalid_cohort',
        message: 'This group is not available.',
      );
    }
    final payload = await _request(
      'GET',
      '/api/v1/cohorts/$cohortId/cycle-progress/',
    );
    final progress = CohortCycleProgressInfo.fromJson(_map(payload));
    if (progress.cohortId != cohortId) {
      throw const StarforgeException(
        code: 'invalid_response',
        message: 'Group progress returned invalid information.',
      );
    }
    return progress;
  }

  @override
  Future<CohortTeachingProgressInfo> updateCohortTeachingProgress({
    required int cohortId,
    required String level,
    required int studyMonth,
    required int lessonCycleLength,
  }) async {
    if (cohortId <= 0 ||
        level.length > 64 ||
        studyMonth < 1 ||
        studyMonth > 600 ||
        !const {8, 12}.contains(lessonCycleLength)) {
      throw const StarforgeException(
        code: 'invalid_teaching_progress',
        message: 'The teaching progress is not valid.',
      );
    }
    final payload = await _request(
      'PATCH',
      '/api/v1/cohorts/$cohortId/teaching-progress/',
      body: {
        'level': level.trim(),
        'study_month': studyMonth,
        'lesson_cycle_length': lessonCycleLength,
      },
    );
    final progress = CohortTeachingProgressInfo.fromJson(_map(payload));
    if (progress.cohortId != cohortId) {
      throw const StarforgeException(
        code: 'invalid_response',
        message: 'Group progress returned invalid information.',
      );
    }
    return progress;
  }

  @override
  Future<StudentLeadershipInfo> studentLeadershipProfile(int studentId) async {
    final payload = await _request(
      'GET',
      '/api/v1/students/$studentId/leadership-profile/',
    );
    return StudentLeadershipInfo.fromJson(_map(payload));
  }

  @override
  Future<AttendanceMonth> attendanceForMonth(
    int groupId,
    DateTime month,
  ) async {
    final start = DateTime(month.year, month.month);
    final end = DateTime(
      month.year,
      month.month + 1,
    ).subtract(const Duration(milliseconds: 1));
    final query = {
      'cohort': '$groupId',
      'date_from': start.toIso8601String(),
      'date_to': end.toIso8601String(),
    };
    final responses = await Future.wait<Object?>([
      _getAll('/api/v1/schedule/lessons/', query: query),
      // A large cohort can legitimately exceed the generic 5,000-row list
      // ceiling in one month. Never silently truncate attendance evidence.
      _getAll('/api/v1/attendance/records/', query: query, maxPages: 500),
      _request(
        'GET',
        '/api/v1/attendance/cohorts/$groupId/dashboard/',
        query: {
          'date_from': start.toIso8601String(),
          'date_to': end.toIso8601String(),
        },
      ),
    ]);
    final dashboard = _map(responses[2]);
    return AttendanceMonth(
      month: start,
      lessons: (responses[0] as List<Map<String, dynamic>>)
          .map(LessonInfo.fromJson)
          .toList(growable: false),
      records: (responses[1] as List<Map<String, dynamic>>)
          .map(AttendanceRecordInfo.fromJson)
          .toList(growable: false),
      rate: jsonDouble(dashboard['rate']),
      students: (dashboard['students'] as List? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                StudentAttendanceSummary.fromJson(item.cast<String, dynamic>()),
          )
          .toList(growable: false),
    );
  }

  @override
  Future<List<ExamInfo>> examsForGroup(int groupId) async {
    final items = await _getAll(
      '/api/v1/academics/exams/',
      query: {'cohort': '$groupId', 'ordering': '-exam_date'},
    );
    return items.map(ExamInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<ExamResultInfo>> examResults(int examId) async {
    final items = await _getAll('/api/v1/academics/exams/$examId/results/');
    return items.map(ExamResultInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<AttendanceRecordInfo>> markAttendance(
    int lessonId,
    List<Map<String, Object?>> records,
  ) async {
    final payload = await _request(
      'POST',
      '/api/v1/attendance/lessons/$lessonId/mark/',
      body: records,
    );
    final map = _map(payload);
    return (map['records'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (item) => AttendanceRecordInfo.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  @override
  Future<TeacherDashboardData> teacherDashboard() async {
    final payload = await _request('GET', '/api/v1/teachers/dashboard/');
    return TeacherDashboardData.fromJson(_map(payload));
  }

  @override
  Future<List<FeatureAvailabilityInfo>> featureAvailability() async {
    final payload = await _request('GET', '/api/v1/org/app-status/');
    final raw = _map(payload)['features'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              FeatureAvailabilityInfo.fromJson(item.cast<String, dynamic>()),
        )
        .where((item) => item.feature.isNotEmpty)
        .toList(growable: false);
  }

  @override
  Future<List<StaffTask>> tasks({bool mineOnly = false}) async {
    final items = await _getAll(
      mineOnly ? '/api/v1/tasks/mine/' : '/api/v1/tasks/',
    );
    return items.map(taskFromJson).toList(growable: false);
  }

  @override
  Future<StaffTask> createTask({
    required String title,
    required String description,
    required bool highPriority,
    required String principalKind,
    required int principalId,
    DateTime? dueAt,
  }) async {
    final payload = await _request(
      'POST',
      '/api/v1/tasks/',
      body: {
        'title': title.trim(),
        'description': description.trim(),
        'priority': highPriority ? 'high' : 'normal',
        'assignee_principal': {'kind': principalKind, 'id': principalId},
        'due_at': ?dueAt?.toIso8601String(),
      },
    );
    return taskFromJson(_map(payload));
  }

  @override
  Future<StaffTask> transitionTask(int taskId, String status) async {
    final payload = await _request(
      'POST',
      '/api/v1/tasks/$taskId/transition/',
      body: {'status': status},
    );
    return taskFromJson(_map(payload));
  }

  @override
  Future<List<MessageContactInfo>> messageContacts() async {
    final items = await _getAll('/api/v1/messaging/contacts/');
    return items.map(MessageContactInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<MessageThreadInfo>> messageThreads() async {
    final items = await _getAll('/api/v1/messaging/threads/');
    return items.map(MessageThreadInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<MessageInfo>> messagesForThread(
    int threadId, {
    int? afterId,
  }) async {
    if (afterId == null || afterId <= 0) {
      return (await recentMessagesForThread(threadId)).messages;
    }
    final items = await _getAll(
      '/api/v1/messaging/threads/$threadId/messages/',
      query: {'after_id': '$afterId'},
    );
    return items.map(MessageInfo.fromJson).toList(growable: false);
  }

  static const _messageHistoryPageSize = 50;

  @override
  Future<MessageHistoryPageInfo> recentMessagesForThread(int threadId) async {
    // Messages are ordered oldest-first. A one-row probe obtains the exact
    // total without walking the thread, after which at most the final two
    // 50-row pages are fetched. Combining a partial final page with its full
    // predecessor avoids opening a 10,001-message thread with one lonely row.
    final probe = await _messageHistoryPage(threadId, page: 1, pageSize: 1);
    if (probe.total == 0) return probe;
    if (probe.total == 1) {
      return MessageHistoryPageInfo(
        messages: probe.messages,
        nextOlderPage: null,
        total: 1,
      );
    }

    final lastPage =
        (probe.total + _messageHistoryPageSize - 1) ~/ _messageHistoryPageSize;
    final latest = await _messageHistoryPage(
      threadId,
      page: lastPage,
      pageSize: _messageHistoryPageSize,
    );
    if (lastPage == 1) return latest;

    if (latest.messages.length < _messageHistoryPageSize) {
      final previous = await _messageHistoryPage(
        threadId,
        page: lastPage - 1,
        pageSize: _messageHistoryPageSize,
      );
      return MessageHistoryPageInfo(
        messages: [...previous.messages, ...latest.messages],
        nextOlderPage: lastPage > 2 ? lastPage - 2 : null,
        total: latest.total,
      );
    }
    return MessageHistoryPageInfo(
      messages: latest.messages,
      nextOlderPage: lastPage - 1,
      total: latest.total,
    );
  }

  @override
  Future<MessageHistoryPageInfo> olderMessagesForThread(
    int threadId, {
    required int page,
  }) {
    if (page < 1) {
      return Future.value(
        const MessageHistoryPageInfo(
          messages: [],
          nextOlderPage: null,
          total: 0,
        ),
      );
    }
    return _messageHistoryPage(
      threadId,
      page: page,
      pageSize: _messageHistoryPageSize,
    ).then(
      (result) => MessageHistoryPageInfo(
        messages: result.messages,
        nextOlderPage: page > 1 ? page - 1 : null,
        total: result.total,
      ),
    );
  }

  Future<MessageHistoryPageInfo> _messageHistoryPage(
    int threadId, {
    required int page,
    required int pageSize,
  }) async {
    final envelope = await _requestEnvelope(
      'GET',
      '/api/v1/messaging/threads/$threadId/messages/',
      query: {'page': '$page', 'page_size': '$pageSize'},
    );
    final data = envelope['data'];
    final messages = data is List
        ? data
              .whereType<Map>()
              .map((item) => MessageInfo.fromJson(item.cast<String, dynamic>()))
              .toList(growable: false)
        : const <MessageInfo>[];
    final pagination = _map(envelope['pagination']);
    return MessageHistoryPageInfo(
      messages: messages,
      nextOlderPage: page > 1 ? page - 1 : null,
      total: jsonInt(pagination['total']) ?? messages.length,
    );
  }

  @override
  Future<MessageRealtimeConnection> connectMessageRealtime(int threadId) async {
    if (threadId <= 0) {
      throw const StarforgeException(
        code: 'invalid_thread',
        message: 'This conversation is not available.',
      );
    }
    _access ??= await _sessionStore.readAccess();
    final access = _access;
    if (access == null || access.isEmpty) {
      throw const StarforgeException(
        code: 'authentication_failed',
        message: 'Please sign in again.',
        statusCode: 401,
      );
    }
    final base = Uri.tryParse(baseUrl);
    if (base == null ||
        !base.hasAuthority ||
        base.userInfo.isNotEmpty ||
        !_isTrustedRemoteUrl(baseUrl)) {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A secure connection could not be established.',
      );
    }
    final socketUri = base.replace(
      scheme: base.scheme == 'https' ? 'wss' : 'ws',
      path: '/ws/messaging/threads/$threadId/',
      query: null,
      fragment: null,
    );
    final channel = _messageSocketConnector(
      socketUri,
      protocols: ['bearer.$access', 'starforge.v1'],
    );
    try {
      await channel.ready;
    } on TimeoutException {
      await channel.sink.close();
      throw const StarforgeException(
        code: 'request_timeout',
        message: 'The conversation took too long to connect.',
      );
    } catch (_) {
      await channel.sink.close();
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'The conversation could not connect.',
      );
    }
    final frames = channel.stream.map<MessageRealtimeFrame>((raw) {
      if (raw is! String || raw.length > 64 * 1024) {
        throw const StarforgeException(
          code: 'invalid_response',
          message: 'A conversation update could not be read.',
        );
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map) {
        throw const StarforgeException(
          code: 'invalid_response',
          message: 'A conversation update could not be read.',
        );
      }
      final frame = decoded.cast<String, dynamic>();
      final type = jsonString(frame['type']);
      final rawPayload = frame['payload'];
      if (type.isEmpty || (rawPayload != null && rawPayload is! Map)) {
        throw const StarforgeException(
          code: 'invalid_response',
          message: 'A conversation update could not be read.',
        );
      }
      return MessageRealtimeFrame(
        type: type,
        payload: rawPayload is Map
            ? rawPayload.cast<String, dynamic>()
            : const {},
      );
    });
    return MessageRealtimeConnection(
      threadId: threadId,
      events: frames,
      send: (command) async {
        channel.sink.add(jsonEncode(command));
      },
      close: () => channel.sink.close(1000),
      closeCode: () => channel.closeCode,
    );
  }

  @override
  Future<MessageEventPageInfo> recoverMessageEvents(
    int threadId, {
    required int after,
    int limit = 100,
  }) async {
    if (threadId <= 0 || after < 0 || limit < 1 || limit > 100) {
      throw const StarforgeException(
        code: 'invalid_event_cursor',
        message: 'Conversation recovery could not be started.',
      );
    }
    final payload = _map(
      await _request(
        'GET',
        '/api/v1/messaging/threads/$threadId/events/',
        query: {'after': '$after', 'limit': '$limit'},
      ),
    );
    final payloadThreadId = jsonInt(payload['thread_id']);
    final requestedAfter = jsonInt(payload['requested_after']);
    final nextCursor = jsonInt(payload['next_cursor']);
    final highWatermark = jsonInt(payload['high_watermark']);
    final recoveryFloor = jsonInt(payload['recovery_floor']);
    final hasMore = payload['has_more'];
    final resetRequired = payload['reset_required'];
    if (payloadThreadId != threadId ||
        requestedAfter != after ||
        nextCursor == null ||
        nextCursor < after ||
        highWatermark == null ||
        highWatermark < nextCursor ||
        recoveryFloor == null ||
        recoveryFloor < 1 ||
        recoveryFloor > highWatermark + 1 ||
        hasMore is! bool ||
        resetRequired is! bool ||
        payload['events'] is! List) {
      throw const StarforgeException(
        code: 'invalid_response',
        message: 'Conversation recovery returned invalid information.',
      );
    }
    var previousSequence = after;
    final events = <MessageEventPointerInfo>[];
    for (final raw in payload['events'] as List) {
      if (raw is! Map) {
        throw const StarforgeException(
          code: 'invalid_response',
          message: 'Conversation recovery returned invalid information.',
        );
      }
      final event = raw.cast<Object?, Object?>();
      final eventThreadId = jsonInt(event['thread_id']);
      final sequence = jsonInt(event['sequence']);
      final messageId = jsonInt(event['message_id']);
      final kind = jsonString(event['kind']);
      if (eventThreadId != threadId ||
          sequence == null ||
          sequence <= previousSequence ||
          sequence > highWatermark ||
          messageId == null ||
          messageId <= 0 ||
          (kind != 'message.created' && kind != 'read.updated')) {
        throw const StarforgeException(
          code: 'invalid_response',
          message: 'Conversation recovery returned invalid information.',
        );
      }
      previousSequence = sequence;
      events.add(
        MessageEventPointerInfo(
          sequence: sequence,
          kind: kind,
          messageId: messageId,
        ),
      );
    }
    if (events.length > limit ||
        (!resetRequired && events.isEmpty && nextCursor != after) ||
        (hasMore && (events.isEmpty || nextCursor >= highWatermark))) {
      throw const StarforgeException(
        code: 'invalid_response',
        message: 'Conversation recovery returned invalid information.',
      );
    }
    if (!resetRequired && events.isNotEmpty && nextCursor != previousSequence) {
      throw const StarforgeException(
        code: 'invalid_response',
        message: 'Conversation recovery returned invalid information.',
      );
    }
    if (resetRequired && events.isNotEmpty) {
      throw const StarforgeException(
        code: 'invalid_response',
        message: 'Conversation recovery returned invalid information.',
      );
    }
    return MessageEventPageInfo(
      events: List.unmodifiable(events),
      nextCursor: nextCursor,
      highWatermark: highWatermark,
      recoveryFloor: recoveryFloor,
      hasMore: hasMore,
      resetRequired: resetRequired,
    );
  }

  @override
  Future<MessageThreadInfo> createMessageThread({
    required int participantUserId,
    String subject = '',
  }) async {
    final payload = await _request(
      'POST',
      '/api/v1/messaging/threads/',
      body: {
        'participant_ids': [participantUserId],
        if (subject.trim().isNotEmpty) 'subject': subject.trim(),
      },
    );
    return MessageThreadInfo.fromJson(_map(payload));
  }

  @override
  Future<String> uploadMessageAttachment({
    required String filePath,
    required String filename,
    required String contentType,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    final payload = await _request(
      'POST',
      '/api/v1/messaging/attachments/upload-url/',
      body: {
        'filename': filename,
        'size_bytes': size,
        'content_type': contentType,
      },
    );
    final upload = _map(payload);
    final url = jsonString(upload['url']);
    final key = jsonString(upload['key']);
    if (!_isTrustedRemoteUrl(url) || key.isEmpty) {
      throw const StarforgeException(
        code: 'upload_unavailable',
        message: 'This attachment could not be prepared.',
      );
    }
    final request = http.MultipartRequest('POST', Uri.parse(url));
    final fields = upload['fields'];
    if (fields is Map) {
      for (final entry in fields.entries) {
        request.fields[entry.key.toString()] = entry.value.toString();
      }
    }
    request.files.add(
      await http.MultipartFile.fromPath('file', filePath, filename: filename),
    );
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 45));
      await streamed.stream.drain<void>();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw StarforgeException(
          code: 'upload_failed',
          message: 'This attachment could not be uploaded.',
          statusCode: streamed.statusCode,
        );
      }
      return key;
    } on TimeoutException {
      throw const StarforgeException(
        code: 'request_timeout',
        message: 'The attachment took too long to upload.',
      );
    } on SocketException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    } on http.ClientException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    }
  }

  @override
  Future<MessageInfo> sendMessage({
    required int threadId,
    String body = '',
    List<String> attachments = const [],
  }) async {
    final payload = await _request(
      'POST',
      '/api/v1/messaging/threads/$threadId/messages/',
      body: {
        'body': body.trim(),
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
    );
    return MessageInfo.fromJson(_map(payload));
  }

  @override
  Future<void> markMessageThreadRead(
    int threadId, {
    int? throughMessageId,
  }) async {
    await _request(
      'POST',
      '/api/v1/messaging/threads/$threadId/read/',
      body: {'through_message_id': ?throughMessageId},
    );
  }

  @override
  Future<String> messageAttachmentUrl({
    required int threadId,
    required String key,
  }) async {
    final payload = await _request(
      'GET',
      '/api/v1/messaging/threads/$threadId/attachments/download/',
      query: {'key': key},
    );
    final url = jsonString(_map(payload)['url']);
    if (!_isTrustedRemoteUrl(url)) {
      throw const StarforgeException(
        code: 'attachment_unavailable',
        message: 'This attachment is not available right now.',
      );
    }
    return url;
  }

  @override
  Future<List<ContentFolderInfo>> contentFolders() async {
    final items = await _getAll('/api/v1/content/folders/');
    return items.map(ContentFolderInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<ContentFileInfo>> contentFiles() async {
    final items = await _getAll('/api/v1/content/files/');
    return items.map(ContentFileInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<LibraryMaterialInfo>> libraryMaterials() async {
    final items = await _getAll('/api/v1/content/materials/');
    return items.map(LibraryMaterialInfo.fromJson).toList(growable: false);
  }

  @override
  Future<String> contentFileUrl(int fileId) async {
    final payload = await _request(
      'GET',
      '/api/v1/content/files/$fileId/download-url/',
    );
    final url = jsonString(_map(payload)['url']);
    if (!_isTrustedRemoteUrl(url)) {
      throw const StarforgeException(
        code: 'file_unavailable',
        message: 'This resource is not available right now.',
      );
    }
    return url;
  }

  @override
  Future<void> trackContentFileView(int fileId) async {
    await _request(
      'POST',
      '/api/v1/content/files/$fileId/track-view/',
      body: const {},
    );
  }

  @override
  Future<ContentFileInfo> approveContentFileAsTeacher(int fileId) async {
    final payload = await _request(
      'POST',
      '/api/v1/content/files/$fileId/approve-teacher/',
      body: const {},
    );
    return ContentFileInfo.fromJson(_map(payload));
  }

  @override
  Future<int> uploadContentFile({
    required String filePath,
    required String filename,
    required String contentType,
    required String title,
    required int folderId,
    required String audience,
    required bool downloadable,
  }) async {
    final file = File(filePath);
    final size = await file.length();
    final payload = await _request(
      'POST',
      '/api/v1/content/upload-url/',
      body: {
        'filename': filename,
        'content_type': contentType,
        'size_bytes': size,
        'title': title.trim(),
        'folder': folderId,
        if (audience.isNotEmpty) 'audience': audience,
        'is_downloadable': downloadable,
      },
    );
    final upload = _map(payload);
    final fileId = jsonInt(upload['file_id']);
    final url = jsonString(upload['url']);
    if (fileId == null || !_isTrustedRemoteUrl(url)) {
      throw const StarforgeException(
        code: 'upload_unavailable',
        message: 'This resource could not be prepared.',
      );
    }
    final request = http.StreamedRequest('PUT', Uri.parse(url))
      ..headers['Content-Type'] = contentType
      ..contentLength = size;
    try {
      final responseFuture = _client
          .send(request)
          .timeout(const Duration(seconds: 90));
      await request.sink.addStream(file.openRead());
      await request.sink.close();
      final response = await responseFuture;
      await response.stream.drain<void>();
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw StarforgeException(
          code: 'upload_failed',
          message: 'This resource could not be uploaded.',
          statusCode: response.statusCode,
        );
      }
    } on TimeoutException {
      throw const StarforgeException(
        code: 'request_timeout',
        message: 'The upload took too long.',
      );
    } on SocketException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    } on http.ClientException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    }
    await _request(
      'POST',
      '/api/v1/content/files/$fileId/confirm/',
      body: const {},
    );
    return fileId;
  }

  @override
  Future<List<PrinterInfo>> printers() async {
    final items = await _getAll('/api/v1/printing/printers/');
    return items.map(PrinterInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<PrintJobInfo>> printJobs() async {
    final envelope = await _requestEnvelope(
      'GET',
      '/api/v1/printing/jobs/',
      query: const {'ordering': '-created_at', 'page': '1', 'page_size': '20'},
    );
    final data = envelope['data'];
    final items = data is List
        ? data
              .whereType<Map>()
              .map((item) => item.cast<String, dynamic>())
              .toList(growable: false)
        : const <Map<String, dynamic>>[];
    return items.map(PrintJobInfo.fromJson).toList(growable: false);
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
    final file = File(filePath);
    final actualSize = await file.length();
    if (actualSize != sizeBytes) {
      throw const StarforgeException(
        code: 'file_changed',
        message: 'The selected file changed before it could be uploaded.',
      );
    }
    final payload = await _request(
      'POST',
      '/api/v1/printing/upload-url/',
      body: {
        'branch': branchId,
        'filename': filename,
        'content_type': contentType,
        'size_bytes': sizeBytes,
      },
    );
    final upload = _map(payload);
    final grantId = jsonInt(upload['grant_id']);
    final url = jsonString(upload['url']);
    final method = jsonString(upload['method']);
    if (grantId == null || !_isTrustedRemoteUrl(url) || method != 'POST') {
      throw const StarforgeException(
        code: 'upload_unavailable',
        message: 'This print file could not be prepared.',
      );
    }
    final request = http.MultipartRequest('POST', Uri.parse(url));
    final fields = upload['fields'];
    if (fields is Map) {
      for (final entry in fields.entries) {
        request.fields[entry.key.toString()] = entry.value.toString();
      }
    }
    request.files.add(
      await http.MultipartFile.fromPath('file', filePath, filename: filename),
    );
    try {
      final streamed = await _client
          .send(request)
          .timeout(const Duration(seconds: 90));
      await streamed.stream.drain<void>();
      if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
        throw StarforgeException(
          code: 'upload_failed',
          message: 'This print file could not be uploaded.',
          statusCode: streamed.statusCode,
        );
      }
    } on TimeoutException {
      throw const StarforgeException(
        code: 'request_timeout',
        message: 'The print upload took too long.',
      );
    } on SocketException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    } on http.ClientException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    }
    final created = await _request(
      'POST',
      '/api/v1/printing/jobs/',
      timeout: const Duration(seconds: 90),
      body: {
        'source': 'upload',
        'source_id': grantId,
        'copies': copies,
        'color': color,
        'duplex': duplex,
        'printer': printerId,
        if (scheduledFor != null)
          'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      },
    );
    return PrintJobInfo.fromJson(_map(created));
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
    final created = await _request(
      'POST',
      '/api/v1/printing/jobs/',
      timeout: const Duration(seconds: 90),
      body: {
        'source': 'content',
        'source_id': fileId,
        'copies': copies,
        'color': color,
        'duplex': duplex,
        'printer': printerId,
        if (scheduledFor != null)
          'scheduled_for': scheduledFor.toUtc().toIso8601String(),
      },
    );
    return PrintJobInfo.fromJson(_map(created));
  }

  @override
  Future<List<PayrollPayslipInfo>> ownPayslips() async {
    final items = await _getAll('/api/v1/payroll/payslips/mine/');
    final result = items
        .map(PayrollPayslipInfo.fromJson)
        .toList(growable: false);
    return result.toList()..sort(
      (left, right) => (right.generatedAt ?? DateTime(0)).compareTo(
        left.generatedAt ?? DateTime(0),
      ),
    );
  }

  @override
  Future<List<ComplianceRuleInfo>> ownRules() async {
    final payload = await _request('GET', '/api/v1/rulebook/rules/mine/');
    final items = payload is List ? payload.whereType<Map>() : const <Map>[];
    return items
        .map(
          (item) => ComplianceRuleInfo.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  @override
  Future<void> acknowledgeRule(int ruleId) async {
    await _request(
      'POST',
      '/api/v1/rulebook/rules/$ruleId/acknowledge/',
      body: const {},
    );
  }

  @override
  Future<List<NotificationInfo>> notifications() async {
    final envelope = await _requestEnvelope(
      'GET',
      '/api/v1/notifications/',
      query: const {'page_size': '50'},
    );
    final raw = envelope['results'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((item) => NotificationInfo.fromJson(item.cast<String, dynamic>()))
        .toList(growable: false);
  }

  @override
  Future<int> unreadNotificationCount() async {
    final payload = await _request(
      'GET',
      '/api/v1/notifications/unread-count/',
    );
    return jsonInt(_map(payload)['count']) ?? 0;
  }

  @override
  Future<void> markNotificationRead(int notificationId) async {
    await _request(
      'POST',
      '/api/v1/notifications/$notificationId/read/',
      body: const {},
    );
  }

  @override
  Future<void> markAllNotificationsRead() async {
    await _request('POST', '/api/v1/notifications/read-all/', body: const {});
  }

  @override
  Future<List<NotificationPreferenceInfo>> notificationPreferences() async {
    final payload = await _request('GET', '/api/v1/notifications/preferences/');
    final items = payload is List ? payload.whereType<Map>() : const <Map>[];
    return items
        .map(
          (item) =>
              NotificationPreferenceInfo.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  @override
  Future<List<NotificationPreferenceInfo>> updateNotificationPreferences(
    List<NotificationPreferenceInfo> preferences,
  ) async {
    final payload = await _request(
      'PUT',
      '/api/v1/notifications/preferences/',
      body: {
        'preferences': preferences
            .map((preference) => preference.toJson())
            .toList(growable: false),
      },
    );
    final items = payload is List ? payload.whereType<Map>() : const <Map>[];
    return items
        .map(
          (item) =>
              NotificationPreferenceInfo.fromJson(item.cast<String, dynamic>()),
        )
        .toList(growable: false);
  }

  @override
  Future<List<MeetingInfo>> upcomingMeetings() async {
    final items = await _getAll('/api/v1/meetings/upcoming/');
    return items.map(MeetingInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<CrmLeadInfo>> crmLeads() async {
    final items = await _getAll(
      '/api/v1/crm/leads/',
      query: {'ordering': '-updated_at'},
    );
    return items.map(CrmLeadInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<FinanceInvoiceInfo>> financeInvoices() async {
    final items = await _getAll(
      '/api/v1/finance/invoices/',
      query: {'ordering': '-created_at'},
    );
    return items.map(FinanceInvoiceInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<CashierShiftInfo>> ownCashierShifts() async {
    final items = await _getAll('/api/v1/finance/cashier-shifts/me/');
    return items.map(CashierShiftInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<StaffRequestInfo>> staffRequests() async {
    final items = await _getAll(
      '/api/v1/approvals/requests/',
      query: {'ordering': '-created_at'},
    );
    return items.map(StaffRequestInfo.fromJson).toList(growable: false);
  }

  @override
  Future<StaffRequestInfo> createStaffRequest({
    required String kind,
    required String title,
    required String description,
    int? branchId,
    double? amount,
  }) async {
    final payload = await _request(
      'POST',
      '/api/v1/approvals/requests/',
      body: {
        'kind': kind,
        'title': title.trim(),
        'description': description.trim(),
        'branch': ?branchId,
        if (amount != null && amount > 0) 'amount_uzs': amount,
        'payload': const <String, Object?>{},
      },
    );
    return StaffRequestInfo.fromJson(_map(payload));
  }

  @override
  Future<StaffRequestInfo> cancelStaffRequest(int requestId) async {
    final payload = await _request(
      'POST',
      '/api/v1/approvals/requests/$requestId/cancel/',
    );
    return StaffRequestInfo.fromJson(_map(payload));
  }

  @override
  Future<List<StaffFormInfo>> staffForms() async {
    final items = await _getAll(
      '/api/v1/forms/',
      query: {'ordering': '-created_at'},
    );
    return items.map(StaffFormInfo.fromJson).toList(growable: false);
  }

  @override
  Future<StaffFormInfo> staffForm(int formId) async {
    final payload = await _request('GET', '/api/v1/forms/$formId/');
    return StaffFormInfo.fromJson(_map(payload));
  }

  @override
  Future<void> submitStaffForm(int formId, Map<int, Object?> answers) async {
    await _request(
      'POST',
      '/api/v1/forms/$formId/submit/',
      body: {
        'answers': answers.entries
            .map((entry) => {'field': entry.key, 'value': entry.value})
            .toList(growable: false),
      },
    );
  }

  @override
  Future<List<StaffAchievementInfo>> staffAchievements() async {
    final items = await _getAll(
      '/api/v1/achievements/',
      query: {'ordering': '-created_at'},
    );
    return items.map(StaffAchievementInfo.fromJson).toList(growable: false);
  }

  @override
  Future<StaffAchievementInfo> createGroupAchievement({
    required int cohortId,
    required String name,
    required String description,
    required String emoji,
  }) async {
    final payload = await _request(
      'POST',
      '/api/v1/achievements/',
      body: {
        'name': name.trim(),
        'description': description.trim(),
        'emoji': emoji.trim().isEmpty ? '⭐' : emoji.trim(),
        'scope': 'group',
        'cohort': cohortId,
      },
    );
    return StaffAchievementInfo.fromJson(_map(payload));
  }

  @override
  Future<void> grantStaffAchievement({
    required int achievementId,
    required int studentId,
    required String note,
  }) async {
    await _request(
      'POST',
      '/api/v1/achievements/$achievementId/grant/',
      body: {'student': studentId, 'note': note.trim()},
    );
  }

  @override
  Future<List<StaffReportInfo>> staffReports() async {
    final items = await _getAll('/api/v1/reports/');
    return items.map(StaffReportInfo.fromJson).toList(growable: false);
  }

  @override
  Future<List<StaffReportRunInfo>> staffReportRuns() async {
    final items = await _getAll(
      '/api/v1/reports/runs/',
      query: {'ordering': '-created_at'},
    );
    return items.map(StaffReportRunInfo.fromJson).toList(growable: false);
  }

  @override
  Future<StaffReportRunInfo> createStaffReportRun({
    required String reportKey,
    required String format,
    required Map<String, Object?> params,
    List<int> recipientIds = const [],
  }) async {
    final payload = await _request(
      'POST',
      '/api/v1/reports/runs/',
      body: {
        'report_key': reportKey,
        'format': format,
        'params': params,
        'recipient_ids': recipientIds,
      },
    );
    return StaffReportRunInfo.fromJson(_map(payload));
  }

  @override
  Future<List<BranchChoiceInfo>> transferBranches() async {
    final items = await _getAll(
      '/api/v1/org/branches/',
      query: {'ordering': 'name'},
    );
    return items
        .map(BranchChoiceInfo.fromJson)
        .where((branch) => branch.isActive)
        .toList(growable: false);
  }

  @override
  Future<void> transferBranchSubject({
    required String subjectKind,
    required int subjectId,
    int? fromBranchId,
    required int toBranchId,
    required String reason,
    required bool confirmImpacts,
  }) async {
    await _request(
      'POST',
      '/api/v1/org/transfers/',
      body: {
        'subject_kind': subjectKind,
        if (subjectKind == 'student')
          'student': subjectId
        else
          'subject': subjectId,
        if (subjectKind == 'staff' && fromBranchId != null)
          'from_branch': fromBranchId,
        'to_branch': toBranchId,
        'reason': reason.trim(),
        'confirm_impacts': confirmImpacts,
      },
    );
  }

  @override
  Future<void> submitStudentRequest({
    required String action,
    required LearningGroup group,
    required Student student,
    required String description,
    int? branchId,
  }) async {
    await _request(
      'POST',
      '/api/v1/approvals/requests/',
      body: {
        'kind': 'other',
        'title': 'Student ${action.trim()}: ${student.name}',
        'description': description.trim(),
        'branch': ?branchId,
        'payload': {
          'request_type': 'student_$action',
          'student_id': int.tryParse(student.id),
          'student_name': student.name,
          'cohort_id': group.remoteId,
          'cohort_name': group.name,
        },
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getAll(
    String path, {
    Map<String, String> query = const {},
    int maxPages = 50,
  }) async {
    if (maxPages < 1) {
      throw ArgumentError.value(maxPages, 'maxPages', 'Must be at least 1.');
    }
    final result = <Map<String, dynamic>>[];
    var page = 1;
    var hasNext = true;
    while (hasNext && page <= maxPages) {
      final envelope = await _requestEnvelope(
        'GET',
        path,
        query: {...query, 'page': '$page', 'page_size': '100'},
      );
      final data = envelope['data'];
      if (data is List) {
        result.addAll(
          data.whereType<Map>().map((item) => item.cast<String, dynamic>()),
        );
      }
      final pagination = envelope['pagination'];
      hasNext = pagination is Map && pagination['has_next'] == true;
      page++;
    }
    if (hasNext) {
      throw const StarforgeException(
        code: 'response_too_large',
        message:
            'There is more information than can be loaded safely. Narrow the view and try again.',
      );
    }
    return result;
  }

  Future<Object?> _request(
    String method,
    String path, {
    Object? body,
    Map<String, String> query = const {},
    bool authenticated = true,
    Duration? timeout,
  }) async {
    final envelope = await _requestEnvelope(
      method,
      path,
      body: body,
      query: query,
      authenticated: authenticated,
      timeout: timeout,
    );
    return envelope['data'];
  }

  Future<Map<String, dynamic>> _requestEnvelope(
    String method,
    String path, {
    Object? body,
    Map<String, String> query = const {},
    bool authenticated = true,
    Duration? timeout,
  }) async {
    if (authenticated) {
      _access ??= await _sessionStore.readAccess();
      if (_access == null || _access!.isEmpty) {
        throw const StarforgeException(
          code: 'authentication_failed',
          message: 'Please sign in again.',
          statusCode: 401,
        );
      }
    }
    final uri = Uri.parse(
      '$baseUrl$path',
    ).replace(queryParameters: query.isEmpty ? null : query);
    final headers = <String, String>{
      'Accept': 'application/json',
      'Content-Type': 'application/json',
      'Accept-Language': language,
      if (authenticated) 'Authorization': 'Bearer $_access',
    };
    try {
      late http.Response response;
      final encoded = body == null ? null : jsonEncode(body);
      switch (method) {
        case 'GET':
          response = await _client
              .get(uri, headers: headers)
              .timeout(timeout ?? const Duration(seconds: 18));
        case 'POST':
          response = await _client
              .post(uri, headers: headers, body: encoded)
              .timeout(timeout ?? const Duration(seconds: 22));
        case 'PATCH':
          response = await _client
              .patch(uri, headers: headers, body: encoded)
              .timeout(timeout ?? const Duration(seconds: 22));
        case 'PUT':
          response = await _client
              .put(uri, headers: headers, body: encoded)
              .timeout(timeout ?? const Duration(seconds: 22));
        default:
          throw ArgumentError.value(method, 'method');
      }
      Map<String, dynamic> envelope = const {};
      if (response.body.isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) envelope = decoded.cast<String, dynamic>();
      }
      if (response.statusCode >= 200 && response.statusCode < 300) {
        return envelope;
      }
      final exception = StarforgeException(
        code: jsonString(envelope['code'], 'request_failed'),
        message: jsonString(
          envelope['message'],
          'Request could not be completed.',
        ),
        statusCode: response.statusCode,
        details: envelope['errors'],
      );
      if (exception.isAuthenticationFailure && authenticated) {
        await clearSession();
        _notifySessionExpired();
      }
      throw exception;
    } on TimeoutException {
      throw const StarforgeException(
        code: 'request_timeout',
        message: 'The request took too long.',
      );
    } on SocketException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    } on http.ClientException {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'A connection could not be established.',
      );
    } on FormatException {
      throw const StarforgeException(
        code: 'invalid_response',
        message: 'The response could not be read.',
      );
    }
  }

  static Map<String, dynamic> _map(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return value.cast<String, dynamic>();
    return const {};
  }

  bool _isTrustedRemoteUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      return false;
    }
    if (uri.scheme == 'https') return true;
    if (uri.scheme != 'http') return false;
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '127.0.0.1' || host == '::1';
  }
}

import 'package:flutter/material.dart';

enum StudentState { unmarked, present, absent, late, excused }

class Student {
  const Student({
    required this.id,
    required this.name,
    required this.phone,
    required this.guardian,
    required this.guardianPhone,
    required this.birthDate,
    required this.joinedDate,
    this.attendance,
    this.lastExam,
    this.state = StudentState.unmarked,
    this.hasSmartCard = false,
    this.hasWarningCard = false,
    this.email = '',
    this.status = '',
    this.academicLevel = '',
  });

  final String id;
  final String name;
  final String phone;
  final String guardian;
  final String guardianPhone;
  final String birthDate;
  final String joinedDate;

  /// A fraction in the range 0–1, or `null` when no attendance aggregate was
  /// supplied. Zero is a real measured value and must not double as "unknown".
  final double? attendance;
  final double? lastExam;
  final StudentState state;
  final bool hasSmartCard;
  final bool hasWarningCard;
  final String email;
  final String status;
  final String academicLevel;

  Student copyWith({
    StudentState? state,
    bool? hasSmartCard,
    bool? hasWarningCard,
    String? email,
    String? status,
    String? academicLevel,
    double? attendance,
  }) => Student(
    id: id,
    name: name,
    phone: phone,
    guardian: guardian,
    guardianPhone: guardianPhone,
    birthDate: birthDate,
    joinedDate: joinedDate,
    attendance: attendance ?? this.attendance,
    lastExam: lastExam,
    state: state ?? this.state,
    hasSmartCard: hasSmartCard ?? this.hasSmartCard,
    hasWarningCard: hasWarningCard ?? this.hasWarningCard,
    email: email ?? this.email,
    status: status ?? this.status,
    academicLevel: academicLevel ?? this.academicLevel,
  );
}

class LearningGroup {
  const LearningGroup({
    required this.id,
    required this.name,
    required this.course,
    required this.level,
    required this.studyMonth,
    required this.schedule,
    required this.room,
    required this.branch,
    required this.department,
    required this.mainTeacher,
    required this.progress,
    required this.attendance,
    required this.nextLesson,
    required this.students,
    this.isExamSoon = false,
    this.remoteId,
    this.branchId,
    this.capacity,
    this.primaryTeacherId,
    this.teacherIds = const [],
    this.assistantTeacherIds = const [],
    this.coTeacherIds = const [],
    this.startDate,
    this.endDate,
    this.lessonCycleLength,
  });

  final String id;
  final String name;
  final String course;
  final String level;
  final int? studyMonth;
  final String schedule;
  final String room;
  final String branch;
  final String department;
  final String mainTeacher;
  final double? progress;
  final double? attendance;
  final String nextLesson;
  final List<Student> students;
  final bool isExamSoon;
  final int? remoteId;
  final int? branchId;
  final int? capacity;
  final int? primaryTeacherId;
  final List<int> teacherIds;
  final List<int> assistantTeacherIds;
  final List<int> coTeacherIds;
  final DateTime? startDate;
  final DateTime? endDate;
  final int? lessonCycleLength;

  LearningGroup copyWith({
    String? level,
    int? studyMonth,
    String? schedule,
    String? nextLesson,
    List<Student>? students,
    double? attendance,
    double? progress,
    bool? isExamSoon,
    int? lessonCycleLength,
  }) => LearningGroup(
    id: id,
    name: name,
    course: course,
    level: level ?? this.level,
    studyMonth: studyMonth ?? this.studyMonth,
    schedule: schedule ?? this.schedule,
    room: room,
    branch: branch,
    department: department,
    mainTeacher: mainTeacher,
    progress: progress ?? this.progress,
    attendance: attendance ?? this.attendance,
    nextLesson: nextLesson ?? this.nextLesson,
    students: students ?? this.students,
    isExamSoon: isExamSoon ?? this.isExamSoon,
    remoteId: remoteId,
    branchId: branchId,
    capacity: capacity,
    primaryTeacherId: primaryTeacherId,
    teacherIds: teacherIds,
    assistantTeacherIds: assistantTeacherIds,
    coTeacherIds: coTeacherIds,
    startDate: startDate,
    endDate: endDate,
    lessonCycleLength: lessonCycleLength ?? this.lessonCycleLength,
  );
}

enum TaskStage { todo, inProgress, blocked, done, cancelled }

class StaffTask {
  const StaffTask({
    required this.id,
    required this.title,
    required this.description,
    required this.due,
    required this.assignee,
    required this.creator,
    required this.stage,
    this.highPriority = false,
    this.tags = const [],
    this.remoteId,
    this.rawStatus = 'open',
    this.assigneePrincipalKind = '',
    this.assigneePrincipalId,
    this.creatorPrincipalKind = '',
    this.creatorPrincipalId,
  });

  final String id;
  final String title;
  final String description;
  final String due;
  final String assignee;
  final String creator;
  final TaskStage stage;
  final bool highPriority;
  final List<String> tags;
  final int? remoteId;
  final String rawStatus;
  final String assigneePrincipalKind;
  final int? assigneePrincipalId;
  final String creatorPrincipalKind;
  final int? creatorPrincipalId;

  bool isAssignedTo({
    required String principalKind,
    required int principalId,
  }) =>
      assigneePrincipalKind == principalKind &&
      assigneePrincipalId == principalId;

  bool isCreatedBy({required String principalKind, required int principalId}) =>
      creatorPrincipalKind == principalKind &&
      creatorPrincipalId == principalId;

  StaffTask copyWith({TaskStage? stage, String? rawStatus}) => StaffTask(
    id: id,
    title: title,
    description: description,
    due: due,
    assignee: assignee,
    creator: creator,
    stage: stage ?? this.stage,
    highPriority: highPriority,
    tags: tags,
    remoteId: remoteId,
    rawStatus: rawStatus ?? this.rawStatus,
    assigneePrincipalKind: assigneePrincipalKind,
    assigneePrincipalId: assigneePrincipalId,
    creatorPrincipalKind: creatorPrincipalKind,
    creatorPrincipalId: creatorPrincipalId,
  );
}

class ChatContact {
  const ChatContact({
    required this.id,
    required this.name,
    required this.role,
    required this.preview,
    required this.time,
    this.unread = 0,
    this.online = false,
    this.isStudent = false,
    this.archived = false,
    this.remoteUserId,
    this.profileId,
    this.principalKind = '',
    this.threadId,
    this.participantUserIds = const [],
    this.participantNames = const {},
  });

  final String id;
  final String name;
  final String role;
  final String preview;
  final String time;
  final int unread;
  final bool online;
  final bool isStudent;
  final bool archived;
  final int? remoteUserId;
  final int? profileId;
  final String principalKind;
  final int? threadId;
  final List<int> participantUserIds;
  final Map<int, String> participantNames;

  bool get isGroup => participantUserIds.length > 1;

  ChatContact copyWith({
    String? id,
    String? name,
    String? role,
    String? preview,
    String? time,
    int? unread,
    bool? online,
    bool? isStudent,
    bool? archived,
    int? remoteUserId,
    int? profileId,
    String? principalKind,
    int? threadId,
    List<int>? participantUserIds,
    Map<int, String>? participantNames,
  }) => ChatContact(
    id: id ?? this.id,
    name: name ?? this.name,
    role: role ?? this.role,
    preview: preview ?? this.preview,
    time: time ?? this.time,
    unread: unread ?? this.unread,
    online: online ?? this.online,
    isStudent: isStudent ?? this.isStudent,
    archived: archived ?? this.archived,
    remoteUserId: remoteUserId ?? this.remoteUserId,
    profileId: profileId ?? this.profileId,
    principalKind: principalKind ?? this.principalKind,
    threadId: threadId ?? this.threadId,
    participantUserIds: participantUserIds ?? this.participantUserIds,
    participantNames: participantNames ?? this.participantNames,
  );
}

class MessagingWorkspace {
  const MessagingWorkspace({required this.threads, required this.contacts});

  const MessagingWorkspace.empty() : threads = const [], contacts = const [];

  final List<ChatContact> threads;
  final List<ChatContact> contacts;
}

enum MessageType { text, voice, image, video, file }

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.text,
    required this.time,
    required this.isMine,
    this.type = MessageType.text,
    this.duration,
    this.senderName = '',
    this.sentAt,
    this.attachmentKey = '',
    this.attachmentUrl = '',
  });

  final String id;
  final String text;
  final String time;
  final bool isMine;
  final MessageType type;
  final String? duration;
  final String senderName;
  final DateTime? sentAt;
  final String attachmentKey;
  final String attachmentUrl;

  bool get isPending => id.startsWith('local-') || id.startsWith('upload-');

  ChatMessage copyWith({
    String? id,
    String? text,
    String? time,
    bool? isMine,
    MessageType? type,
    String? duration,
    String? senderName,
    DateTime? sentAt,
    String? attachmentKey,
    String? attachmentUrl,
  }) => ChatMessage(
    id: id ?? this.id,
    text: text ?? this.text,
    time: time ?? this.time,
    isMine: isMine ?? this.isMine,
    type: type ?? this.type,
    duration: duration ?? this.duration,
    senderName: senderName ?? this.senderName,
    sentAt: sentAt ?? this.sentAt,
    attachmentKey: attachmentKey ?? this.attachmentKey,
    attachmentUrl: attachmentUrl ?? this.attachmentUrl,
  );
}

enum LibraryKind { book, playlist, podcast, video }

class LibraryResource {
  const LibraryResource({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.author,
    required this.kind,
    required this.color,
    required this.icon,
    this.downloadable = true,
    this.progress,
    this.remoteFileId,
    this.remoteMaterialId,
    this.contentType = '',
    this.body = '',
    this.status = '',
    this.remoteUrl = '',
    this.thumbnailUrl = '',
    this.createdAt,
    this.teacherApproved = false,
    this.managerApproved = false,
    this.rejectReason = '',
  });

  final String id;
  final String title;
  final String subtitle;
  final String author;
  final LibraryKind kind;
  final Color color;
  final IconData icon;
  final bool downloadable;
  final double? progress;
  final int? remoteFileId;
  final int? remoteMaterialId;
  final String contentType;
  final String body;
  final String status;
  final String remoteUrl;
  final String thumbnailUrl;
  final DateTime? createdAt;
  final bool teacherApproved;
  final bool managerApproved;
  final String rejectReason;

  bool get isPublished =>
      status == 'published' ||
      status == 'clean' && teacherApproved && managerApproved;

  LibraryResource copyWith({
    String? remoteUrl,
    String? status,
    bool? teacherApproved,
    bool? managerApproved,
    String? rejectReason,
  }) => LibraryResource(
    id: id,
    title: title,
    subtitle: subtitle,
    author: author,
    kind: kind,
    color: color,
    icon: icon,
    downloadable: downloadable,
    progress: progress,
    remoteFileId: remoteFileId,
    remoteMaterialId: remoteMaterialId,
    contentType: contentType,
    body: body,
    status: status ?? this.status,
    remoteUrl: remoteUrl ?? this.remoteUrl,
    thumbnailUrl: thumbnailUrl,
    createdAt: createdAt,
    teacherApproved: teacherApproved ?? this.teacherApproved,
    managerApproved: managerApproved ?? this.managerApproved,
    rejectReason: rejectReason ?? this.rejectReason,
  );
}

class LibraryFolder {
  const LibraryFolder({
    required this.id,
    required this.name,
    required this.libraryName,
    this.parentName = '',
    this.visibility = '',
    this.cohortId,
    this.cohortName = '',
  });

  final int id;
  final String name;
  final String libraryName;
  final String parentName;
  final String visibility;
  final int? cohortId;
  final String cohortName;

  String get displayPath => [
    libraryName,
    if (parentName.isNotEmpty) parentName,
    name,
  ].where((part) => part.isNotEmpty).join(' / ');
}

class LibraryWorkspace {
  const LibraryWorkspace({required this.resources, required this.folders});

  const LibraryWorkspace.empty() : resources = const [], folders = const [];

  final List<LibraryResource> resources;
  final List<LibraryFolder> folders;
}

class PrinterDevice {
  const PrinterDevice({
    required this.id,
    required this.name,
    required this.location,
    required this.toner,
    required this.paper,
    this.isBusy = false,
    this.isOffline = false,
    this.supportsColor = false,
    this.supportsDuplex = false,
    this.branchId,
  });

  final String id;
  final String name;
  final String location;
  final double toner;
  final String paper;
  final bool isBusy;
  final bool isOffline;
  final bool supportsColor;
  final bool supportsDuplex;
  final int? branchId;
}

class StaffPrintJob {
  const StaffPrintJob({
    required this.id,
    required this.status,
    required this.source,
    required this.pages,
    required this.copies,
    required this.color,
    required this.duplex,
    required this.createdAt,
    required this.finishedAt,
    this.scheduledFor,
  });

  final int id;
  final String status;
  final String source;
  final int pages;
  final int copies;
  final bool color;
  final bool duplex;
  final DateTime createdAt;
  final DateTime? finishedAt;
  final DateTime? scheduledFor;
}

class PrintWorkspace {
  const PrintWorkspace({required this.printers, required this.jobs});

  const PrintWorkspace.empty() : printers = const [], jobs = const [];

  final List<PrinterDevice> printers;
  final List<StaffPrintJob> jobs;
}

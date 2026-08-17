import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:video_player/video_player.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../data/models.dart';
import '../../services/starforge_api.dart';

class ConversationPage extends StatefulWidget {
  const ConversationPage({super.key, required this.contact});
  final ChatContact contact;

  @override
  State<ConversationPage> createState() => _ConversationPageState();
}

class _ConversationPageState extends State<ConversationPage>
    with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _imagePicker = ImagePicker();
  AudioRecorder? _recorder;
  final List<ChatMessage> _messages = [];
  bool _loading = true;
  bool _failed = false;
  bool _polling = false;
  bool _loadingOlder = false;
  bool _olderLoadFailed = false;
  bool _appIsActive = true;
  int? _nextOlderPage;
  Timer? _pollTimer;
  Timer? _realtimeReconnectTimer;
  MessageRealtimeConnection? _realtime;
  StreamSubscription<MessageRealtimeFrame>? _realtimeSubscription;
  int _realtimeCursor = 0;
  int _realtimeReconnectAttempt = 0;
  bool _realtimeConnecting = false;
  bool _realtimeRecovering = false;
  Timer? _voiceLimitTimer;
  DateTime? _voiceStartedAt;
  bool _voiceStarting = false;
  bool _voiceRecording = false;
  bool _voiceStopRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    final lifecycleState = WidgetsBinding.instance.lifecycleState;
    _appIsActive =
        lifecycleState == null || lifecycleState == AppLifecycleState.resumed;
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final active = state == AppLifecycleState.resumed;
    if (_appIsActive == active) return;
    _appIsActive = active;
    if (active) {
      unawaited(_startRealtime(pollFallbackImmediately: true));
    } else {
      _pollTimer?.cancel();
      _pollTimer = null;
      _realtimeReconnectTimer?.cancel();
      _realtimeReconnectTimer = null;
      unawaited(_closeRealtime());
      unawaited(_cancelVoiceRecording());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _pollTimer?.cancel();
    _realtimeReconnectTimer?.cancel();
    final realtimeSubscription = _realtimeSubscription;
    if (realtimeSubscription != null) unawaited(realtimeSubscription.cancel());
    final realtime = _realtime;
    if (realtime != null) unawaited(realtime.close());
    _voiceLimitTimer?.cancel();
    final recorder = _recorder;
    if (recorder != null) {
      unawaited(recorder.cancel());
      unawaited(recorder.dispose());
    }
    super.dispose();
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (!_appIsActive || !mounted || _loading || _failed) return;
    _pollTimer = Timer.periodic(
      const Duration(seconds: 6),
      (_) => unawaited(_pollForMessages()),
    );
  }

  Future<void> _closeRealtime() async {
    final subscription = _realtimeSubscription;
    final realtime = _realtime;
    _realtimeSubscription = null;
    _realtime = null;
    final cancelled = subscription?.cancel();
    if (realtime != null) await realtime.close();
    await cancelled;
  }

  Future<void> _startRealtime({bool pollFallbackImmediately = false}) async {
    if (!mounted ||
        !_appIsActive ||
        _loading ||
        _failed ||
        _realtimeConnecting ||
        _realtime != null) {
      return;
    }
    _realtimeConnecting = true;
    try {
      final connection = await AppControllerScope.of(
        context,
      ).connectConversationRealtime(widget.contact);
      if (!mounted || !_appIsActive) {
        await connection?.close();
        return;
      }
      if (connection == null) {
        _startPolling();
        if (pollFallbackImmediately) await _pollForMessages();
        return;
      }
      _pollTimer?.cancel();
      _pollTimer = null;
      _realtime = connection;
      _realtimeSubscription = connection.events.listen(
        _handleRealtimeFrame,
        onError: (_) => _handleRealtimeEnded(),
        onDone: _handleRealtimeEnded,
        cancelOnError: true,
      );
    } catch (_) {
      _startPolling();
      _scheduleRealtimeReconnect();
    } finally {
      _realtimeConnecting = false;
    }
  }

  void _scheduleRealtimeReconnect({Duration? minimumDelay}) {
    if (!mounted || !_appIsActive || _loading || _failed) return;
    _realtimeReconnectTimer?.cancel();
    final attempt = _realtimeReconnectAttempt.clamp(0, 5);
    final exponential = Duration(seconds: math.min(30, 1 << attempt));
    final delay = minimumDelay != null && minimumDelay > exponential
        ? minimumDelay
        : exponential;
    _realtimeReconnectAttempt++;
    _realtimeReconnectTimer = Timer(delay, () => unawaited(_startRealtime()));
  }

  void _handleRealtimeEnded() {
    final connection = _realtime;
    _realtime = null;
    _realtimeSubscription = null;
    if (!mounted || !_appIsActive) return;
    final closeCode = connection?.closeCode();
    if (closeCode == 4401) {
      unawaited(
        AppControllerScope.of(
          context,
        ).handleMessagingRealtimeClosure(closeCode),
      );
      return;
    }
    if (closeCode == 4403) {
      // Membership/permission was revoked. Reloading fails closed or provides
      // the still-authorized view without repeatedly reconnecting.
      unawaited(_load());
      return;
    }
    _startPolling();
    _scheduleRealtimeReconnect(
      minimumDelay: closeCode == 4429 ? const Duration(seconds: 30) : null,
    );
  }

  void _handleRealtimeFrame(MessageRealtimeFrame frame) {
    if (!mounted || !_appIsActive) return;
    switch (frame.type) {
      case 'ping':
        unawaited(_realtime?.send(const {'type': 'pong'}));
      case 'thread.ready':
        final threadId = frame.payload['thread_id'];
        final protocol = frame.payload['protocol'];
        final highWatermark = frame.payload['high_watermark'];
        final recoveryFloor = frame.payload['recovery_floor'];
        if (protocol != 'starforge.messaging.thread.v1' ||
            threadId is! int ||
            threadId != _realtime?.threadId ||
            highWatermark is! int ||
            highWatermark < 0 ||
            recoveryFloor is! int ||
            recoveryFloor < 1) {
          unawaited(_fallbackFromRealtime());
          return;
        }
        _realtimeReconnectAttempt = 0;
        if (_realtimeCursor > highWatermark) {
          _realtimeCursor = 0;
          unawaited(
            AppControllerScope.of(
              context,
            ).saveConversationEventCursor(widget.contact, 0),
          );
        }
        unawaited(_recoverRealtime());
      case 'thread.event':
        final threadId = frame.payload['thread_id'];
        final sequence = frame.payload['sequence'];
        if (threadId != _realtime?.threadId ||
            sequence is! int ||
            sequence <= 0) {
          return;
        }
        if (sequence <= _realtimeCursor) return;
        unawaited(_recoverRealtime());
      case 'thread.sync':
        unawaited(_applyRealtimePage(frame.payload));
      case 'protocol.error':
        unawaited(_fallbackFromRealtime());
      default:
        // Forward-compatible: unknown event types cannot mutate local state.
        break;
    }
  }

  Future<void> _recoverRealtime() async {
    if (_realtimeRecovering || !mounted || !_appIsActive) return;
    final controller = AppControllerScope.of(context);
    _realtimeRecovering = true;
    try {
      while (mounted && _appIsActive) {
        final page = await controller.recoverConversationEvents(
          widget.contact,
          after: _realtimeCursor,
        );
        if (page == null) {
          _startPolling();
          return;
        }
        if (page.resetRequired) {
          await _reloadRealtimeSnapshot(page.highWatermark);
          return;
        }
        final cursorBefore = _realtimeCursor;
        _realtimeCursor = page.nextCursor;
        await controller.saveConversationEventCursor(
          widget.contact,
          _realtimeCursor,
        );
        final shouldRefresh = page.events.any(
          (event) => event.kind == 'message.created',
        );
        if (shouldRefresh) await _pollForMessages();
        if (!page.hasMore) return;
        if (_realtimeCursor <= cursorBefore) {
          throw const StarforgeException(
            code: 'invalid_event_cursor',
            message: 'Conversation recovery did not advance.',
          );
        }
      }
    } catch (_) {
      await _fallbackFromRealtime();
    } finally {
      _realtimeRecovering = false;
    }
  }

  Future<void> _fallbackFromRealtime() async {
    await _closeRealtime();
    if (!mounted || !_appIsActive) return;
    _startPolling();
    _scheduleRealtimeReconnect();
  }

  Future<void> _applyRealtimePage(Map<String, dynamic> payload) async {
    final reset = payload['reset_required'];
    final highWatermark = payload['high_watermark'];
    final nextCursor = payload['next_cursor'];
    if (reset == true && highWatermark is int && highWatermark >= 0) {
      await _reloadRealtimeSnapshot(highWatermark);
      return;
    }
    if (nextCursor is int && nextCursor > _realtimeCursor) {
      // Treat the socket page only as a hint. The authenticated HTTP recovery
      // endpoint validates and orders every pointer before advancing state.
      await _recoverRealtime();
    }
  }

  Future<void> _reloadRealtimeSnapshot(int cursor) async {
    final page = await AppControllerScope.of(
      context,
    ).loadConversationPage(widget.contact);
    if (!mounted || !_appIsActive) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(page.messages);
      _nextOlderPage = page.nextOlderPage;
    });
    _realtimeCursor = cursor;
    await AppControllerScope.of(
      context,
    ).saveConversationEventCursor(widget.contact, cursor);
    await _hydrateRecentAttachments();
    _scrollToEnd();
  }

  void _scrollToEnd() {
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Future<void> _load() async {
    _pollTimer?.cancel();
    _pollTimer = null;
    if (mounted) {
      setState(() {
        _loading = true;
        _failed = false;
        _olderLoadFailed = false;
      });
    }
    try {
      final controller = AppControllerScope.of(context);
      final page = await controller.loadConversationPage(widget.contact);
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(page.messages);
        _nextOlderPage = page.nextOlderPage;
        _loading = false;
      });
      _realtimeCursor = controller.loadConversationEventCursor(widget.contact);
      await _hydrateRecentAttachments();
      _scrollToEnd();
      await _startRealtime();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _failed = true;
      });
    }
  }

  Future<void> _pollForMessages() async {
    if (_polling || !mounted || !_appIsActive || _loading || _failed) return;
    final afterId = _messages
        .map((message) => int.tryParse(message.id) ?? 0)
        .fold<int>(0, (largest, id) => largest > id ? largest : id);
    _polling = true;
    final followLatest = _isNearConversationEnd();
    try {
      final updates = await AppControllerScope.of(
        context,
      ).loadConversationUpdates(widget.contact, afterId: afterId);
      if (!mounted || !_appIsActive || updates.isEmpty) return;
      final known = _messages.map((message) => message.id).toSet();
      final fresh = updates
          .where((message) => known.add(message.id))
          .toList(growable: false);
      if (fresh.isEmpty) return;
      setState(() => _messages.addAll(fresh));
      await _hydrateRecentAttachments(messages: fresh);
      if (followLatest) _scrollToEnd();
    } catch (_) {
      // Polling is best effort; the visible conversation remains usable offline.
    } finally {
      _polling = false;
    }
  }

  bool _isNearConversationEnd() {
    if (!_scrollController.hasClients) return true;
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels < 180;
  }

  Future<void> _loadOlderMessages() async {
    final page = _nextOlderPage;
    if (page == null || _loadingOlder) return;
    final oldExtent = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;
    final oldOffset = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    setState(() {
      _loadingOlder = true;
      _olderLoadFailed = false;
    });
    try {
      final history = await AppControllerScope.of(
        context,
      ).loadOlderConversationPage(widget.contact, page: page);
      if (!mounted) return;
      final known = _messages.map((message) => message.id).toSet();
      final older = history.messages
          .where((message) => known.add(message.id))
          .toList(growable: false);
      setState(() {
        _messages.insertAll(0, older);
        _nextOlderPage = history.nextOlderPage;
        _loadingOlder = false;
      });
      await _hydrateRecentAttachments(messages: older);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        final addedExtent =
            _scrollController.position.maxScrollExtent - oldExtent;
        _scrollController.jumpTo(
          (oldOffset + addedExtent).clamp(
            _scrollController.position.minScrollExtent,
            _scrollController.position.maxScrollExtent,
          ),
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loadingOlder = false;
        _olderLoadFailed = true;
      });
    }
  }

  Future<void> _hydrateRecentAttachments({
    Iterable<ChatMessage>? messages,
  }) async {
    final source = (messages ?? _messages.reversed)
        .where(
          (message) =>
              message.attachmentKey.isNotEmpty &&
              message.attachmentUrl.isEmpty &&
              (message.type == MessageType.image ||
                  message.type == MessageType.video),
        )
        .take(18)
        .toList(growable: false);
    if (source.isEmpty) return;
    final controller = AppControllerScope.of(context);
    final hydrated = await Future.wait(
      source.map((message) async {
        try {
          return await controller.prepareMessageAttachment(
            widget.contact,
            message,
          );
        } catch (_) {
          return message;
        }
      }),
    );
    if (!mounted) return;
    final byId = {for (final message in hydrated) message.id: message};
    setState(() {
      for (var index = 0; index < _messages.length; index++) {
        _messages[index] = byId[_messages[index].id] ?? _messages[index];
      }
    });
  }

  Future<void> _sendText() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final localId = 'local-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: localId,
      text: text,
      time: TimeOfDay.now().format(context),
      isMine: true,
      sentAt: DateTime.now(),
    );
    setState(() {
      _messages.add(optimistic);
      _messageController.clear();
    });
    _scrollToEnd();
    try {
      final sent = await AppControllerScope.of(
        context,
      ).sendTextMessage(widget.contact, text);
      if (!mounted) return;
      setState(() => _reconcileOptimisticMessage(localId, sent));
      unawaited(_startRealtime());
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _messages.removeWhere((message) => message.id == localId);
        if (_messageController.text.trim().isEmpty) {
          _messageController.text = text;
          _messageController.selection = TextSelection.collapsed(
            offset: text.length,
          );
        }
      });
      showPremiumToast(
        context,
        context.tr('messageSendFailed'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  Future<void> _startVoice() async {
    if (_voiceStarting || _voiceRecording) return;
    _voiceStarting = true;
    _voiceStopRequested = false;
    final recorder = _recorder ??= AudioRecorder();
    try {
      if (!await recorder.hasPermission()) {
        if (mounted) {
          showPremiumToast(
            context,
            context.tr('microphonePermissionNeeded'),
            icon: Icons.mic_off_outlined,
            color: AppTheme.gold,
          );
        }
        return;
      }
      final directory = await getTemporaryDirectory();
      final path =
          '${directory.path}/starforge_voice_${DateTime.now().microsecondsSinceEpoch}.m4a';
      await recorder.start(
        const RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 64000,
          sampleRate: 44100,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
        ),
        path: path,
      );
      _voiceStartedAt = DateTime.now();
      _voiceRecording = true;
      _voiceLimitTimer?.cancel();
      _voiceLimitTimer = Timer(
        const Duration(minutes: 5),
        () => unawaited(_finishVoiceRecording()),
      );
      if (mounted) setState(() {});
      if (_voiceStopRequested) await _finishVoiceRecording();
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          context.tr('voiceRecordingFailed'),
          icon: Icons.mic_off_outlined,
          color: AppTheme.coral,
        );
      }
    } finally {
      _voiceStarting = false;
    }
  }

  Future<void> _sendVoice() async {
    if (_voiceStarting) {
      _voiceStopRequested = true;
      return;
    }
    await _finishVoiceRecording();
  }

  Future<void> _finishVoiceRecording() async {
    if (!_voiceRecording) return;
    _voiceLimitTimer?.cancel();
    _voiceLimitTimer = null;
    final startedAt = _voiceStartedAt;
    _voiceRecording = false;
    _voiceStartedAt = null;
    if (mounted) setState(() {});
    String? path;
    try {
      path = await _recorder?.stop();
      if (path == null || path.isEmpty) throw StateError('No voice file');
      final elapsed = DateTime.now().difference(startedAt ?? DateTime.now());
      if (elapsed < const Duration(milliseconds: 350)) {
        await _deleteTemporaryVoice(path);
        if (mounted) {
          showPremiumToast(
            context,
            context.tr('voiceMessageTooShort'),
            icon: Icons.mic_none_rounded,
          );
        }
        return;
      }
      await _sendAttachment(
        path: path,
        filename: 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
        contentType: 'audio/mp4',
        type: MessageType.voice,
        duration: _formatVoiceDuration(elapsed),
      );
    } catch (_) {
      if (mounted) {
        showPremiumToast(
          context,
          context.tr('voiceRecordingFailed'),
          icon: Icons.mic_off_outlined,
          color: AppTheme.coral,
        );
      }
    } finally {
      if (path != null) await _deleteTemporaryVoice(path);
    }
  }

  Future<void> _cancelVoiceRecording() async {
    _voiceStopRequested = false;
    _voiceLimitTimer?.cancel();
    _voiceLimitTimer = null;
    if (!_voiceStarting && !_voiceRecording) return;
    _voiceRecording = false;
    _voiceStartedAt = null;
    try {
      await _recorder?.cancel();
    } catch (_) {
      // Lifecycle cleanup is best effort; no partial recording is sent.
    }
    if (mounted) setState(() {});
  }

  Future<void> _deleteTemporaryVoice(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Temporary-file cleanup is retried by the operating system.
    }
  }

  String _formatVoiceDuration(Duration value) {
    final seconds = value.inSeconds.clamp(0, 300);
    return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
  }

  void _unsupportedFormat() => showPremiumToast(
    context,
    context.tr('unsupportedAttachmentFormat'),
    icon: Icons.info_outline_rounded,
    color: AppTheme.gold,
  );

  Future<void> _pickImage(ImageSource source) async {
    Navigator.pop(context);
    final file = await _imagePicker.pickImage(source: source, imageQuality: 82);
    if (file == null || !mounted) return;
    if (!const {'jpg', 'jpeg', 'png', 'webp'}.contains(_extension(file.name))) {
      _unsupportedFormat();
      return;
    }
    await _sendAttachment(
      path: file.path,
      filename: file.name,
      contentType: _contentType(file.name),
      type: MessageType.image,
    );
  }

  Future<void> _pickVideo() async {
    Navigator.pop(context);
    final file = await _imagePicker.pickVideo(
      source: ImageSource.gallery,
      maxDuration: const Duration(minutes: 5),
    );
    if (file == null || !mounted) return;
    if (_extension(file.name) != 'mp4') {
      _unsupportedFormat();
      return;
    }
    await _sendAttachment(
      path: file.path,
      filename: file.name,
      contentType: _contentType(file.name),
      type: MessageType.video,
    );
  }

  Future<void> _pickAudio() async {
    Navigator.pop(context);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['mp3'],
    );
    if (result == null || !mounted) return;
    final selected = result.files.single;
    if (selected.path == null || _extension(selected.name) != 'mp3') {
      _unsupportedFormat();
      return;
    }
    await _sendAttachment(
      path: selected.path!,
      filename: selected.name,
      contentType: 'audio/mpeg',
      type: MessageType.voice,
    );
  }

  Future<void> _pickFile() async {
    Navigator.pop(context);
    final result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'docx', 'pptx'],
    );
    if (result == null || !mounted) return;
    final selected = result.files.single;
    if (selected.path == null) {
      showPremiumToast(
        context,
        context.tr('messageAttachmentFailed'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
      return;
    }
    await _sendAttachment(
      path: selected.path!,
      filename: selected.name,
      contentType: _contentType(selected.name),
      type: MessageType.file,
    );
  }

  Future<void> _sendAttachment({
    required String path,
    required String filename,
    required String contentType,
    required MessageType type,
    String? duration,
  }) async {
    final localId = 'upload-${DateTime.now().microsecondsSinceEpoch}';
    final optimistic = ChatMessage(
      id: localId,
      text: filename,
      time: TimeOfDay.now().format(context),
      isMine: true,
      type: type,
      duration: duration,
      sentAt: DateTime.now(),
    );
    setState(() => _messages.add(optimistic));
    _scrollToEnd();
    try {
      final sent = await AppControllerScope.of(context).sendAttachmentMessage(
        contact: widget.contact,
        filePath: path,
        filename: _safeAttachmentName(filename),
        contentType: contentType,
      );
      if (!mounted) return;
      final resolved = sent.copyWith(duration: duration);
      setState(() => _reconcileOptimisticMessage(localId, resolved));
      unawaited(_startRealtime());
      await _hydrateRecentAttachments(messages: [resolved]);
    } catch (_) {
      if (!mounted) return;
      setState(() => _messages.removeWhere((message) => message.id == localId));
      showPremiumToast(
        context,
        context.tr('messageAttachmentFailed'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  void _reconcileOptimisticMessage(String localId, ChatMessage sent) {
    final localIndex = _messages.indexWhere((message) => message.id == localId);
    final remoteIndex = _messages.indexWhere(
      (message) => message.id == sent.id,
    );
    if (remoteIndex >= 0) {
      _messages[remoteIndex] = sent;
      if (localIndex >= 0 && localIndex != remoteIndex) {
        _messages.removeAt(localIndex);
      }
      return;
    }
    if (localIndex >= 0) {
      _messages[localIndex] = sent;
    } else {
      _messages.add(sent);
    }
  }

  String _extension(String filename) =>
      filename.contains('.') ? filename.split('.').last.toLowerCase() : '';

  String _safeAttachmentName(String filename) {
    final extension = _extension(filename);
    final rawStem = filename.replaceFirst(RegExp(r'\.[^.]+$'), '');
    var stem = rawStem
        .replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_')
        .replaceAll(RegExp(r'^\.+'), '')
        .replaceAll(RegExp(r'_+'), '_');
    if (stem.isEmpty) {
      stem = 'starforge_${DateTime.now().millisecondsSinceEpoch}';
    }
    if (stem.length > 180) stem = stem.substring(0, 180);
    return extension.isEmpty ? stem : '$stem.$extension';
  }

  String _contentType(String filename) {
    final extension = filename.contains('.')
        ? filename.split('.').last.toLowerCase()
        : '';
    return switch (extension) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'mp4' => 'video/mp4',
      'mp3' => 'audio/mpeg',
      'm4a' => 'audio/mp4',
      'pdf' => 'application/pdf',
      'docx' =>
        'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      'pptx' =>
        'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      _ => 'application/octet-stream',
    };
  }

  void _showAttachments() {
    showAppSheet<void>(
      context: context,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('upload'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.spaceEvenly,
              runSpacing: 12,
              children: [
                _AttachmentAction(
                  icon: Icons.camera_alt_outlined,
                  label: context.tr('camera'),
                  color: Theme.of(context).colorScheme.primary,
                  onTap: () => _pickImage(ImageSource.camera),
                ),
                _AttachmentAction(
                  icon: Icons.photo_library_outlined,
                  label: context.tr('gallery'),
                  color: AppTheme.gold,
                  onTap: () => _pickImage(ImageSource.gallery),
                ),
                _AttachmentAction(
                  icon: Icons.video_library_outlined,
                  label: context.tr('videos'),
                  color: const Color(0xFF248C7A),
                  onTap: _pickVideo,
                ),
                _AttachmentAction(
                  icon: Icons.audio_file_outlined,
                  label: context.tr('audio'),
                  color: const Color(0xFF2A3D8F),
                  onTap: _pickAudio,
                ),
                _AttachmentAction(
                  icon: Icons.description_outlined,
                  label: context.tr('file'),
                  color: const Color(0xFFC27A36),
                  onTap: _pickFile,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool _sameDay(DateTime? left, DateTime? right) {
    if (left == null || right == null) return left == right;
    final a = left.toLocal();
    final b = right.toLocal();
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateLabel(ChatMessage message) {
    final value = message.sentAt?.toLocal();
    if (value == null) return context.tr('today');
    final now = DateTime.now();
    if (_sameDay(value, now)) return context.tr('today');
    final yesterday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(const Duration(days: 1));
    if (_sameDay(value, yesterday)) return context.tr('yesterday');
    return DateFormat.yMMMd(
      Localizations.localeOf(context).languageCode,
    ).format(value);
  }

  Future<void> _openAttachment(ChatMessage message) async {
    if (message.isPending || message.attachmentKey.isEmpty) {
      showPremiumToast(
        context,
        context.tr('resourceBeingPrepared'),
        icon: Icons.cloud_upload_outlined,
        color: AppTheme.gold,
      );
      return;
    }
    try {
      final ready = await AppControllerScope.of(
        context,
      ).prepareMessageAttachment(widget.contact, message);
      if (!mounted) return;
      final uri = Uri.tryParse(ready.attachmentUrl);
      if (uri == null) throw StateError('Missing attachment URL');
      switch (ready.type) {
        case MessageType.image:
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _ImageAttachmentPage(message: ready),
            ),
          );
        case MessageType.video:
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _VideoAttachmentPage(message: ready),
            ),
          );
        case MessageType.voice:
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => _AudioAttachmentPage(message: ready),
            ),
          );
        case MessageType.file:
          if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
            throw StateError('Could not open attachment');
          }
        case MessageType.text:
          return;
      }
    } catch (_) {
      if (!mounted) return;
      showPremiumToast(
        context,
        context.tr('messageAttachmentFailed'),
        icon: Icons.error_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = AppControllerScope.of(context);
    final name = widget.contact.name.isEmpty
        ? context.tr('conversation')
        : widget.contact.name;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Row(
          children: [
            PersonAvatar(name: name, size: 39),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  Text(
                    widget.contact.online
                        ? context.tr('recentlyActive')
                        : widget.contact.role,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          if (widget.contact.threadId case final threadId?)
            Builder(
              builder: (context) {
                final archived = controller.isMessageThreadArchived(threadId);
                return IconButton(
                  tooltip: context.tr(
                    archived ? 'unarchiveConversation' : 'archiveConversation',
                  ),
                  onPressed: () async {
                    await controller.setMessageThreadArchived(
                      threadId,
                      !archived,
                    );
                    if (!context.mounted) return;
                    setState(() {});
                    showPremiumToast(
                      context,
                      context.tr(
                        archived ? 'movedToInbox' : 'conversationArchived',
                      ),
                      icon: archived
                          ? Icons.unarchive_outlined
                          : Icons.archive_outlined,
                    );
                  },
                  icon: Icon(
                    archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                );
              },
            ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: _loading
                  ? const _ConversationSkeleton()
                  : _failed
                  ? _ConversationLoadState(onRetry: _load)
                  : _messages.isEmpty
                  ? EmptyState(
                      title: context.tr('noMessages'),
                      body: context.tr('noMessagesBody'),
                      icon: Icons.waving_hand_outlined,
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(15, 20, 15, 12),
                      itemCount:
                          _messages.length + (_nextOlderPage != null ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (_nextOlderPage != null && index == 0) {
                          return Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: TextButton.icon(
                                key: const ValueKey('loadOlderMessages'),
                                onPressed: _loadingOlder
                                    ? null
                                    : _loadOlderMessages,
                                icon: _loadingOlder
                                    ? SizedBox.square(
                                        dimension: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          semanticsLabel: context.tr('history'),
                                        ),
                                      )
                                    : const Icon(Icons.history_rounded),
                                label: Text(
                                  context.tr(
                                    _olderLoadFailed ? 'tryAgain' : 'history',
                                  ),
                                ),
                              ),
                            ),
                          );
                        }
                        final messageIndex = _nextOlderPage != null
                            ? index - 1
                            : index;
                        final message = _messages[messageIndex];
                        final showDate =
                            messageIndex == 0 ||
                            !_sameDay(
                              _messages[messageIndex - 1].sentAt,
                              message.sentAt,
                            );
                        return Column(
                          children: [
                            if (showDate)
                              Padding(
                                padding: EdgeInsets.only(
                                  top: messageIndex == 0 ? 0 : 12,
                                  bottom: 16,
                                ),
                                child: Center(
                                  child: StatusPill(
                                    label: _dateLabel(message),
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                            _MessageBubble(
                              message: message,
                              showSender: widget.contact.isGroup,
                              onOpenAttachment: () => _openAttachment(message),
                            ),
                          ],
                        );
                      },
                    ),
            ),
            if (controller.canMutate('messaging:write'))
              _Composer(
                key: const ValueKey('composer'),
                controller: _messageController,
                onSend: _sendText,
                onAttach: _showAttachments,
                onRecordStart: _startVoice,
                onRecordEnd: _sendVoice,
                recording: _voiceRecording || _voiceStarting,
              )
            else
              SafeArea(
                top: false,
                minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 13,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.visibility_outlined,
                        size: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Flexible(child: Text(context.tr('readOnlyConversation'))),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ConversationSkeleton extends StatelessWidget {
  const _ConversationSkeleton();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
    child: Column(
      children: List.generate(
        5,
        (index) => Align(
          alignment: index.isEven
              ? Alignment.centerLeft
              : Alignment.centerRight,
          child: Container(
            width: index.isEven ? 190 : 235,
            height: index == 2 ? 76 : 54,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest
                  .withValues(alpha: .68 - index * .06),
              borderRadius: BorderRadius.circular(19),
            ),
          ),
        ),
      ),
    ),
  );
}

class _ConversationLoadState extends StatelessWidget {
  const _ConversationLoadState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.forum_outlined,
            size: 48,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(height: 16),
          Text(
            context.tr('messagesLoadFailed'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            context.tr('messagesLoadFailedBody'),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 18),
          FilledButton.tonalIcon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(context.tr('tryAgain')),
          ),
        ],
      ),
    ),
  );
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.showSender,
    required this.onOpenAttachment,
  });

  final ChatMessage message;
  final bool showSender;
  final VoidCallback onOpenAttachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mine = message.isMine;
    final hasAttachment = message.type != MessageType.text;
    final foreground = mine ? Colors.white : theme.colorScheme.onSurface;
    final content = Container(
      constraints: BoxConstraints(
        maxWidth: math.min(MediaQuery.sizeOf(context).width * .78, 480),
      ),
      margin: const EdgeInsets.only(bottom: 7),
      padding:
          message.type == MessageType.image || message.type == MessageType.video
          ? const EdgeInsets.all(5)
          : const EdgeInsets.fromLTRB(13, 9, 10, 8),
      decoration: BoxDecoration(
        color: mine ? theme.colorScheme.primary : theme.colorScheme.surface,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(19),
          topRight: const Radius.circular(19),
          bottomLeft: Radius.circular(mine ? 19 : 5),
          bottomRight: Radius.circular(mine ? 5 : 19),
        ),
        border: mine
            ? null
            : Border.all(
                color: theme.colorScheme.outlineVariant.withValues(alpha: .42),
              ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showSender && !mine && message.senderName.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(2, 0, 4, 5),
              child: Text(
                message.senderName,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
          _bubbleContent(context, foreground),
        ],
      ),
    );
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: hasAttachment
          ? Semantics(
              button: true,
              label: message.text,
              child: InkWell(
                onTap: onOpenAttachment,
                borderRadius: BorderRadius.circular(19),
                child: content,
              ),
            )
          : content,
    );
  }

  Widget _bubbleContent(BuildContext context, Color foreground) {
    if (message.type == MessageType.voice) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentPlayIcon(
            icon: message.isPending
                ? Icons.cloud_upload_outlined
                : Icons.play_arrow_rounded,
            foreground: foreground,
          ),
          const SizedBox(width: 9),
          _Waveform(color: foreground),
          const SizedBox(width: 7),
          Text(
            message.duration ?? message.time,
            style: TextStyle(
              color: foreground.withValues(alpha: .72),
              fontSize: 11,
            ),
          ),
          _messageStatus(foreground),
        ],
      );
    }
    if (message.type == MessageType.image ||
        message.type == MessageType.video) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: SizedBox(
              height: 158,
              width: 220,
              child:
                  message.type == MessageType.image &&
                      message.attachmentUrl.isNotEmpty
                  ? Image.network(
                      message.attachmentUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => _mediaPlaceholder(context),
                    )
                  : Stack(
                      fit: StackFit.expand,
                      children: [
                        if (message.attachmentUrl.isNotEmpty)
                          ColoredBox(
                            color: Theme.of(context).colorScheme.primary,
                            child: const Icon(
                              Icons.movie_outlined,
                              color: Colors.white30,
                              size: 74,
                            ),
                          )
                        else
                          _mediaPlaceholder(context),
                        if (message.type == MessageType.video)
                          Center(
                            child: _AttachmentPlayIcon(
                              icon: message.isPending
                                  ? Icons.cloud_upload_outlined
                                  : Icons.play_arrow_rounded,
                              foreground: Colors.white,
                              large: true,
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 4, 5, 1),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message.time,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
                _messageStatus(Colors.white),
              ],
            ),
          ),
        ],
      );
    }
    if (message.type == MessageType.file) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _AttachmentPlayIcon(
            icon: message.isPending
                ? Icons.cloud_upload_outlined
                : Icons.insert_drive_file_rounded,
            foreground: foreground,
          ),
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              message.text,
              style: TextStyle(color: foreground, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            message.time,
            style: TextStyle(
              color: foreground.withValues(alpha: .65),
              fontSize: 11,
            ),
          ),
          _messageStatus(foreground),
        ],
      );
    }
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.end,
      alignment: WrapAlignment.end,
      children: [
        Text(message.text, style: TextStyle(color: foreground, height: 1.35)),
        const SizedBox(width: 8),
        Text(
          message.time,
          style: TextStyle(
            color: foreground.withValues(alpha: .65),
            fontSize: 11,
          ),
        ),
        _messageStatus(foreground),
      ],
    );
  }

  Widget _mediaPlaceholder(BuildContext context) => ColoredBox(
    color: Theme.of(context).colorScheme.primary,
    child: const Center(
      child: Icon(Icons.image_rounded, color: Colors.white, size: 42),
    ),
  );

  Widget _messageStatus(Color foreground) {
    if (!message.isMine) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(left: 3),
      child: Icon(
        message.isPending ? Icons.schedule_rounded : Icons.done_rounded,
        size: 13,
        color: foreground.withValues(alpha: .7),
      ),
    );
  }
}

class _AttachmentPlayIcon extends StatelessWidget {
  const _AttachmentPlayIcon({
    required this.icon,
    required this.foreground,
    this.large = false,
  });

  final IconData icon;
  final Color foreground;
  final bool large;

  @override
  Widget build(BuildContext context) => Container(
    width: large ? 52 : 35,
    height: large ? 52 : 35,
    decoration: BoxDecoration(
      color: foreground.withValues(alpha: large ? .22 : .14),
      shape: BoxShape.circle,
      border: large ? Border.all(color: Colors.white54) : null,
    ),
    child: Icon(icon, color: foreground, size: large ? 31 : 22),
  );
}

class _Composer extends StatelessWidget {
  const _Composer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onAttach,
    required this.onRecordStart,
    required this.onRecordEnd,
    required this.recording,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onAttach;
  final VoidCallback onRecordStart;
  final VoidCallback onRecordEnd;
  final bool recording;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(10, 6, 10, 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          IconButton(
            onPressed: onAttach,
            icon: const Icon(Icons.add_circle_outline_rounded),
          ),
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => onSend(),
              enabled: !recording,
              decoration: InputDecoration(
                hintText: context.tr(recording ? 'recording' : 'typeMessage'),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              if (value.text.trim().isNotEmpty) {
                return IconButton.filled(
                  onPressed: onSend,
                  icon: const Icon(Icons.arrow_upward_rounded),
                );
              }
              return GestureDetector(
                onLongPressStart: (_) => onRecordStart(),
                onLongPressEnd: (_) => onRecordEnd(),
                child: Semantics(
                  button: true,
                  liveRegion: recording,
                  label: context.tr(
                    recording ? 'recording' : 'holdToRecordVoice',
                  ),
                  child: Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: recording
                          ? Theme.of(context).colorScheme.errorContainer
                          : Theme.of(context).colorScheme.primaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      recording ? Icons.mic_rounded : Icons.mic_none_rounded,
                      color: recording
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _Waveform extends StatelessWidget {
  const _Waveform({required this.color});
  final Color color;

  @override
  Widget build(BuildContext context) {
    final heights = [
      8.0,
      15.0,
      11.0,
      22.0,
      17.0,
      9.0,
      20.0,
      13.0,
      18.0,
      7.0,
      14.0,
      10.0,
    ];
    return Row(
      children: heights
          .map(
            (height) => Container(
              width: 2,
              height: height,
              margin: const EdgeInsets.symmetric(horizontal: 1.3),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .72),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ImageAttachmentPage extends StatelessWidget {
  const _ImageAttachmentPage({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF111117),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      title: Text(message.text, maxLines: 1, overflow: TextOverflow.ellipsis),
    ),
    body: InteractiveViewer(
      minScale: .7,
      maxScale: 5,
      child: Center(
        child: Image.network(
          message.attachmentUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, progress) => progress == null
              ? child
              : const CircularProgressIndicator(color: Colors.white),
          errorBuilder: (_, _, _) => const Icon(
            Icons.broken_image_outlined,
            color: Colors.white54,
            size: 64,
          ),
        ),
      ),
    ),
  );
}

class _VideoAttachmentPage extends StatefulWidget {
  const _VideoAttachmentPage({required this.message});

  final ChatMessage message;

  @override
  State<_VideoAttachmentPage> createState() => _VideoAttachmentPageState();
}

class _VideoAttachmentPageState extends State<_VideoAttachmentPage> {
  late final VideoPlayerController _player = VideoPlayerController.networkUrl(
    Uri.parse(widget.message.attachmentUrl),
  );
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player
        .initialize()
        .then((_) {
          if (mounted) setState(() {});
        })
        .catchError((_) {
          if (mounted) setState(() => _failed = true);
        });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFF111117),
    appBar: AppBar(
      backgroundColor: Colors.transparent,
      foregroundColor: Colors.white,
      title: Text(
        widget.message.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: Center(
      child: _failed
          ? const Icon(
              Icons.video_file_outlined,
              color: Colors.white54,
              size: 70,
            )
          : !_player.value.isInitialized
          ? const CircularProgressIndicator(color: Colors.white)
          : GestureDetector(
              onTap: () {
                setState(() {
                  _player.value.isPlaying ? _player.pause() : _player.play();
                });
              },
              child: AspectRatio(
                aspectRatio: _player.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_player),
                    if (!_player.value.isPlaying)
                      Container(
                        width: 64,
                        height: 64,
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          color: Colors.white,
                          size: 42,
                        ),
                      ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: VideoProgressIndicator(
                        _player,
                        allowScrubbing: true,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        colors: VideoProgressColors(
                          playedColor: Theme.of(context).colorScheme.primary,
                          bufferedColor: Colors.white30,
                          backgroundColor: Colors.white12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    ),
  );
}

class _AudioAttachmentPage extends StatefulWidget {
  const _AudioAttachmentPage({required this.message});

  final ChatMessage message;

  @override
  State<_AudioAttachmentPage> createState() => _AudioAttachmentPageState();
}

class _AudioAttachmentPageState extends State<_AudioAttachmentPage> {
  final AudioPlayer _player = AudioPlayer();
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _player.setUrl(widget.message.attachmentUrl).catchError((_) {
      if (mounted) setState(() => _failed = true);
      return null;
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  String _duration(Duration value) {
    final total = value.inSeconds.clamp(0, 359999);
    return '${total ~/ 60}:${(total % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.message.text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    ),
    body: MaxWidthBox(
      maxWidth: 620,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: PremiumCard(
            padding: const EdgeInsets.fromLTRB(24, 30, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 112,
                  height: 112,
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.graphic_eq_rounded,
                    color: Colors.white,
                    size: 54,
                  ),
                ),
                const SizedBox(height: 25),
                Text(
                  widget.message.text,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 24),
                if (_failed)
                  Text(context.tr('messageAttachmentFailed'))
                else
                  StreamBuilder<Duration>(
                    stream: _player.positionStream,
                    builder: (context, positionSnapshot) =>
                        StreamBuilder<Duration?>(
                          stream: _player.durationStream,
                          builder: (context, durationSnapshot) {
                            final position =
                                positionSnapshot.data ?? Duration.zero;
                            final duration =
                                durationSnapshot.data ?? Duration.zero;
                            final max = math
                                .max(1, duration.inMilliseconds)
                                .toDouble();
                            return Column(
                              children: [
                                Slider(
                                  value: position.inMilliseconds
                                      .clamp(0, max.toInt())
                                      .toDouble(),
                                  max: max,
                                  onChanged: (value) => _player.seek(
                                    Duration(milliseconds: value.round()),
                                  ),
                                ),
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(_duration(position)),
                                    Text(_duration(duration)),
                                  ],
                                ),
                              ],
                            );
                          },
                        ),
                  ),
                const SizedBox(height: 12),
                StreamBuilder<bool>(
                  stream: _player.playingStream,
                  builder: (context, snapshot) => IconButton.filled(
                    onPressed: _failed
                        ? null
                        : () => snapshot.data == true
                              ? _player.pause()
                              : _player.play(),
                    iconSize: 34,
                    icon: Icon(
                      snapshot.data == true
                          ? Icons.pause_rounded
                          : Icons.play_arrow_rounded,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class _AttachmentAction extends StatelessWidget {
  const _AttachmentAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(7),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: color.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(17),
              ),
              child: Icon(icon, color: color),
            ),
            const SizedBox(height: 7),
            Text(label, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

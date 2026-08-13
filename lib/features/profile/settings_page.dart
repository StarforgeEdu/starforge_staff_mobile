import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../core/legal_links.dart';
import '../../data/remote_models.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  static const _inAppKey = 'settings.inAppNotifications';
  static const _legacyPushKey = 'settings.pushEnabled';
  static const _remindersKey = 'settings.lessonReminders';
  static const _defaultShiftKey = 'settings.defaultShift';
  static const _lessonReminderEvent = 'schedule.lesson_reminder';
  static const _inAppChannel = 'in_app';
  static const _defaultShiftValues = {'morning', 'afternoon', 'fullDay'};

  // Canonical EventType choices supported by the notification service. Lesson
  // reminders have their own switch below and are intentionally excluded here.
  static const _generalNotificationEvents = <String>[
    'attendance.absent',
    'attendance.late',
    'academics.grades_published',
    'assignments.created',
    'assignments.due_soon',
    'assignments.graded',
    'auth.new_device_login',
    'students.enrollment_changed',
    'finance.invoice_issued',
    'finance.payment_reminder',
    'payments.payment_completed',
    'payments.payment_failed',
    'cohorts.announcement',
    'billing.subscription_past_due',
    'billing.subscription_suspended',
    'print.failed',
    'approval.approved',
    'approval.rejected',
    'approval.awaiting_disbursement',
    'approval.disbursed',
    'penalty.escalated',
    'message.received',
    'report.ready',
    'cover.requested',
    'cover.approved',
    'cover.pool_opened',
    'cover.rejected',
  ];

  bool _inAppEnabled = true;
  bool _lessonReminders = true;
  String _defaultShift = 'morning';
  bool _notificationSaveInProgress = false;
  bool _remotePreferencesStarted = false;
  int _notificationMutationVersion = 0;
  late final Future<void> _localSettingsReady;
  late final Future<PackageInfo?> _packageInfo;

  @override
  void initState() {
    super.initState();
    _localSettingsReady = _restoreLocalSettings();
    _packageInfo = _loadPackageInfo();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_remotePreferencesStarted) return;
    _remotePreferencesStarted = true;
    _loadRemoteNotificationPreferences();
  }

  Future<void> _restoreLocalSettings() async {
    final preferences = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _inAppEnabled =
          preferences.getBool(_inAppKey) ??
          preferences.getBool(_legacyPushKey) ??
          true;
      _lessonReminders = preferences.getBool(_remindersKey) ?? true;
      final storedShift = preferences.getString(_defaultShiftKey);
      _defaultShift = _defaultShiftValues.contains(storedShift)
          ? storedShift!
          : 'morning';
    });
  }

  Future<void> _loadRemoteNotificationPreferences() async {
    await _localSettingsReady;
    if (!mounted) return;
    final controller = AppControllerScope.of(context);
    if (!controller.isSignedIn || !controller.can('notifications:read')) {
      return;
    }
    final mutationVersion = _notificationMutationVersion;
    try {
      final preferences = await controller.loadNotificationPreferences();
      final generalEnabled = _generalNotificationEvents.every(
        (eventType) => _effectiveInAppPreference(preferences, eventType),
      );
      final remindersEnabled = _effectiveInAppPreference(
        preferences,
        _lessonReminderEvent,
      );
      if (!mounted || mutationVersion != _notificationMutationVersion) return;
      setState(() {
        _inAppEnabled = generalEnabled;
        _lessonReminders = remindersEnabled;
      });
      await _persistNotificationFallback(
        inAppEnabled: generalEnabled,
        lessonReminders: remindersEnabled,
      );
    } catch (_) {
      // Local values remain a useful offline fallback. A user-initiated change
      // will retry the account preference endpoint and report any failure.
    }
  }

  bool _effectiveInAppPreference(
    List<NotificationPreferenceInfo> preferences,
    String eventType,
  ) {
    for (final preference in preferences.reversed) {
      if (preference.eventType == eventType &&
          preference.channel == _inAppChannel) {
        return preference.enabled;
      }
    }
    // Account notification preferences default to enabled when no override
    // has been saved for an event.
    return true;
  }

  Future<void> _saveInAppNotifications(bool value) async {
    if (_notificationSaveInProgress) return;
    final controller = AppControllerScope.of(context);
    if (!_canEditNotificationPreferences(controller)) return;
    final previous = _inAppEnabled;
    _notificationMutationVersion++;
    setState(() {
      _inAppEnabled = value;
      _notificationSaveInProgress = controller.isSignedIn;
    });
    await _persistNotificationFallback(inAppEnabled: value);
    if (!controller.isSignedIn) return;
    try {
      await controller.updateNotificationPreferences(
        _generalNotificationEvents
            .map(
              (eventType) => NotificationPreferenceInfo(
                eventType: eventType,
                channel: _inAppChannel,
                enabled: value,
              ),
            )
            .toList(growable: false),
      );
    } catch (_) {
      await _persistNotificationFallback(inAppEnabled: previous);
      if (!mounted) return;
      setState(() => _inAppEnabled = previous);
      showPremiumToast(
        context,
        context.tr('changesCouldNotSave'),
        icon: Icons.info_outline_rounded,
        color: AppTheme.coral,
      );
    } finally {
      if (mounted) setState(() => _notificationSaveInProgress = false);
    }
  }

  Future<void> _saveReminders(bool value) async {
    if (_notificationSaveInProgress) return;
    final controller = AppControllerScope.of(context);
    if (!_canEditNotificationPreferences(controller)) return;
    final previous = _lessonReminders;
    _notificationMutationVersion++;
    setState(() {
      _lessonReminders = value;
      _notificationSaveInProgress = controller.isSignedIn;
    });
    await _persistNotificationFallback(lessonReminders: value);
    if (!controller.isSignedIn) return;
    try {
      await controller.updateNotificationPreferences([
        NotificationPreferenceInfo(
          eventType: _lessonReminderEvent,
          channel: _inAppChannel,
          enabled: value,
        ),
      ]);
    } catch (_) {
      await _persistNotificationFallback(lessonReminders: previous);
      if (!mounted) return;
      setState(() => _lessonReminders = previous);
      showPremiumToast(
        context,
        context.tr('changesCouldNotSave'),
        icon: Icons.info_outline_rounded,
        color: AppTheme.coral,
      );
    } finally {
      if (mounted) setState(() => _notificationSaveInProgress = false);
    }
  }

  bool _canEditNotificationPreferences(AppController controller) {
    // An unsigned settings widget exists only in tests; the production page is
    // behind authentication. Keeping local controls available there exercises
    // and preserves the offline fallback without bypassing an account guard.
    if (!controller.isSignedIn) return true;
    return controller.account?.readOnly != true &&
        controller.can('notifications:read');
  }

  Future<void> _persistNotificationFallback({
    bool? inAppEnabled,
    bool? lessonReminders,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    if (inAppEnabled != null) {
      await preferences.setBool(_inAppKey, inAppEnabled);
      await preferences.remove(_legacyPushKey);
    }
    if (lessonReminders != null) {
      await preferences.setBool(_remindersKey, lessonReminders);
    }
  }

  Future<void> _saveDefaultShift(String? value) async {
    if (value == null || !_defaultShiftValues.contains(value)) return;
    final previous = _defaultShift;
    setState(() => _defaultShift = value);
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(_defaultShiftKey, value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _defaultShift = previous);
      showPremiumToast(
        context,
        context.tr('changesCouldNotSave'),
        icon: Icons.info_outline_rounded,
        color: AppTheme.coral,
      );
    }
  }

  Future<PackageInfo?> _loadPackageInfo() async {
    try {
      return await PackageInfo.fromPlatform();
    } catch (_) {
      return null;
    }
  }

  void _changePassword() {
    final currentController = TextEditingController();
    final nextController = TextEditingController();
    var showCurrentPassword = false;
    var showNewPassword = false;
    var savingPassword = false;
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            24,
            2,
            24,
            24 + MediaQuery.viewInsetsOf(sheetContext).bottom,
          ),
          child: AutofillGroup(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  context.tr('changePassword'),
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: currentController,
                  enabled: !savingPassword,
                  obscureText: !showCurrentPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.password],
                  decoration: InputDecoration(
                    labelText: context.tr('currentPassword'),
                    prefixIcon: const Icon(Icons.lock_outline_rounded),
                    suffixIcon: IconButton(
                      tooltip: context.tr(
                        showCurrentPassword ? 'hidePassword' : 'showPassword',
                      ),
                      onPressed: savingPassword
                          ? null
                          : () => setSheetState(
                              () => showCurrentPassword = !showCurrentPassword,
                            ),
                      icon: Icon(
                        showCurrentPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nextController,
                  enabled: !savingPassword,
                  obscureText: !showNewPassword,
                  autocorrect: false,
                  enableSuggestions: false,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    labelText: context.tr('newPassword'),
                    prefixIcon: const Icon(Icons.password_rounded),
                    suffixIcon: IconButton(
                      tooltip: context.tr(
                        showNewPassword ? 'hidePassword' : 'showPassword',
                      ),
                      onPressed: savingPassword
                          ? null
                          : () => setSheetState(
                              () => showNewPassword = !showNewPassword,
                            ),
                      icon: Icon(
                        showNewPassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: savingPassword
                        ? null
                        : () async {
                            final successMessage = context.tr(
                              'passwordUpdated',
                            );
                            final failureMessage = context.tr(
                              'passwordUpdateFailed',
                            );
                            if (nextController.text.length < 10) {
                              showPremiumToast(
                                context,
                                context.tr('passwordRules'),
                                icon: Icons.info_outline_rounded,
                                color: AppTheme.coral,
                              );
                              return;
                            }
                            setSheetState(() => savingPassword = true);
                            final saved = await AppControllerScope.of(context)
                                .completeRequiredPasswordChange(
                                  currentPassword: currentController.text,
                                  newPassword: nextController.text,
                                );
                            if (!mounted || !sheetContext.mounted) return;
                            if (saved) {
                              Navigator.pop(sheetContext);
                              showPremiumToast(
                                context,
                                successMessage,
                                icon: Icons.lock_outline_rounded,
                              );
                            } else {
                              setSheetState(() => savingPassword = false);
                              showPremiumToast(
                                context,
                                failureMessage,
                                icon: Icons.info_outline_rounded,
                                color: AppTheme.coral,
                              );
                            }
                          },
                    child: savingPassword
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(context.tr('save')),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ).whenComplete(() {
      currentController.dispose();
      nextController.dispose();
    });
  }

  void _privacy() {
    final privacyUri = configuredPrivacyPolicyUri;
    showAppSheet<void>(
      context: context,
      builder: (context) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          2,
          24,
          30 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const StarforgeMark(),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    context.tr('privacyPolicy'),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 22),
            Text(
              context.tr('termsBody'),
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(height: 1.55),
            ),
            const SizedBox(height: 18),
            _PrivacyPoint(
              icon: Icons.visibility_outlined,
              title: context.tr('privacyRoleVisibility'),
              body: context.tr('privacyRoleVisibilityBody'),
            ),
            _PrivacyPoint(
              icon: Icons.shield_outlined,
              title: context.tr('privacyProtectedContent'),
              body: context.tr('privacyProtectedContentBody'),
            ),
            _PrivacyPoint(
              icon: Icons.manage_history_rounded,
              title: context.tr('privacyAccountability'),
              body: context.tr('privacyAccountabilityBody'),
            ),
            if (privacyUri != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final opened = await launchUrl(
                      privacyUri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && context.mounted) {
                      showPremiumToast(
                        context,
                        context.tr('policyOpenFailed'),
                        icon: Icons.info_outline_rounded,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(context.tr('viewFullPolicy')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _signOut() async {
    final shouldSignOut = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.logout_rounded),
        title: Text(context.tr('signOut')),
        content: Text(context.tr('signOutConfirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.tr('cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.tr('confirm')),
          ),
        ],
      ),
    );
    if (shouldSignOut == true && mounted) {
      AppControllerScope.of(context).signOut();
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final canEditNotifications = _canEditNotificationPreferences(controller);
    final compactHeader =
        MediaQuery.sizeOf(context).width < 360 ||
        MediaQuery.textScalerOf(context).scale(1) >= 1.45;
    return Scaffold(
      appBar: AppBar(
        title: Text(context.tr('settings')),
        actions: compactHeader
            ? null
            : const [
                Padding(
                  padding: EdgeInsetsDirectional.only(end: 18),
                  child: StarforgeMark(size: 34),
                ),
              ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          physics: const BouncingScrollPhysics(),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.only(bottom: 34),
          children: [
            MaxWidthBox(
              maxWidth: 760,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _SettingsTitle(
                    title: context.tr('appearance'),
                    icon: Icons.auto_awesome_outlined,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  PremiumCard(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 17),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.contrast_rounded, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                context.tr('theme'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _ThemeModePicker(
                          value: controller.themeMode,
                          onChanged: controller.setThemeMode,
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Divider(),
                        ),
                        Row(
                          children: [
                            const Icon(Icons.palette_outlined, size: 20),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                context.tr('accentColor'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _AccentPicker(
                          value: controller.accent,
                          onChanged: controller.setAccent,
                        ),
                      ],
                    ),
                  ),
                  _SettingsTitle(
                    title: context.tr('language'),
                    icon: Icons.translate_rounded,
                    color: const Color(0xFF4D73B7),
                  ),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: RadioGroup<String>(
                      groupValue: controller.locale.languageCode,
                      onChanged: (value) {
                        if (value != null) controller.setLocale(Locale(value));
                      },
                      child: const Column(
                        children: [
                          RadioListTile(
                            value: 'uz',
                            title: Text('O‘zbekcha'),
                            secondary: Text('UZ'),
                          ),
                          Divider(indent: 52),
                          RadioListTile(
                            value: 'en',
                            title: Text('English'),
                            secondary: Text('EN'),
                          ),
                          Divider(indent: 52),
                          RadioListTile(
                            value: 'ru',
                            title: Text('Русский'),
                            secondary: Text('RU'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _SettingsTitle(
                    title: context.tr('defaultShift'),
                    icon: Icons.work_history_outlined,
                    color: AppTheme.gold,
                  ),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: RadioGroup<String>(
                      groupValue: _defaultShift,
                      onChanged: _saveDefaultShift,
                      child: Column(
                        children: [
                          RadioListTile<String>(
                            value: 'morning',
                            title: Text(context.tr('morningShift')),
                            secondary: const Icon(Icons.wb_sunny_outlined),
                          ),
                          const Divider(indent: 52),
                          RadioListTile<String>(
                            value: 'afternoon',
                            title: Text(context.tr('afternoonShift')),
                            secondary: const Icon(Icons.light_mode_outlined),
                          ),
                          const Divider(indent: 52),
                          RadioListTile<String>(
                            value: 'fullDay',
                            title: Text(context.tr('fullDayShift')),
                            secondary: const Icon(Icons.today_outlined),
                          ),
                        ],
                      ),
                    ),
                  ),
                  _SettingsTitle(
                    title: context.tr('notifications'),
                    icon: Icons.notifications_none_rounded,
                    color: AppTheme.coral,
                  ),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        if (_notificationSaveInProgress)
                          const LinearProgressIndicator(minHeight: 2),
                        SwitchListTile.adaptive(
                          secondary: const Icon(
                            Icons.notifications_active_outlined,
                          ),
                          title: Text(context.tr('notifications')),
                          subtitle: Text(
                            context.tr(
                              canEditNotifications
                                  ? 'notificationsEmptyBody'
                                  : 'actionUnavailable',
                            ),
                          ),
                          value: _inAppEnabled,
                          onChanged:
                              canEditNotifications &&
                                  !_notificationSaveInProgress
                              ? _saveInAppNotifications
                              : null,
                        ),
                        const Divider(indent: 52),
                        SwitchListTile.adaptive(
                          secondary: const Icon(Icons.schedule_rounded),
                          title: Text(context.tr('lessonReminders')),
                          subtitle: canEditNotifications
                              ? null
                              : Text(context.tr('actionUnavailable')),
                          value: _lessonReminders,
                          onChanged:
                              canEditNotifications &&
                                  !_notificationSaveInProgress
                              ? _saveReminders
                              : null,
                        ),
                      ],
                    ),
                  ),
                  _SettingsTitle(
                    title: context.tr('security'),
                    icon: Icons.shield_outlined,
                    color: const Color(0xFF2D9079),
                  ),
                  PremiumCard(
                    padding: EdgeInsets.zero,
                    child: Column(
                      children: [
                        ListTile(
                          leading: const Icon(Icons.password_rounded),
                          title: Text(context.tr('changePassword')),
                          subtitle: controller.account?.readOnly == true
                              ? Text(context.tr('actionUnavailable'))
                              : null,
                          trailing: controller.account?.readOnly == true
                              ? null
                              : const Icon(Icons.chevron_right_rounded),
                          onTap: controller.account?.readOnly == true
                              ? null
                              : _changePassword,
                        ),
                        const Divider(indent: 52),
                        ListTile(
                          leading: const Icon(Icons.shield_outlined),
                          title: Text(context.tr('privacyPolicy')),
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: _privacy,
                        ),
                      ],
                    ),
                  ),
                  _SettingsTitle(
                    title: context.tr('about'),
                    icon: Icons.info_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  PremiumCard(
                    padding: const EdgeInsets.all(18),
                    color: Theme.of(
                      context,
                    ).colorScheme.primaryContainer.withValues(alpha: .28),
                    child: Row(
                      children: [
                        const StarforgeMark(),
                        const SizedBox(width: 13),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Starforge Staff',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              const SizedBox(height: 3),
                              FutureBuilder<PackageInfo?>(
                                future: _packageInfo,
                                builder: (context, snapshot) {
                                  final info = snapshot.data;
                                  final value = info == null
                                      ? '—'
                                      : '${info.version} (${info.buildNumber})';
                                  return Text(
                                    context.l10n.format('versionValue', {
                                      'version': value,
                                    }),
                                    style: Theme.of(
                                      context,
                                    ).textTheme.bodySmall,
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.coral,
                      ),
                      onPressed: _signOut,
                      icon: const Icon(Icons.logout_rounded),
                      label: Text(context.tr('signOut')),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThemeModePicker extends StatelessWidget {
  const _ThemeModePicker({required this.value, required this.onChanged});

  final ThemeMode value;
  final ValueChanged<ThemeMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final options = <(ThemeMode, String, IconData)>[
      (ThemeMode.system, context.tr('system'), Icons.brightness_auto_outlined),
      (ThemeMode.light, context.tr('light'), Icons.light_mode_outlined),
      (ThemeMode.dark, context.tr('dark'), Icons.dark_mode_outlined),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = scale >= 1.45 || constraints.maxWidth < 290 ? 1 : 3;
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: options
              .map(
                (option) => SizedBox(
                  width: width,
                  child: _SettingsChoice(
                    label: option.$2,
                    icon: option.$3,
                    selected: value == option.$1,
                    onTap: () => onChanged(option.$1),
                    vertical: columns > 1,
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _AccentPicker extends StatelessWidget {
  const _AccentPicker({required this.value, required this.onChanged});

  final AccentChoice value;
  final ValueChanged<AccentChoice> onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final columns = scale >= 1.6 || constraints.maxWidth < 250 ? 1 : 2;
        final width = (constraints.maxWidth - 8 * (columns - 1)) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: AccentChoice.values
              .map(
                (accent) => SizedBox(
                  width: width,
                  child: _SettingsChoice(
                    label: context.tr('accent${accent.name}'),
                    color: accent.color,
                    selected: value == accent,
                    semanticLabel: context.l10n.format('accentOption', {
                      'color': context.tr('accent${accent.name}'),
                    }),
                    onTap: () => onChanged(accent),
                  ),
                ),
              )
              .toList(growable: false),
        );
      },
    );
  }
}

class _SettingsChoice extends StatelessWidget {
  const _SettingsChoice({
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
    this.color,
    this.semanticLabel,
    this.vertical = false,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;
  final Color? color;
  final String? semanticLabel;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final indicator = color == null
        ? Icon(
            icon,
            size: 21,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          )
        : Container(
            width: 22,
            height: 22,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            child: selected
                ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
                : null,
          );
    final labelWidget = Text(
      label,
      textAlign: vertical ? TextAlign.center : TextAlign.start,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: selected ? scheme.primary : scheme.onSurface,
      ),
    );
    return Semantics(
      button: true,
      selected: selected,
      label: semanticLabel ?? label,
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: selected
            ? scheme.primaryContainer.withValues(alpha: .65)
            : scheme.surfaceContainerHighest.withValues(alpha: .45),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: selected
                ? scheme.primary.withValues(alpha: .5)
                : scheme.outlineVariant.withValues(alpha: .38),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 54),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: vertical
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        indicator,
                        const SizedBox(height: 6),
                        labelWidget,
                      ],
                    )
                  : Row(
                      children: [
                        indicator,
                        const SizedBox(width: 9),
                        Expanded(child: labelWidget),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsTitle extends StatelessWidget {
  const _SettingsTitle({
    required this.title,
    required this.icon,
    required this.color,
  });

  final String title;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 25, 2, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
        ],
      ),
    );
  }
}

class _PrivacyPoint extends StatelessWidget {
  const _PrivacyPoint({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              icon,
              color: Theme.of(context).colorScheme.primary,
              size: 19,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(body, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

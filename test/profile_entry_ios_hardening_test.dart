import 'dart:io';
import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/app.dart';
import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/features/profile/employment_pages.dart';
import 'package:starforge_staff/features/profile/profile_page.dart';
import 'package:starforge_staff/features/shell/app_shell.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('loaded profile and name editor fit narrow Russian at 200%', (
    tester,
  ) async {
    _setViewport(tester, const Size(320, 568));
    final semantics = tester.ensureSemantics();
    final gateway = _ProfileGateway();
    final controller = await _signedInController(gateway, const Locale('ru'));
    await controller.loadGroups();
    gateway.lastProfileChanges = null;

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('ru'),
        child: const ProfilePage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final russian = AppLocalizations(const Locale('ru'));
    final editButton = find.byTooltip(russian.tr('editProfile'));
    expect(editButton, findsOneWidget);
    expect(tester.getSize(editButton).shortestSide, greaterThanOrEqualTo(48));
    expect(
      tester
          .getSemantics(editButton)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.ensureVisible(editButton);
    await tester.pumpAndSettle();
    await tester.tap(editButton);
    await tester.pumpAndSettle();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(3));
    expect(fields[0].controller?.text, 'Zarina');
    expect(fields[1].controller?.text, 'Otabekovna');
    expect(fields[2].controller?.text, 'Rustamova');
    expect(fields[0].autofillHints, contains(AutofillHints.givenName));
    expect(fields[1].autofillHints, contains(AutofillHints.middleName));
    expect(fields[2].autofillHints, contains(AutofillHints.familyName));

    final save = find.widgetWithText(FilledButton, russian.tr('save'));
    await tester.enterText(find.byType(TextField).first, '   ');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pump();
    expect(find.byType(TextField), findsNWidgets(3));
    expect(gateway.lastProfileChanges, isNull);
    final failedToast = find.bySemanticsLabel(
      russian.tr('changesCouldNotSave'),
    );
    expect(failedToast, findsOneWidget);
    await tester.tap(failedToast);
    await tester.pump();

    await tester.enterText(find.byType(TextField).at(0), '  Zebo   ');
    await tester.enterText(find.byType(TextField).at(1), '  Anvarovna  ');
    await tester.enterText(find.byType(TextField).at(2), '  Karimova  ');
    await tester.ensureVisible(save);
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(gateway.lastProfileChanges, {
      'first_name': 'Zebo',
      'middle_name': 'Anvarovna',
      'last_name': 'Karimova',
    });
    expect(controller.displayName, 'Zebo Anvarovna Karimova');
    final savedToast = find.bySemanticsLabel(russian.tr('changesSaved'));
    expect(savedToast, findsOneWidget);
    await tester.tap(savedToast);
    await tester.pump();
    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, 1800),
      1300,
    );
    await tester.pumpAndSettle();
    expect(find.text('Zebo Anvarovna Karimova'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.fling(
      find.byType(CustomScrollView),
      const Offset(0, -1700),
      1300,
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('loaded payslips fit Uzbek landscape at 200% text', (
    tester,
  ) async {
    _setViewport(tester, const Size(844, 390));
    final gateway = _ProfileGateway();
    final controller = await _signedInController(gateway, const Locale('uz'));

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('uz'),
        child: const SalaryHistoryPage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(gateway.payslipRequests, 1);
    expect(
      find.text(
        AppLocalizations(const Locale('uz')).tr('salaryCurrent').toUpperCase(),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);

    for (var index = 0; index < 5; index++) {
      await tester.fling(find.byType(ListView), const Offset(0, -900), 1200);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets('app entry switches directly when animations are disabled', (
    tester,
  ) async {
    tester.binding.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(
      tester.binding.platformDispatcher.clearAccessibilityFeaturesTestValue,
    );
    final gateway = _ProfileGateway();
    final controller = await AppController.load(
      gateway: gateway,
      restoreSession: false,
    );

    await tester.pumpWidget(StarforgeApp(controller: controller));
    await tester.pump();
    final login = find.byKey(const ValueKey('login'));
    expect(login, findsOneWidget);
    expect(
      find.ancestor(of: login, matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );

    expect(
      await controller.signIn(
        username: 'teacher.zarina',
        password: 'valid-password',
      ),
      AuthResult.success,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 20));

    final shell = find.byKey(const ValueKey('shell'));
    expect(shell, findsOneWidget);
    expect(find.byType(AppShell), findsOneWidget);
    expect(
      find.ancestor(of: shell, matching: find.byType(AnimatedSwitcher)),
      findsNothing,
    );
    expect(tester.takeException(), isNull);
  });

  test('profile production sources do not embed sensitive sample data', () {
    const paths = [
      'lib/app.dart',
      'lib/features/profile/profile_page.dart',
      'lib/features/profile/employment_pages.dart',
      'lib/features/profile/settings_page.dart',
    ];
    final phone = RegExp(r'\+998[\s\d()-]{7,}');
    final email = RegExp(
      r'[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}',
      caseSensitive: false,
    );
    final credentialLiteral = RegExp(
      r'''(?:password|token|secret|api[_-]?key)\s*[:=]\s*['"][^'"]+['"]''',
      caseSensitive: false,
    );
    const sampleIdentities = ['aziza karimova', 'madina akramova'];

    for (final path in paths) {
      final source = File(path).readAsStringSync();
      final lower = source.toLowerCase();
      expect(lower, isNot(contains('demo_data.dart')), reason: path);
      expect(phone.hasMatch(source), isFalse, reason: path);
      expect(email.hasMatch(source), isFalse, reason: path);
      expect(credentialLiteral.hasMatch(source), isFalse, reason: path);
      for (final identity in sampleIdentities) {
        expect(lower, isNot(contains(identity)), reason: path);
      }
    }
  });

  test('iOS permission localizations are complete and referenced by Xcode', () {
    const permissionKeys = {
      'NSCameraUsageDescription',
      'NSMicrophoneUsageDescription',
      'NSPhotoLibraryUsageDescription',
    };
    final infoPlist = File('ios/Runner/Info.plist').readAsStringSync();
    final localizationBlock = RegExp(
      r'<key>CFBundleLocalizations</key>\s*<array>(.*?)</array>',
      dotAll: true,
    ).firstMatch(infoPlist)?.group(1);
    expect(localizationBlock, isNotNull);
    for (final locale in const ['en', 'ru', 'uz']) {
      expect(localizationBlock, contains('<string>$locale</string>'));
    }
    for (final key in permissionKeys) {
      expect(infoPlist, contains('<key>$key</key>'));
    }

    final localized = <String, Map<String, String>>{};
    for (final locale in const ['en', 'ru', 'uz']) {
      final file = File('ios/Runner/$locale.lproj/InfoPlist.strings');
      expect(file.existsSync(), isTrue, reason: locale);
      final values = _parseInfoPlistStrings(file.readAsStringSync());
      localized[locale] = values;
      expect(values.keys, containsAll(permissionKeys), reason: locale);
      expect(values['CFBundleDisplayName'], 'Starforge Staff');
      for (final key in permissionKeys) {
        expect(values[key], isNotNull);
        expect(values[key]!.trim(), isNotEmpty);
        expect(values[key], contains('Starforge Staff'));
      }
    }
    for (final key in permissionKeys) {
      expect(localized['ru']![key], isNot(localized['en']![key]));
      expect(localized['uz']![key], isNot(localized['en']![key]));
    }

    final project = File(
      'ios/Runner.xcodeproj/project.pbxproj',
    ).readAsStringSync();
    final knownRegions = RegExp(
      r'knownRegions = \((.*?)\);',
      dotAll: true,
    ).firstMatch(project)?.group(1);
    expect(knownRegions, isNotNull);
    for (final locale in const ['en', 'ru', 'uz']) {
      expect(knownRegions, contains(locale));
      expect(project, contains('$locale.lproj/InfoPlist.strings'));
    }
    final variant = RegExp(
      r'/\* InfoPlist\.strings \*/ = \{\s*isa = PBXVariantGroup;(.*?)name = InfoPlist\.strings;',
      dotAll: true,
    ).firstMatch(project)?.group(1);
    expect(variant, isNotNull);
    for (final locale in const ['en', 'ru', 'uz']) {
      expect(variant, contains('/* $locale */'));
    }
    final resources = RegExp(
      r'97C146EC1CF9000F007C117D /\* Resources \*/ = \{(.*?)\n\s*\};',
      dotAll: true,
    ).firstMatch(project)?.group(1);
    expect(resources, contains('InfoPlist.strings in Resources'));
  });
}

Map<String, String> _parseInfoPlistStrings(String source) => {
  for (final match in RegExp(
    r'^"([^"]+)"\s*=\s*"([^"]+)";$',
    multiLine: true,
  ).allMatches(source))
    match.group(1)!: match.group(2)!,
};

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<AppController> _signedInController(
  _ProfileGateway gateway,
  Locale locale,
) async {
  final controller = await AppController.load(
    gateway: gateway,
    restoreSession: false,
  );
  expect(
    await controller.signIn(
      username: 'teacher.zarina',
      password: 'valid-password',
    ),
    AuthResult.success,
  );
  await controller.setLocale(locale);
  return controller;
}

Widget _harness({
  required AppController controller,
  required Locale locale,
  required Widget child,
}) => AppControllerScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light(controller.accent),
    locale: locale,
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
    home: child,
  ),
);

class _ProfileGateway implements StarforgeGateway {
  StaffAccount _account = _baseAccount;
  Map<String, Object?>? lastProfileChanges;
  int payslipRequests = 0;

  @override
  Future<LoginSession> login(String username, String password) async =>
      const LoginSession(
        access: 'profile-hardening-session',
        principalKind: 'teacher',
        mustChangePassword: false,
      );

  @override
  Future<StaffAccount> currentAccount() async => _account;

  @override
  Future<StaffAccount> updateProfile(Map<String, Object?> changes) async {
    lastProfileChanges = Map.unmodifiable(changes);
    final first = (changes['first_name'] as String?) ?? _account.firstName;
    final middle = (changes['middle_name'] as String?) ?? _account.middleName;
    final last = (changes['last_name'] as String?) ?? _account.lastName;
    _account = StaffAccount(
      id: _account.id,
      principalKind: _account.principalKind,
      username: _account.username,
      fullName: [
        first,
        middle,
        last,
      ].where((part) => part.isNotEmpty).join(' '),
      firstName: first,
      middleName: middle,
      lastName: last,
      phone: _account.phone,
      email: _account.email,
      preferredLanguage:
          (changes['preferred_language'] as String?) ??
          _account.preferredLanguage,
      mustChangePassword: false,
      memberships: _account.memberships,
      permissions: _account.permissions,
      readOnly: false,
    );
    return _account;
  }

  @override
  Future<List<LearningGroup>> groups() async => List.generate(
    24,
    (index) => LearningGroup(
      id: '${index + 1}',
      remoteId: index + 1,
      name: 'Advanced conversation group ${index + 1}',
      course: 'English',
      level: 'Upper intermediate',
      studyMonth: 4,
      schedule: 'Monday · Wednesday · Friday',
      room: 'A-${index + 1}',
      branch: 'Chilonzor',
      department: 'English',
      mainTeacher: _account.fullName,
      progress: .5,
      attendance: .9,
      nextLesson: 'Tomorrow',
      students: const [],
      primaryTeacherId: _account.id,
      teacherIds: [_account.id],
    ),
  );

  @override
  Future<List<PayrollPayslipInfo>> ownPayslips() async {
    payslipRequests++;
    return List.generate(
      36,
      (index) => PayrollPayslipInfo(
        id: index + 1,
        documentNumber: 'PAY-2026-${1000 + index}',
        periodStatus: index % 3 == 0 ? 'paid' : 'pending',
        branchName: 'Chilonzor central education branch',
        departmentName: 'English language department',
        periodLabel: '2026 August payroll period ${index + 1}',
        periodStart: DateTime(2026, 8, 1),
        periodEnd: DateTime(2026, 8, 31),
        payDate: DateTime(2026, 9, 5),
        currency: 'UZS',
        baseAmount: 987654321,
        bonusAmount: 12345678,
        deductionAmount: 2345678,
        netAmount: 997654321,
        generatedAt: DateTime(2026, 9, 2),
      ),
    );
  }

  @override
  Future<TeacherDashboardData> teacherDashboard() async =>
      const TeacherDashboardData(
        groupsCount: 24,
        studentsCount: 0,
        nextLessons: [],
        nextMeeting: {},
      );

  @override
  Future<List<NotificationInfo>> notifications() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _baseAccount = StaffAccount(
  id: 17,
  principalKind: 'teacher',
  username: 'teacher.zarina',
  fullName: 'Zarina Otabekovna Rustamova',
  firstName: 'Zarina',
  middleName: 'Otabekovna',
  lastName: 'Rustamova',
  phone: '',
  email: '',
  preferredLanguage: 'uz',
  mustChangePassword: false,
  memberships: [
    RoleMembership(
      id: 1,
      name: 'Teacher',
      slug: 'teacher',
      kind: 'teacher',
      branchName: 'Chilonzor central education branch',
      departmentName: 'English language department',
      branchId: 1,
      departmentId: 2,
    ),
  ],
  permissions: {'cohorts:read', 'payroll:read'},
  readOnly: false,
);

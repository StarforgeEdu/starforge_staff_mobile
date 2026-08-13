import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/data/models.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/features/profile/profile_page.dart';
import 'package:starforge_staff/features/profile/settings_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Uzbek settings stay usable in landscape at 200 percent text', (
    tester,
  ) async {
    _setViewport(tester, const Size(844, 390));
    final semantics = tester.ensureSemantics();
    final controller = await AppController.load(restoreSession: false);
    const locale = Locale('uz');
    final translations = AppLocalizations(locale);

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: locale,
        textScaler: const TextScaler.linear(2),
        child: const SettingsPage(),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final dark = find.bySemanticsLabel(translations.tr('dark'));
    expect(dark, findsOneWidget);
    expect(tester.getSize(dark).height, greaterThanOrEqualTo(54));
    expect(
      tester
          .getSemantics(dark)
          .getSemanticsData()
          .hasAction(SemanticsAction.tap),
      isTrue,
    );
    await tester.tap(dark);
    await tester.pump();
    expect(controller.themeMode, ThemeMode.dark);

    final ocean = find.bySemanticsLabel(
      translations.format('accentOption', {
        'color': translations.tr('accentocean'),
      }),
    );
    await tester.ensureVisible(ocean);
    await tester.pumpAndSettle();
    await tester.tap(ocean);
    await tester.pump();
    expect(controller.accent, AccentChoice.ocean);
    expect(tester.takeException(), isNull);

    final afternoon = find.text(translations.tr('afternoonShift'));
    await tester.ensureVisible(afternoon);
    await tester.pumpAndSettle();
    await tester.tap(afternoon);
    await tester.pump();
    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('settings.defaultShift'), 'afternoon');
    expect(tester.takeException(), isNull);

    for (var index = 0; index < 7; index++) {
      await tester.fling(find.byType(ListView), const Offset(0, -800), 1000);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    expect(find.text(translations.tr('signOut')), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('profile exposes only working actions and opens settings', (
    tester,
  ) async {
    _setViewport(tester, const Size(390, 844));
    final gateway = _ProfileActionsGateway();
    final controller = await AppController.load(
      gateway: gateway,
      restoreSession: false,
    );
    expect(
      await controller.signIn(username: 'staff', password: 'safe-password'),
      AuthResult.success,
    );

    await tester.pumpWidget(
      _harness(
        controller: controller,
        locale: const Locale('en'),
        child: const ProfilePage(),
      ),
    );
    await tester.pumpAndSettle();

    expect(gateway.groupRequests, 1);
    expect(find.text('Library'), findsNothing);
    expect(find.text('Print center'), findsNothing);
    expect(find.text('Education center rules'), findsOneWidget);
    final settings = find.byTooltip('Open settings');
    expect(settings, findsOneWidget);
    expect(tester.getSize(settings).shortestSide, greaterThanOrEqualTo(48));
    await tester.tap(settings);
    await tester.pumpAndSettle();

    expect(find.byType(SettingsPage), findsOneWidget);
    expect(tester.takeException(), isNull);

    final changePassword = find.widgetWithText(ListTile, 'Change password');
    await tester.ensureVisible(changePassword);
    await tester.pumpAndSettle();
    await tester.tap(changePassword);
    await tester.pumpAndSettle();
    final passwordFields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList(growable: false);
    expect(passwordFields, hasLength(2));
    expect(
      passwordFields.first.autofillHints,
      contains(AutofillHints.password),
    );
    expect(
      passwordFields.last.autofillHints,
      contains(AutofillHints.newPassword),
    );
    Navigator.of(tester.element(find.byType(TextField).first)).pop();
    await tester.pumpAndSettle();

    final privacy = find.widgetWithText(ListTile, 'Privacy policy');
    await tester.ensureVisible(privacy);
    await tester.pumpAndSettle();
    await tester.tap(privacy);
    await tester.pumpAndSettle();
    expect(find.text('Role-based visibility'), findsOneWidget);
    expect(find.text('Protected learning content'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

void _setViewport(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Widget _harness({
  required AppController controller,
  required Locale locale,
  required Widget child,
  TextScaler textScaler = TextScaler.noScaling,
}) => AppControllerScope(
  controller: controller,
  child: MaterialApp(
    theme: AppTheme.light(controller.accent),
    darkTheme: AppTheme.dark(controller.accent),
    locale: locale,
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(disableAnimations: true, textScaler: textScaler),
      child: child!,
    ),
    home: child,
  ),
);

class _ProfileActionsGateway implements StarforgeGateway {
  int groupRequests = 0;

  @override
  Future<LoginSession> login(String username, String password) async =>
      const LoginSession(
        access: 'profile-actions-session',
        principalKind: 'teacher',
        mustChangePassword: false,
      );

  @override
  Future<StaffAccount> currentAccount() async => _account;

  @override
  Future<List<LearningGroup>> groups() async {
    groupRequests++;
    return const [
      LearningGroup(
        id: '1',
        remoteId: 1,
        name: 'Conversation',
        course: 'English',
        level: 'Intermediate',
        studyMonth: 2,
        schedule: 'Mon · Wed · Fri',
        room: 'A-1',
        branch: 'Central',
        department: 'Languages',
        mainTeacher: 'Staff Member',
        progress: .4,
        attendance: .9,
        nextLesson: '',
        students: [],
        primaryTeacherId: 7,
        teacherIds: [7],
      ),
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError(invocation.memberName.toString());
}

const _account = StaffAccount(
  id: 7,
  principalKind: 'teacher',
  username: 'staff',
  fullName: 'Staff Member',
  firstName: 'Staff',
  lastName: 'Member',
  phone: '',
  email: '',
  preferredLanguage: 'en',
  mustChangePassword: false,
  memberships: [
    RoleMembership(
      id: 1,
      name: 'Teacher',
      slug: 'teacher',
      kind: 'teacher',
      branchName: 'Central',
      departmentName: 'Languages',
      branchId: 1,
      departmentId: 2,
    ),
  ],
  permissions: {'cohorts:read', 'attendance:read'},
  readOnly: false,
);

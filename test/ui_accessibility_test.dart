import 'dart:ui' show SemanticsAction;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/core/app_widgets.dart';
import 'package:starforge_staff/features/auth/login_page.dart';
import 'package:starforge_staff/features/profile/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('new UI copy is complete in every supported language', () {
    const keys = [
      'usernameRequired',
      'passwordTooShort',
      'showPassword',
      'hidePassword',
      'afternoonShift',
      'fullDayShift',
      'lessonReminders',
      'privacyRoleVisibility',
      'privacyProtectedContent',
      'privacyAccountability',
      'salaryCurrent',
      'noPayslips',
      'rulesRequired',
      'contractUnavailable',
      'markAllRead',
      'notificationsEmpty',
      'notificationsLoadFailed',
      'search',
      'clear',
      'noItems',
    ];

    for (final locale in AppLocalizations.supportedLocales) {
      final localizations = AppLocalizations(locale);
      for (final key in keys) {
        expect(
          localizations.tr(key),
          isNot(key),
          reason: '$key is missing for ${locale.languageCode}',
        );
      }
    }
  });

  testWidgets('compact login remains usable and validates fields separately', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final controller = await AppController.load(restoreSession: false);
    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: const LoginPage(),
        disableAnimations: true,
        textScaler: const TextScaler.linear(1.4),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Til'), findsOneWidget);
    expect(find.byTooltip('Parolni ko‘rsatish'), findsOneWidget);
    final systemUiRegions = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byWidgetPredicate(
            (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
          ),
        );
    expect(
      systemUiRegions.any(
        (region) => region.value.statusBarIconBrightness == Brightness.light,
      ),
      isTrue,
    );

    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(fields.first.autofillHints, contains(AutofillHints.username));
    expect(fields.last.autofillHints, contains(AutofillHints.password));

    final button = find.byKey(const ValueKey('loginButton'));
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    expect(find.text('Foydalanuvchi nomini kiriting.'), findsOneWidget);
    expect(find.text('Parolni kiriting.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('login remains operable in landscape at 200% text scale', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(844, 390);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final semantics = tester.ensureSemantics();

    final controller = await AppController.load(restoreSession: false);
    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: const LoginPage(),
        disableAnimations: true,
        textScaler: const TextScaler.linear(2),
      ),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('usernameField')), findsOneWidget);
    expect(find.byKey(const ValueKey('passwordField')), findsOneWidget);
    final loginButton = find.byKey(const ValueKey('loginButton'));
    await tester.ensureVisible(loginButton);
    await tester.pump();

    expect(tester.getSize(loginButton).height, greaterThanOrEqualTo(48));
    final interactiveSurface = find.descendant(
      of: loginButton,
      matching: find.byType(InkWell),
    );
    expect(interactiveSurface, findsOneWidget);
    final loginSemantics = tester.getSemantics(interactiveSurface);
    expect(
      loginSemantics.getSemanticsData().hasAction(SemanticsAction.tap),
      isTrue,
    );
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('required password visibility is controlled per field', (
    tester,
  ) async {
    final controller = await AppController.load(restoreSession: false);
    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: const RequiredPasswordPage(),
        locale: const Locale('en'),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    expect(find.byTooltip('Show password'), findsNWidgets(3));
    final systemUiRegions = tester
        .widgetList<AnnotatedRegion<SystemUiOverlayStyle>>(
          find.byWidgetPredicate(
            (widget) => widget is AnnotatedRegion<SystemUiOverlayStyle>,
          ),
        );
    expect(
      systemUiRegions.any(
        (region) => region.value.statusBarIconBrightness == Brightness.light,
      ),
      isTrue,
    );
    await tester.tap(find.byTooltip('Show password').first);
    await tester.pump();

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(3));
    expect(fields[0].obscureText, isFalse);
    expect(fields[1].obscureText, isTrue);
    expect(fields[2].obscureText, isTrue);
  });

  testWidgets('empty-state motion stops when animations are disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: const Scaffold(
          body: EmptyState(title: 'Clear', body: 'Nothing pending'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Clear'), findsOneWidget);
  });

  testWidgets('premium toasts queue and expose a dismissible live region', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: child!,
        ),
        home: Scaffold(
          body: Builder(
            builder: (context) => FilledButton(
              onPressed: () {
                showPremiumToast(context, 'First message');
                showPremiumToast(context, 'Second message');
              },
              child: const Text('Show'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Show'));
    await tester.pump();
    expect(find.text('First message'), findsOneWidget);
    expect(find.text('Second message'), findsNothing);

    final semantics = tester.getSemantics(
      find.bySemanticsLabel('First message'),
    );
    expect(semantics.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);

    await tester.tap(find.bySemanticsLabel('First message'));
    await tester.pump();
    expect(find.text('First message'), findsNothing);
    expect(find.text('Second message'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Second message'));
    await tester.pump();
  });

  testWidgets('notification preference is restored on a new settings page', (
    tester,
  ) async {
    final controller = await AppController.load(restoreSession: false);
    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: const SettingsPage(),
        locale: const Locale('en'),
        disableAnimations: true,
      ),
    );
    await tester.pump();

    final notifications = find.widgetWithText(SwitchListTile, 'Notifications');
    await tester.fling(find.byType(ListView), const Offset(0, -700), 1000);
    await tester.pumpAndSettle();
    await tester.tap(notifications);
    await tester.pump();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getBool('settings.inAppNotifications'), isFalse);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpWidget(
      _harness(
        controller: controller,
        child: const SettingsPage(),
        locale: const Locale('en'),
        disableAnimations: true,
      ),
    );
    await tester.pump();
    await tester.pump();

    final restored = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, 'Notifications'),
    );
    expect(restored.value, isFalse);
  });
}

Widget _harness({
  required AppController controller,
  required Widget child,
  Locale locale = const Locale('uz'),
  bool disableAnimations = false,
  TextScaler textScaler = TextScaler.noScaling,
}) {
  return AppControllerScope(
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
          disableAnimations: disableAnimations,
          textScaler: textScaler,
        ),
        child: child!,
      ),
      home: child,
    ),
  );
}

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:starforge_staff/core/app_controller.dart';
import 'package:starforge_staff/core/app_localizations.dart';
import 'package:starforge_staff/core/app_theme.dart';
import 'package:starforge_staff/data/remote_models.dart';
import 'package:starforge_staff/features/profile/settings_page.dart';
import 'package:starforge_staff/services/starforge_api.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'notification preferences use the production GET and PUT contract',
    () async {
      var requestCount = 0;
      final client = MockClient((request) async {
        requestCount++;
        expect(request.url.path, '/api/v1/notifications/preferences/');
        expect(request.headers['Authorization'], 'Bearer test-access');
        if (request.method == 'GET') {
          return http.Response(
            jsonEncode({
              'success': true,
              'data': [
                {
                  'event_type': 'schedule.lesson_reminder',
                  'channel': 'in_app',
                  'enabled': false,
                },
              ],
            }),
            200,
          );
        }

        expect(request.method, 'PUT');
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        expect(body.keys.toSet(), {'preferences'});
        expect(body['preferences'], [
          {
            'event_type': 'schedule.lesson_reminder',
            'channel': 'in_app',
            'enabled': true,
          },
        ]);
        return http.Response(
          jsonEncode({'success': true, 'data': body['preferences']}),
          200,
        );
      });
      final gateway = RemoteStarforgeGateway(
        client: client,
        sessionStore: MemorySessionStore(access: 'test-access'),
        baseUrl: 'https://example.test',
      );

      final loaded = await gateway.notificationPreferences();
      expect(loaded.single.enabled, isFalse);

      final updated = await gateway.updateNotificationPreferences(const [
        NotificationPreferenceInfo(
          eventType: 'schedule.lesson_reminder',
          channel: 'in_app',
          enabled: true,
        ),
      ]);
      expect(updated.single.enabled, isTrue);
      expect(requestCount, 2);
    },
  );

  testWidgets(
    'failed account preference save rolls back local and visible state',
    (tester) async {
      final gateway = _PreferencesGateway(failWrites: true);
      final controller = await _signedInController(gateway);
      await tester.pumpWidget(_harness(controller));
      await tester.pumpAndSettle();

      final notifications = find.widgetWithText(
        SwitchListTile,
        'Notifications',
      );
      await tester.ensureVisible(notifications);
      await tester.pumpAndSettle();
      expect(tester.widget<SwitchListTile>(notifications).value, isTrue);

      await tester.tap(notifications);
      await tester.pumpAndSettle();

      expect(gateway.writes, 1);
      expect(tester.widget<SwitchListTile>(notifications).value, isTrue);
      expect(
        find.text('Your changes could not be saved. Please try again.'),
        findsOneWidget,
      );
      final local = await SharedPreferences.getInstance();
      expect(local.getBool('settings.inAppNotifications'), isTrue);
    },
  );

  testWidgets('read-only accounts cannot mutate notification preferences', (
    tester,
  ) async {
    final gateway = _PreferencesGateway(readOnly: true);
    final controller = await _signedInController(gateway);
    await tester.pumpWidget(_harness(controller));
    await tester.pumpAndSettle();

    final notifications = find.widgetWithText(SwitchListTile, 'Notifications');
    await tester.ensureVisible(notifications);
    await tester.pumpAndSettle();

    expect(tester.widget<SwitchListTile>(notifications).onChanged, isNull);
    expect(gateway.writes, 0);
  });
}

Future<AppController> _signedInController(_PreferencesGateway gateway) async {
  final controller = await AppController.load(
    gateway: gateway,
    restoreSession: false,
  );
  final result = await controller.signIn(
    username: 'teacher',
    password: 'secure-password',
  );
  expect(result, AuthResult.success);
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
    home: const SettingsPage(),
  ),
);

class _PreferencesGateway implements StarforgeGateway {
  _PreferencesGateway({this.failWrites = false, this.readOnly = false});

  final bool failWrites;
  final bool readOnly;
  int writes = 0;

  StaffAccount get _account => StaffAccount(
    id: 9,
    principalKind: 'teacher',
    username: 'teacher',
    fullName: 'Taylor Teacher',
    firstName: 'Taylor',
    lastName: 'Teacher',
    phone: '',
    email: '',
    preferredLanguage: 'en',
    mustChangePassword: false,
    memberships: const [
      RoleMembership(
        id: 1,
        name: 'Teacher',
        slug: 'teacher',
        kind: 'teacher',
        branchName: 'Central',
        departmentName: 'English',
        branchId: 1,
        departmentId: 1,
      ),
    ],
    permissions: const {'notifications:read'},
    readOnly: readOnly,
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
  Future<List<NotificationPreferenceInfo>> notificationPreferences() async =>
      const [];

  @override
  Future<List<NotificationPreferenceInfo>> updateNotificationPreferences(
    List<NotificationPreferenceInfo> preferences,
  ) async {
    writes++;
    if (failWrites) {
      throw const StarforgeException(
        code: 'connection_unavailable',
        message: 'Unavailable',
      );
    }
    return preferences;
  }

  @override
  Future<void> clearSession() async {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/app_controller.dart';
import 'core/app_localizations.dart';
import 'core/app_theme.dart';
import 'features/auth/login_page.dart';
import 'features/shell/app_shell.dart';

class StarforgeApp extends StatelessWidget {
  const StarforgeApp({super.key, required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return AppControllerScope(
          controller: controller,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            title: 'Starforge Staff',
            theme: AppTheme.light(controller.accent),
            darkTheme: AppTheme.dark(controller.accent),
            themeMode: controller.themeMode,
            locale: controller.locale,
            supportedLocales: AppLocalizations.supportedLocales,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            home: _AppEntry(controller: controller),
          ),
        );
      },
    );
  }
}

class _AppEntry extends StatelessWidget {
  const _AppEntry({required this.controller});

  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final child = !controller.isSignedIn
        ? const LoginPage(key: ValueKey('login'))
        : controller.mustChangePassword
        ? const RequiredPasswordPage(key: ValueKey('password-change'))
        : const AppShell(key: ValueKey('shell'));

    if (reduceMotion) return child;

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) =>
          FadeTransition(opacity: animation, child: child),
      child: child,
    );
  }
}

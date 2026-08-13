import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/app_controller.dart';
import '../../core/app_localizations.dart';
import '../../core/app_theme.dart';
import '../../core/app_widgets.dart';
import '../../core/legal_links.dart';

const _darkSystemUiStyle = SystemUiOverlayStyle(
  statusBarColor: Colors.transparent,
  statusBarIconBrightness: Brightness.light,
  statusBarBrightness: Brightness.dark,
);

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  late final AnimationController _entrance = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1050),
  )..forward();
  bool _obscurePassword = true;
  bool? _reduceMotion;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _entrance.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _entrance.value = 1;
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!(_formKey.currentState?.validate() ?? false) || _submitting) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    final result = await AppControllerScope.of(context).signIn(
      username: _usernameController.text,
      password: _passwordController.text,
    );
    if (!mounted || result == AuthResult.success) return;
    final message = switch (result) {
      AuthResult.invalid => context.tr('invalidLogin'),
      AuthResult.restricted => context.tr('restrictedLogin'),
      AuthResult.rateLimited => context.tr('loginRateLimited'),
      AuthResult.unavailable => context.tr('loginUnavailable'),
      AuthResult.success => '',
    };
    setState(() {
      _submitting = false;
      _error = message;
    });
    showPremiumToast(
      context,
      message,
      icon: result == AuthResult.restricted
          ? Icons.shield_outlined
          : Icons.info_outline_rounded,
      color: result == AuthResult.restricted ? AppTheme.gold : AppTheme.coral,
    );
  }

  void _showForgotPassword() {
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          30 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primaryContainer,
                    Theme.of(
                      context,
                    ).colorScheme.tertiaryContainer.withValues(alpha: .75),
                  ],
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.key_rounded,
                size: 34,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              context.tr('forgotPassword'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              context.tr('forgotMessage'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => Navigator.pop(sheetContext),
                child: Text(context.tr('confirm')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPrivacy() {
    final privacyUri = configuredPrivacyPolicyUri;
    showAppSheet<void>(
      context: context,
      builder: (sheetContext) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          24,
          4,
          24,
          30 + MediaQuery.viewInsetsOf(sheetContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const StarforgeMark(showWordmark: true),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: AppTheme.mint.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: const Icon(
                    Icons.verified_user_outlined,
                    size: 19,
                    color: Color(0xFF278B72),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 26),
            Text(
              context.tr('terms'),
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            Text(
              context.tr('termsBody'),
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                height: 1.55,
              ),
            ),
            const SizedBox(height: 22),
            PremiumCard(
              color: Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: .4),
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(
                    Icons.lock_outline_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      context.tr('secureWorkspace'),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (privacyUri != null) ...[
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final opened = await launchUrl(
                      privacyUri,
                      mode: LaunchMode.externalApplication,
                    );
                    if (!opened && sheetContext.mounted) {
                      showPremiumToast(
                        sheetContext,
                        sheetContext.tr('policyOpenFailed'),
                        icon: Icons.info_outline_rounded,
                      );
                    }
                  },
                  icon: const Icon(Icons.open_in_new_rounded),
                  label: Text(sheetContext.tr('viewFullPolicy')),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppControllerScope.of(context);
    final entrance = CurvedAnimation(
      parent: _entrance,
      curve: Curves.easeOutCubic,
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _darkSystemUiStyle,
      child: Scaffold(
        backgroundColor: const Color(0xFF0D0E1B),
        body: DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF17172B), Color(0xFF0C1720)],
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final isWide =
                    constraints.maxWidth >= 900 && constraints.maxHeight >= 620;
                final isCompactHeight = constraints.maxHeight < 700;
                return Stack(
                  children: [
                    Positioned(
                      left: isWide ? 36 : 20,
                      top: 12,
                      child: const StarforgeMark(
                        onDark: true,
                        showWordmark: true,
                      ),
                    ),
                    Positioned(
                      right: isWide ? 32 : 14,
                      top: 6,
                      child: _LanguageButton(controller: controller),
                    ),
                    Center(
                      child: SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          isWide ? 54 : 20,
                          isCompactHeight ? 64 : 84,
                          isWide ? 54 : 20,
                          28,
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1160),
                          child: isWide
                              ? Row(
                                  children: [
                                    Expanded(
                                      child: FadeTransition(
                                        opacity: entrance,
                                        child: SlideTransition(
                                          position: Tween(
                                            begin: const Offset(-.06, 0),
                                            end: Offset.zero,
                                          ).animate(entrance),
                                          child: _LoginStory(compact: false),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 78),
                                    SizedBox(
                                      width: 452,
                                      child: _EntranceItem(
                                        animation: entrance,
                                        begin: const Offset(.07, 0),
                                        child: _buildForm(),
                                      ),
                                    ),
                                  ],
                                )
                              : _EntranceItem(
                                  animation: entrance,
                                  begin: const Offset(0, .04),
                                  child: _buildForm(),
                                ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildForm() => _GlassLoginCard(
    formKey: _formKey,
    usernameController: _usernameController,
    passwordController: _passwordController,
    obscurePassword: _obscurePassword,
    submitting: _submitting,
    error: _error,
    onTogglePassword: () =>
        setState(() => _obscurePassword = !_obscurePassword),
    onSubmit: _submit,
    onForgot: _showForgotPassword,
    onPrivacy: _showPrivacy,
  );
}

class _EntranceItem extends StatelessWidget {
  const _EntranceItem({
    required this.animation,
    required this.begin,
    required this.child,
  });
  final Animation<double> animation;
  final Offset begin;
  final Widget child;

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: animation,
    child: SlideTransition(
      position: Tween(begin: begin, end: Offset.zero).animate(animation),
      child: child,
    ),
  );
}

class _LoginStory extends StatelessWidget {
  const _LoginStory({this.compact = false});
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: compact
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        Container(
          width: compact ? 78 : 104,
          height: compact ? 78 : 104,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 27 : 35),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9A8EFF), Color(0xFF5B51D6)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: .3)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF7B70FA).withValues(alpha: .28),
                blurRadius: 32,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: compact ? 39 : 52,
          ),
        ),
        SizedBox(height: compact ? 20 : 34),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(99),
            border: Border.all(color: Colors.white.withValues(alpha: .11)),
          ),
          child: Text(
            context.tr('loginEyebrow'),
            style: const TextStyle(
              color: Color(0xFFBDB7FF),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.35,
            ),
          ),
        ),
        SizedBox(height: compact ? 14 : 20),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 610),
          child: Text(
            context.tr('loginPromise'),
            textAlign: compact ? TextAlign.center : TextAlign.start,
            style: Theme.of(context).textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontSize: compact ? 34 : 54,
              height: 1.02,
              letterSpacing: -1.8,
            ),
          ),
        ),
        SizedBox(height: compact ? 10 : 18),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540),
          child: Text(
            context.tr('loginDetail'),
            textAlign: compact ? TextAlign.center : TextAlign.start,
            maxLines: compact ? 2 : 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: Colors.white.withValues(alpha: .64),
              height: 1.55,
              fontSize: compact ? 14 : 17,
            ),
          ),
        ),
      ],
    );
  }
}

class _GlassLoginCard extends StatelessWidget {
  const _GlassLoginCard({
    required this.formKey,
    required this.usernameController,
    required this.passwordController,
    required this.obscurePassword,
    required this.submitting,
    required this.error,
    required this.onTogglePassword,
    required this.onSubmit,
    required this.onForgot,
    required this.onPrivacy,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController usernameController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool submitting;
  final String? error;
  final VoidCallback onTogglePassword;
  final VoidCallback onSubmit;
  final VoidCallback onForgot;
  final VoidCallback onPrivacy;

  @override
  Widget build(BuildContext context) {
    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(18),
      borderSide: BorderSide(color: Colors.white.withValues(alpha: .1)),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(26, 28, 26, 22),
      decoration: BoxDecoration(
        color: const Color(0xFF17182B).withValues(alpha: .92),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: Colors.white.withValues(alpha: .12)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: .25),
            blurRadius: 32,
            offset: const Offset(0, 18),
          ),
        ],
      ),
      child: AutofillGroup(
        child: Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('welcomeBack'),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 7),
              Text(
                context.tr('loginSubtitle'),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: .58),
                ),
              ),
              const SizedBox(height: 26),
              _DarkField(
                fieldKey: const ValueKey('usernameField'),
                controller: usernameController,
                label: context.tr('username'),
                icon: Icons.person_outline_rounded,
                border: fieldBorder,
                textInputAction: TextInputAction.next,
                validator: (value) => value == null || value.trim().isEmpty
                    ? context.tr('usernameRequired')
                    : null,
              ),
              const SizedBox(height: 14),
              _DarkField(
                fieldKey: const ValueKey('passwordField'),
                controller: passwordController,
                label: context.tr('password'),
                icon: Icons.lock_outline_rounded,
                border: fieldBorder,
                obscureText: obscurePassword,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => onSubmit(),
                suffix: IconButton(
                  onPressed: onTogglePassword,
                  tooltip: context.tr(
                    obscurePassword ? 'showPassword' : 'hidePassword',
                  ),
                  icon: Icon(
                    obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white.withValues(alpha: .55),
                  ),
                ),
                validator: (value) => value == null || value.isEmpty
                    ? context.tr('passwordRequired')
                    : null,
              ),
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: TextButton(
                  onPressed: submitting ? null : onForgot,
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFFC6C1FF),
                    visualDensity: VisualDensity.compact,
                  ),
                  child: Text(context.tr('forgotPassword')),
                ),
              ),
              AnimatedSize(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : const Duration(milliseconds: 280),
                curve: Curves.easeOutCubic,
                child: error == null
                    ? const SizedBox.shrink()
                    : Container(
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 14),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.coral.withValues(alpha: .1),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: AppTheme.coral.withValues(alpha: .22),
                          ),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.info_outline_rounded,
                              color: AppTheme.coral,
                              size: 19,
                            ),
                            const SizedBox(width: 9),
                            Expanded(
                              child: Text(
                                error!,
                                style: const TextStyle(
                                  color: Color(0xFFFFB2AF),
                                  fontSize: 12.5,
                                  height: 1.35,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
              SizedBox(
                width: double.infinity,
                height: 57,
                child: _GradientLoginButton(
                  key: const ValueKey('loginButton'),
                  loading: submitting,
                  onPressed: submitting ? null : onSubmit,
                  label: context.tr('signIn'),
                ),
              ),
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  onPressed: onPrivacy,
                  icon: const Icon(Icons.shield_outlined, size: 17),
                  label: Text(context.tr('privacyPolicy')),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white.withValues(alpha: .56),
                    textStyle: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DarkField extends StatelessWidget {
  const _DarkField({
    this.fieldKey,
    required this.controller,
    required this.label,
    required this.icon,
    required this.border,
    this.obscureText = false,
    this.suffix,
    this.validator,
    this.textInputAction,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final Key? fieldKey;
  final String label;
  final IconData icon;
  final InputBorder border;
  final bool obscureText;
  final Widget? suffix;
  final FormFieldValidator<String>? validator;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => TextFormField(
    key: fieldKey,
    controller: controller,
    obscureText: obscureText,
    validator: validator,
    textInputAction: textInputAction,
    onFieldSubmitted: onSubmitted,
    autofillHints: obscureText
        ? const [AutofillHints.password]
        : const [AutofillHints.username],
    keyboardType: obscureText
        ? TextInputType.visiblePassword
        : TextInputType.text,
    autocorrect: false,
    enableSuggestions: !obscureText,
    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
    cursorColor: const Color(0xFFAAA3FF),
    decoration: InputDecoration(
      labelText: label,
      labelStyle: TextStyle(color: Colors.white.withValues(alpha: .55)),
      floatingLabelStyle: const TextStyle(color: Color(0xFFC5C0FF)),
      prefixIcon: Icon(icon, color: Colors.white.withValues(alpha: .55)),
      suffixIcon: suffix,
      filled: true,
      fillColor: Colors.black.withValues(alpha: .16),
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: Color(0xFF958CFF), width: 1.5),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.coral),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: const BorderSide(color: AppTheme.coral, width: 1.5),
      ),
      errorStyle: const TextStyle(color: Color(0xFFFFB2AF)),
    ),
  );
}

class _GradientLoginButton extends StatelessWidget {
  const _GradientLoginButton({
    super.key,
    required this.loading,
    required this.onPressed,
    required this.label,
  });
  final bool loading;
  final VoidCallback? onPressed;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        colors: onPressed == null
            ? const [Color(0xFF4A486B), Color(0xFF49475F)]
            : const [Color(0xFF8E83FF), Color(0xFF5E55D8)],
      ),
      borderRadius: BorderRadius.circular(18),
      boxShadow: onPressed == null
          ? null
          : [
              BoxShadow(
                color: const Color(0xFF766BEC).withValues(alpha: .34),
                blurRadius: 24,
                offset: const Offset(0, 11),
              ),
            ],
    ),
    child: Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            child: loading
                ? const SizedBox(
                    key: ValueKey('login-progress'),
                    width: 23,
                    height: 23,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  )
                : Row(
                    key: const ValueKey('login-label'),
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 9),
                      const Icon(
                        Icons.arrow_forward_rounded,
                        color: Colors.white,
                        size: 19,
                      ),
                    ],
                  ),
          ),
        ),
      ),
    ),
  );
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.controller});
  final AppController controller;

  @override
  Widget build(BuildContext context) {
    final current = controller.locale.languageCode.toUpperCase();
    return PopupMenuButton<String>(
      tooltip: context.tr('language'),
      onSelected: (value) => controller.setLocale(Locale(value)),
      color: const Color(0xFF20213A),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      itemBuilder: (_) => const [
        PopupMenuItem(
          value: 'uz',
          child: _LanguageRow(code: 'UZ', name: 'O‘zbekcha'),
        ),
        PopupMenuItem(
          value: 'en',
          child: _LanguageRow(code: 'EN', name: 'English'),
        ),
        PopupMenuItem(
          value: 'ru',
          child: _LanguageRow(code: 'RU', name: 'Русский'),
        ),
      ],
      child: Semantics(
        button: true,
        label: '${context.tr('language')}: $current',
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: .12)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language_rounded, color: Colors.white, size: 18),
              const SizedBox(width: 7),
              Text(
                current,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 3),
              const Icon(
                Icons.expand_more_rounded,
                color: Colors.white54,
                size: 17,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LanguageRow extends StatelessWidget {
  const _LanguageRow({required this.code, required this.name});
  final String code;
  final String name;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Container(
        width: 34,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: const Color(0xFF8C82FF).withValues(alpha: .18),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Text(
          code,
          style: const TextStyle(
            color: Color(0xFFC9C4FF),
            fontSize: 11,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      const SizedBox(width: 11),
      Text(name, style: const TextStyle(color: Colors.white)),
    ],
  );
}

class RequiredPasswordPage extends StatefulWidget {
  const RequiredPasswordPage({super.key});

  @override
  State<RequiredPasswordPage> createState() => _RequiredPasswordPageState();
}

class _RequiredPasswordPageState extends State<RequiredPasswordPage> {
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  bool _obscureCurrent = true;
  bool _obscureNext = true;
  bool _obscureConfirm = true;
  String? _error;

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_next.text.length < 10) {
      setState(() => _error = context.tr('passwordRules'));
      return;
    }
    if (_next.text != _confirm.text) {
      setState(() => _error = context.tr('passwordMismatch'));
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final ok = await AppControllerScope.of(context)
        .completeRequiredPasswordChange(
          currentPassword: _current.text,
          newPassword: _next.text,
        );
    if (!mounted || ok) return;
    setState(() {
      _busy = false;
      _error = context.tr('passwordUpdateFailed');
    });
  }

  @override
  Widget build(BuildContext context) => AnnotatedRegion<SystemUiOverlayStyle>(
    value: _darkSystemUiStyle,
    child: Scaffold(
      backgroundColor: const Color(0xFF101124),
      body: StarfieldBackdrop(
        child: SafeArea(
          child: Center(
            child: AutofillGroup(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 470),
                  child: Column(
                    children: [
                      const StarforgeMark(onDark: true, showWordmark: true),
                      const SizedBox(height: 28),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(30),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                          child: Container(
                            padding: const EdgeInsets.all(26),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF1A1B31,
                              ).withValues(alpha: .86),
                              borderRadius: BorderRadius.circular(30),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: .12),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: 58,
                                  height: 58,
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF8D83FF,
                                    ).withValues(alpha: .16),
                                    borderRadius: BorderRadius.circular(19),
                                  ),
                                  child: const Icon(
                                    Icons.lock_reset_rounded,
                                    color: Color(0xFFBEB8FF),
                                    size: 30,
                                  ),
                                ),
                                const SizedBox(height: 20),
                                Text(
                                  context.tr('passwordRequiredTitle'),
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineMedium
                                      ?.copyWith(color: Colors.white),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  context.tr('passwordRequiredBody'),
                                  style: TextStyle(
                                    color: Colors.white.withValues(alpha: .62),
                                    height: 1.45,
                                  ),
                                ),
                                const SizedBox(height: 24),
                                for (final field in [
                                  (
                                    _current,
                                    'currentPassword',
                                    _obscureCurrent,
                                    () => setState(
                                      () => _obscureCurrent = !_obscureCurrent,
                                    ),
                                  ),
                                  (
                                    _next,
                                    'newPassword',
                                    _obscureNext,
                                    () => setState(
                                      () => _obscureNext = !_obscureNext,
                                    ),
                                  ),
                                  (
                                    _confirm,
                                    'confirmPassword',
                                    _obscureConfirm,
                                    () => setState(
                                      () => _obscureConfirm = !_obscureConfirm,
                                    ),
                                  ),
                                ]) ...[
                                  TextField(
                                    controller: field.$1,
                                    obscureText: field.$3,
                                    autocorrect: false,
                                    enableSuggestions: false,
                                    keyboardType: TextInputType.visiblePassword,
                                    autofillHints: field.$1 == _current
                                        ? const [AutofillHints.password]
                                        : const [AutofillHints.newPassword],
                                    style: const TextStyle(color: Colors.white),
                                    decoration: InputDecoration(
                                      labelText: context.tr(field.$2),
                                      labelStyle: const TextStyle(
                                        color: Colors.white54,
                                      ),
                                      fillColor: Colors.black.withValues(
                                        alpha: .16,
                                      ),
                                      suffixIcon: IconButton(
                                        onPressed: field.$4,
                                        tooltip: context.tr(
                                          field.$3
                                              ? 'showPassword'
                                              : 'hidePassword',
                                        ),
                                        icon: Icon(
                                          field.$3
                                              ? Icons.visibility_outlined
                                              : Icons.visibility_off_outlined,
                                          color: Colors.white54,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                ],
                                Text(
                                  _error ?? context.tr('passwordRules'),
                                  style: TextStyle(
                                    color: _error == null
                                        ? Colors.white54
                                        : const Color(0xFFFFAAA6),
                                    fontSize: 12,
                                  ),
                                ),
                                const SizedBox(height: 18),
                                SizedBox(
                                  width: double.infinity,
                                  child: FilledButton(
                                    onPressed: _busy ? null : _save,
                                    child: _busy
                                        ? const SizedBox(
                                            width: 22,
                                            height: 22,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2.2,
                                            ),
                                          )
                                        : Text(context.tr('updatePassword')),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Center(
                                  child: TextButton(
                                    onPressed: _busy
                                        ? null
                                        : () => AppControllerScope.of(
                                            context,
                                          ).signOut(),
                                    child: Text(context.tr('signOut')),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

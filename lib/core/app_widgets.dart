import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'app_theme.dart';

class StarforgeMark extends StatelessWidget {
  const StarforgeMark({
    super.key,
    this.size = 44,
    this.onDark = false,
    this.showWordmark = false,
  });

  final double size;
  final bool onDark;
  final bool showWordmark;

  @override
  Widget build(BuildContext context) {
    final foreground = onDark
        ? Colors.white
        : Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF9288FF), Color(0xFF5D55D8)],
            ),
            borderRadius: BorderRadius.circular(size * .32),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF6C63E8).withValues(alpha: .28),
                blurRadius: size * .42,
                offset: Offset(0, size * .14),
              ),
            ],
          ),
          child: Icon(
            Icons.auto_awesome_rounded,
            color: Colors.white,
            size: size * .52,
          ),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 12),
          Text(
            'Starforge',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
        ],
      ],
    );
  }
}

class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.onTap,
    this.border,
    this.radius = 24,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;
  final BorderSide? border;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: color ?? scheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side:
            border ??
            BorderSide(color: scheme.outlineVariant.withValues(alpha: .42)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.action,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.titleLarge),
              if (subtitle != null) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (action != null)
          TextButton(onPressed: onAction, child: Text(action!)),
      ],
    );
  }
}

class StatusPill extends StatelessWidget {
  const StatusPill({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final surface = Color.alphaBlend(
      color.withValues(alpha: .13),
      Theme.of(context).colorScheme.surface,
    );
    final foreground = _withMinimumContrast(color, surface);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: foreground),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

Color _withMinimumContrast(Color foreground, Color background) {
  double ratio(Color first, Color second) {
    final light = first.computeLuminance();
    final dark = second.computeLuminance();
    final high = math.max(light, dark);
    final low = math.min(light, dark);
    return (high + .05) / (low + .05);
  }

  var resolved = foreground;
  final target = background.computeLuminance() > .35
      ? Colors.black
      : Colors.white;
  for (var step = 1; step <= 10 && ratio(resolved, background) < 4.5; step++) {
    resolved = Color.lerp(foreground, target, step / 10)!;
  }
  return resolved;
}

class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    super.key,
    required this.name,
    this.size = 46,
    this.color,
    this.showOnline = false,
  });

  final String name;
  final double size;
  final Color? color;
  final bool showOnline;

  String get initials {
    final words = name.trim().split(RegExp(r'\s+'));
    return words
        .take(2)
        .map((word) => word.isEmpty ? '' : word[0])
        .join()
        .toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final palette = [
      const Color(0xFF6C63E8),
      const Color(0xFF098B8C),
      const Color(0xFFE76B81),
      const Color(0xFF9A6B43),
      const Color(0xFF4278C0),
    ];
    final resolved = color ?? palette[name.hashCode.abs() % palette.length];
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: size,
            height: size,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: resolved.withValues(alpha: .14),
              shape: BoxShape.circle,
              border: Border.all(color: resolved.withValues(alpha: .16)),
            ),
            child: Text(
              initials,
              style: TextStyle(
                color: resolved,
                fontWeight: FontWeight.w800,
                fontSize: size * .31,
              ),
            ),
          ),
          if (showOnline)
            Positioned(
              right: -1,
              bottom: 1,
              child: Container(
                width: size * .25,
                height: size * .25,
                decoration: BoxDecoration(
                  color: AppTheme.mint,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.surface,
                    width: 2.5,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class MetricTile extends StatelessWidget {
  const MetricTile({
    super.key,
    required this.value,
    required this.label,
    required this.icon,
    required this.color,
  });

  final String value;
  final String label;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return PremiumCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: color, size: 19),
          ),
          const SizedBox(height: 14),
          Text(
            value,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class PageIntro extends StatelessWidget {
  const PageIntro({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: theme.textTheme.headlineMedium),
              if (subtitle != null) ...[
                const SizedBox(height: 5),
                Text(
                  subtitle!,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ],
          ),
        ),
        ?trailing,
      ],
    );
  }
}

class EmptyState extends StatefulWidget {
  const EmptyState({
    super.key,
    required this.title,
    required this.body,
    this.action,
    this.onAction,
    this.icon = Icons.inbox_rounded,
  });

  final String title;
  final String body;
  final String? action;
  final VoidCallback? onAction;
  final IconData icon;

  @override
  State<EmptyState> createState() => _EmptyStateState();
}

class _EmptyStateState extends State<EmptyState>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AnimatedBuilder(
              animation: _controller,
              builder: (context, child) => Transform.translate(
                offset: Offset(0, -4 * math.sin(_controller.value * math.pi)),
                child: child,
              ),
              child: Container(
                width: 92,
                height: 92,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: .7,
                  ),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.icon,
                  size: 42,
                  color: theme.colorScheme.primary,
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              widget.title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              widget.body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (widget.action != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(
                onPressed: widget.onAction,
                child: Text(widget.action!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.delay = Duration.zero,
    this.offset = const Offset(0, .08),
  });

  final Widget child;
  final Duration delay;
  final Offset offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  Timer? _delayTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
        return;
      }
      final safeDelay = widget.delay > const Duration(milliseconds: 320)
          ? const Duration(milliseconds: 320)
          : widget.delay;
      _delayTimer = Timer(safeDelay, () {
        if (mounted) _controller.forward();
      });
    });
  }

  @override
  void dispose() {
    _delayTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween(begin: widget.offset, end: Offset.zero).animate(curved),
        child: widget.child,
      ),
    );
  }
}

class StarfieldBackdrop extends StatefulWidget {
  const StarfieldBackdrop({super.key, required this.child});

  final Widget child;

  @override
  State<StarfieldBackdrop> createState() => _StarfieldBackdropState();
}

class _StarfieldBackdropState extends State<StarfieldBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 18),
  )..repeat();
  bool? _reduceMotion;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    if (_reduceMotion == reduceMotion) return;
    _reduceMotion = reduceMotion;
    if (reduceMotion) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF11122B),
                  Color(0xFF25265B),
                  Color(0xFF121323),
                ],
                stops: [0, .55, 1],
              ),
            ),
          ),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              painter: _StarfieldPainter(progress: _controller.value),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _StarfieldPainter extends CustomPainter {
  const _StarfieldPainter({required this.progress});
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(42);
    for (var i = 0; i < 38; i++) {
      final x = random.nextDouble() * size.width;
      final baseY = random.nextDouble() * size.height;
      final y = (baseY + progress * (12 + i % 7)) % size.height;
      final radius = .55 + random.nextDouble() * 1.25;
      final twinkle =
          .23 + .37 * (1 + math.sin(progress * math.pi * 2 + i)) / 2;
      canvas.drawCircle(
        Offset(x, y),
        radius,
        Paint()..color = Colors.white.withValues(alpha: twinkle),
      );
    }
    canvas.drawCircle(
      Offset(size.width * .82, size.height * .18),
      size.shortestSide * .22,
      Paint()
        ..shader =
            RadialGradient(
              colors: [
                const Color(0xFF786EFF).withValues(alpha: .22),
                Colors.transparent,
              ],
            ).createShader(
              Rect.fromCircle(
                center: Offset(size.width * .82, size.height * .18),
                radius: size.shortestSide * .22,
              ),
            ),
    );
  }

  @override
  bool shouldRepaint(_StarfieldPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    useSafeArea: true,
    isScrollControlled: isScrollControlled,
    showDragHandle: true,
    builder: builder,
  );
}

void showPremiumToast(
  BuildContext context,
  String message, {
  IconData icon = Icons.check_circle_rounded,
  Color? color,
}) {
  _PremiumToastQueue.show(context, message: message, icon: icon, color: color);
}

class _PremiumToastRequest {
  const _PremiumToastRequest({
    required this.message,
    required this.icon,
    this.color,
  });

  final String message;
  final IconData icon;
  final Color? color;
}

abstract final class _PremiumToastQueue {
  static final List<_PremiumToastRequest> _pending = [];
  static OverlayEntry? _active;
  static OverlayState? _activeOverlay;

  static void show(
    BuildContext context, {
    required String message,
    required IconData icon,
    Color? color,
  }) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (_active != null && !identical(_activeOverlay, overlay)) {
      _active = null;
      _pending.clear();
    }
    _pending.add(
      _PremiumToastRequest(message: message, icon: icon, color: color),
    );
    _showNext(overlay);
  }

  static void _showNext(OverlayState overlay) {
    if (_active != null || _pending.isEmpty) return;
    final request = _pending.removeAt(0);
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ToastOverlay(
        message: request.message,
        icon: request.icon,
        color: request.color,
        onDismissed: () {
          if (entry.mounted) entry.remove();
          _active = null;
          _activeOverlay = null;
          if (overlay.mounted) _showNext(overlay);
        },
      ),
    );
    _active = entry;
    _activeOverlay = overlay;
    overlay.insert(entry);
  }
}

class _ToastOverlay extends StatefulWidget {
  const _ToastOverlay({
    required this.message,
    required this.icon,
    required this.onDismissed,
    this.color,
  });

  final String message;
  final IconData icon;
  final Color? color;
  final VoidCallback onDismissed;

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
    reverseDuration: const Duration(milliseconds: 330),
  );
  Timer? _timer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (MediaQuery.disableAnimationsOf(context)) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
      _timer = Timer(const Duration(milliseconds: 4200), _dismiss);
    });
  }

  Future<void> _dismiss() async {
    if (_dismissed) return;
    _dismissed = true;
    _timer?.cancel();
    if (mounted && !MediaQuery.disableAnimationsOf(context)) {
      await _controller.reverse();
    }
    if (mounted) widget.onDismissed();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    final toastColor = widget.color ?? AppTheme.mint;
    final toastForeground = _withMinimumContrast(
      toastColor,
      theme.colorScheme.inverseSurface,
    );
    return Positioned(
      left: 18,
      right: 18,
      top: MediaQuery.paddingOf(context).top + 12,
      child: Semantics(
        container: true,
        liveRegion: true,
        label: widget.message,
        button: true,
        onTap: _dismiss,
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, -.45),
              end: Offset.zero,
            ).animate(curved),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: theme.colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: .22),
                      blurRadius: 30,
                      offset: const Offset(0, 12),
                    ),
                  ],
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _dismiss,
                    borderRadius: BorderRadius.circular(18),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 15,
                        vertical: 13,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: toastColor.withValues(alpha: .16),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              widget.icon,
                              color: toastForeground,
                              size: 19,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Flexible(
                            child: ExcludeSemantics(
                              child: Text(
                                widget.message,
                                style: theme.textTheme.bodyMedium?.copyWith(
                                  color: theme.colorScheme.onInverseSurface,
                                  fontWeight: FontWeight.w600,
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
      ),
    );
  }
}

class MaxWidthBox extends StatelessWidget {
  const MaxWidthBox({
    super.key,
    required this.child,
    this.maxWidth = 1080,
    this.padding = const EdgeInsets.symmetric(horizontal: 20),
  });

  final Widget child;
  final double maxWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

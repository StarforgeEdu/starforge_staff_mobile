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
        ? const Color(0xFFFFFCF5)
        : Theme.of(context).colorScheme.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: size,
          height: size,
          child: CustomPaint(painter: _StarforgeMarkPainter(foreground)),
        ),
        if (showWordmark) ...[
          const SizedBox(width: 12),
          Text(
            'Starforge',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: foreground,
              fontWeight: FontWeight.w800,
              letterSpacing: -.3,
            ),
          ),
        ],
      ],
    );
  }
}

Path _starPath(Rect bounds, {bool cutout = true}) {
  Offset point(double x, double y) => Offset(
    bounds.left + bounds.width * x / 32,
    bounds.top + bounds.height * y / 32,
  );

  final path = Path()
    ..fillType = PathFillType.evenOdd
    ..moveTo(point(16, 1).dx, point(16, 1).dy)
    ..lineTo(point(19.4, 11.2).dx, point(19.4, 11.2).dy)
    ..lineTo(point(29.9, 11.5).dx, point(29.9, 11.5).dy)
    ..lineTo(point(21.3, 17.6).dx, point(21.3, 17.6).dy)
    ..lineTo(point(24.5, 27.9).dx, point(24.5, 27.9).dy)
    ..lineTo(point(16, 21.4).dx, point(16, 21.4).dy)
    ..lineTo(point(7.5, 27.9).dx, point(7.5, 27.9).dy)
    ..lineTo(point(10.7, 17.6).dx, point(10.7, 17.6).dy)
    ..lineTo(point(2.1, 11.5).dx, point(2.1, 11.5).dy)
    ..lineTo(point(12.6, 11.2).dx, point(12.6, 11.2).dy)
    ..close();
  if (cutout) {
    final center = point(16, 16);
    final radius = bounds.shortestSide * 2.2 / 32;
    path.addOval(Rect.fromCircle(center: center, radius: radius));
  }
  return path;
}

class _StarforgeMarkPainter extends CustomPainter {
  const _StarforgeMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      _starPath(Offset.zero & size),
      Paint()
        ..color = color
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_StarforgeMarkPainter oldDelegate) =>
      oldDelegate.color != color;
}

class PremiumCard extends StatelessWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.color,
    this.onTap,
    this.border,
    this.radius = 16,
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
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(radius),
      side:
          border ??
          BorderSide(color: scheme.outlineVariant.withValues(alpha: .88)),
    );
    return Material(
      color: color ?? scheme.surface,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? Padding(padding: padding, child: child)
          : InkWell(
              onTap: onTap,
              customBorder: shape,
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
      Theme.of(context).colorScheme.primary,
      const Color(0xFF1F6B66),
      const Color(0xFF4F6A3A),
      const Color(0xFF9A6B43),
      const Color(0xFF2A3D8F),
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

class EmptyState extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, size: 34, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            if (action != null) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}

class StarforgeLoader extends StatelessWidget {
  const StarforgeLoader({super.key, this.label = 'Loading', this.size = 48});

  final String label;
  final double size;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      label: label,
      child: SizedBox.square(
        dimension: size,
        child: Stack(
          alignment: Alignment.center,
          children: [
            if (reduceMotion)
              Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: scheme.outlineVariant, width: 2),
                ),
              )
            else
              CircularProgressIndicator(
                strokeWidth: 2.4,
                color: scheme.primary,
                backgroundColor: scheme.outlineVariant.withValues(alpha: .5),
              ),
            StarforgeMark(size: size * .38),
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
    this.offset = const Offset(0, .025),
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
    duration: const Duration(milliseconds: 280),
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
      final safeDelay = widget.delay > const Duration(milliseconds: 160)
          ? const Duration(milliseconds: 160)
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

class StarfieldBackdrop extends StatelessWidget {
  const StarfieldBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const DecoratedBox(
            decoration: BoxDecoration(color: AppTheme.darkCanvas),
          ),
          const CustomPaint(painter: _BrandBackdropPainter()),
          child,
        ],
      ),
    );
  }
}

class _BrandBackdropPainter extends CustomPainter {
  const _BrandBackdropPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final large = math.min(size.width * .72, 430.0);
    canvas.drawPath(
      _starPath(
        Rect.fromLTWH(size.width - large * .62, -large * .3, large, large),
        cutout: false,
      ),
      Paint()
        ..color = const Color(0xFFE4815B).withValues(alpha: .10)
        ..isAntiAlias = true,
    );
    final small = math.min(size.width * .28, 150.0);
    canvas.drawPath(
      _starPath(
        Rect.fromLTWH(-small * .26, size.height - small * .78, small, small),
      ),
      Paint()
        ..color = const Color(0xFFF4E9D3).withValues(alpha: .13)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2
        ..isAntiAlias = true,
    );
  }

  @override
  bool shouldRepaint(_BrandBackdropPainter oldDelegate) => false;
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
    duration: const Duration(milliseconds: 260),
    reverseDuration: const Duration(milliseconds: 160),
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
      curve: Curves.easeOutCubic,
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
              begin: const Offset(0, -.16),
              end: Offset.zero,
            ).animate(curved),
            child: Center(
              child: Container(
                constraints: const BoxConstraints(maxWidth: 520),
                decoration: BoxDecoration(
                  color: theme.colorScheme.inverseSurface,
                  borderRadius: BorderRadius.circular(14),
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
                    borderRadius: BorderRadius.circular(14),
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

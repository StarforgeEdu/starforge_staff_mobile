import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_controller.dart';

/// Shared Starforge product tokens adapted to native Material surfaces.
///
/// The web products use a warm, editorial palette. Mobile keeps the same
/// identity while relying on system typography and platform navigation.
abstract final class AppTheme {
  static const ink = Color(0xFF1F1B16);
  static const canvas = Color(0xFFFBF6EC);
  static const darkCanvas = Color(0xFF14110D);
  static const gold = Color(0xFFD89A2E);
  static const mint = Color(0xFF4F7B3B);
  static const coral = Color(0xFFB33A2A);

  static const _lightSurface = Color(0xFFFFFCF5);
  static const _lightSurfaceLow = Color(0xFFF8F0E1);
  static const _lightSurfaceMid = Color(0xFFF4EBD8);
  static const _lightSurfaceHigh = Color(0xFFEADFC4);
  static const _lightMuted = Color(0xFF786850);
  static const _lightBorder = Color(0xFFE5D9BE);

  static const _darkSurface = Color(0xFF1D1914);
  static const _darkSurfaceLow = Color(0xFF241E18);
  static const _darkSurfaceMid = Color(0xFF2B241C);
  static const _darkSurfaceHigh = Color(0xFF3E3327);
  static const _darkInk = Color(0xFFF4E9D3);
  static const _darkMuted = Color(0xFFC5B79C);
  static const _darkBorder = Color(0xFF493E30);

  static ThemeData light(AccentChoice accent) =>
      _theme(brightness: Brightness.light, primary: accent.color);

  static ThemeData dark(AccentChoice accent) =>
      _theme(brightness: Brightness.dark, primary: accent.darkColor);

  static ThemeData _theme({
    required Brightness brightness,
    required Color primary,
  }) {
    final isDark = brightness == Brightness.dark;
    final background = isDark ? darkCanvas : canvas;
    final surface = isDark ? _darkSurface : _lightSurface;
    final onSurface = isDark ? _darkInk : ink;
    final muted = isDark ? _darkMuted : _lightMuted;
    final border = isDark ? _darkBorder : _lightBorder;
    final primaryContainer = isDark
        ? Color.alphaBlend(primary.withValues(alpha: .22), _darkSurfaceMid)
        : Color.alphaBlend(primary.withValues(alpha: .14), _lightSurfaceMid);
    final generated = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      surface: surface,
    );
    final scheme = generated.copyWith(
      primary: primary,
      onPrimary: isDark ? const Color(0xFF24120B) : const Color(0xFFFFFCF5),
      primaryContainer: primaryContainer,
      onPrimaryContainer: isDark ? _darkInk : const Color(0xFF512617),
      secondary: isDark ? const Color(0xFFF0B85A) : gold,
      onSecondary: const Color(0xFF2B1D06),
      secondaryContainer: isDark
          ? const Color(0xFF4A3512)
          : const Color(0xFFF3E2BE),
      onSecondaryContainer: isDark
          ? const Color(0xFFFFE8B8)
          : const Color(0xFF4A3107),
      error: isDark ? const Color(0xFFF28B78) : coral,
      onError: isDark ? const Color(0xFF3A0D06) : Colors.white,
      errorContainer: isDark
          ? const Color(0xFF5A2118)
          : const Color(0xFFF5D9D2),
      onErrorContainer: isDark
          ? const Color(0xFFFFDAD2)
          : const Color(0xFF5B1710),
      surface: surface,
      onSurface: onSurface,
      surfaceContainerLowest: isDark ? darkCanvas : const Color(0xFFFFFDF8),
      surfaceContainerLow: isDark ? _darkSurfaceLow : _lightSurfaceLow,
      surfaceContainer: isDark ? _darkSurfaceMid : _lightSurfaceMid,
      surfaceContainerHigh: isDark
          ? const Color(0xFF342B21)
          : const Color(0xFFEFE4CF),
      surfaceContainerHighest: isDark ? _darkSurfaceHigh : _lightSurfaceHigh,
      onSurfaceVariant: muted,
      outline: isDark ? const Color(0xFF8D7F66) : const Color(0xFFBDAF91),
      outlineVariant: border,
      inverseSurface: isDark
          ? const Color(0xFFF4E9D3)
          : const Color(0xFF2C261F),
      onInverseSurface: isDark
          ? const Color(0xFF2C261F)
          : const Color(0xFFFFF7E8),
      inversePrimary: isDark
          ? accentForInverse(primary)
          : const Color(0xFFF0A07C),
    );
    final typography = Typography.material2021(platform: defaultTargetPlatform);
    final baseText = (isDark ? typography.white : typography.black).apply(
      bodyColor: onSurface,
      displayColor: onSurface,
    );
    final textTheme = baseText.copyWith(
      displaySmall: baseText.displaySmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.8,
        height: 1.08,
      ),
      headlineLarge: baseText.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.7,
        height: 1.1,
      ),
      headlineMedium: baseText.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.5,
        height: 1.14,
      ),
      headlineSmall: baseText.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -.25,
        height: 1.18,
      ),
      titleLarge: baseText.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -.2,
        height: 1.2,
      ),
      titleMedium: baseText.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      titleSmall: baseText.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: baseText.bodyLarge?.copyWith(height: 1.45),
      bodyMedium: baseText.bodyMedium?.copyWith(height: 1.45),
      bodySmall: baseText.bodySmall?.copyWith(height: 1.4),
      labelLarge: baseText.labelLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: .05,
      ),
      labelMedium: baseText.labelMedium?.copyWith(fontWeight: FontWeight.w600),
      labelSmall: baseText.labelSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.25,
      ),
    );
    final inputShape = OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
    );
    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      focusColor: primary.withValues(alpha: .16),
      textTheme: textTheme,
      visualDensity: VisualDensity.adaptivePlatformDensity,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: onSurface,
        centerTitle: defaultTargetPlatform == TargetPlatform.iOS,
        titleTextStyle: textTheme.titleLarge?.copyWith(color: onSurface),
      ),
      cardTheme: CardThemeData(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border.withValues(alpha: .9)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark ? _darkSurfaceLow : _lightSurfaceLow,
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        border: inputShape.copyWith(borderSide: BorderSide(color: border)),
        enabledBorder: inputShape.copyWith(
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: inputShape.copyWith(
          borderSide: BorderSide(color: primary, width: 1.6),
        ),
        errorBorder: inputShape.copyWith(
          borderSide: BorderSide(color: scheme.error),
        ),
        focusedErrorBorder: inputShape.copyWith(
          borderSide: BorderSide(color: scheme.error, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 52),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          elevation: 0,
          disabledBackgroundColor: scheme.surfaceContainerHighest,
          disabledForegroundColor: muted,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          side: BorderSide(color: scheme.outline),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: const TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: primaryContainer,
        side: BorderSide.none,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
        labelStyle: TextStyle(
          color: scheme.onPrimaryContainer,
          fontWeight: FontWeight.w600,
        ),
      ),
      dividerTheme: DividerThemeData(color: border, thickness: 1, space: 1),
      listTileTheme: ListTileThemeData(
        minTileHeight: 54,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16),
        iconColor: muted,
        textColor: onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 70,
        indicatorColor: primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.labelSmall?.copyWith(
            color: states.contains(WidgetState.selected) ? primary : muted,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w800
                : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          return IconThemeData(
            color: states.contains(WidgetState.selected) ? primary : muted,
            size: 24,
          );
        }),
      ),
      badgeTheme: BadgeThemeData(
        backgroundColor: scheme.error,
        textColor: scheme.onError,
        padding: const EdgeInsets.symmetric(horizontal: 5),
        textStyle: textTheme.labelSmall?.copyWith(
          color: scheme.onError,
          fontWeight: FontWeight.w800,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: surface,
        indicatorColor: primaryContainer,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        selectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: primary,
          fontWeight: FontWeight.w700,
        ),
        unselectedLabelTextStyle: textTheme.labelMedium?.copyWith(
          color: muted,
          fontWeight: FontWeight.w600,
        ),
        selectedIconTheme: IconThemeData(color: primary, size: 24),
        unselectedIconTheme: IconThemeData(color: muted, size: 24),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: primary,
        linearTrackColor: border.withValues(alpha: .5),
      ),
      checkboxTheme: CheckboxThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        side: BorderSide(color: scheme.outline, width: 1.4),
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? primary : null,
        ),
      ),
      radioTheme: RadioThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? primary : scheme.outline,
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? scheme.onPrimary
              : scheme.onSurfaceVariant,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? primary
              : scheme.surfaceContainerHighest,
        ),
        trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: scheme.inverseSurface,
          borderRadius: BorderRadius.circular(10),
        ),
        textStyle: textTheme.labelMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        waitDuration: const Duration(milliseconds: 500),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 8,
        shadowColor: scheme.shadow.withValues(alpha: .16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      scrollbarTheme: ScrollbarThemeData(
        radius: const Radius.circular(99),
        thickness: const WidgetStatePropertyAll(4),
        thumbColor: WidgetStatePropertyAll(
          muted.withValues(alpha: isDark ? .58 : .38),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          minimumSize: const Size.square(48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: scheme.onInverseSurface,
        ),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static Color accentForInverse(Color color) =>
      Color.lerp(color, Colors.white, .34)!;
}

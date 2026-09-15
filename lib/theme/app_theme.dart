import 'package:flutter/material.dart';

/// Matrix design tokens (see DESIGN.md): one deep monochrome ground, hairline
/// borders, near-square corners and a single green interaction accent.
abstract final class AppColors {
  // Surfaces, stepped by elevation.
  static const background = Color(0xFF0B0C14);
  static const surface = Color(0xFF10121B);
  static const surfaceRaised = Color(0xFF161925);
  static const surfaceOverlay = Color(0xFF1C2030);

  // Hairlines.
  static const border = Color(0xFF232838);
  static const borderStrong = Color(0xFF363C52);

  // Text. Contrast on [background]: primary 15.9:1, secondary 8.4:1,
  // muted 5.2:1. Keep muted text on [surfaceRaised] or darker (4.7:1).
  static const textPrimary = Color(0xFFE6E8EF);
  static const textSecondary = Color(0xFFA3A8BA);
  static const textMuted = Color(0xFF7D8397);

  // Brand accent. Text on the accent must be dark: white on #2DB58A is 2.7:1.
  static const primary = Color(0xFF2DB58A);
  static const onPrimary = background;
  static const primaryTint = Color(0x1F2DB58A);

  // Semantic tones.
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFD97706);

  /// The brand danger token. It measures 4.0:1 on [background], below AA for
  /// small text, so use it for fills and [dangerText] for text and icons.
  static const danger = Color(0xFFDC2626);
  static const dangerText = Color(0xFFF87171);
  static const info = Color(0xFF38BDF8);
}

/// Spacing scale: 4/8/12/16/24/32.
abstract final class AppSpace {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// Corner radii: near-square badges, 4px controls, 8px containers.
abstract final class AppRadius {
  static const double xs = 2;
  static const double sm = 4;
  static const double md = 8;
}

/// Semantic tone for status pills, badges and feedback.
enum AppTone { neutral, primary, success, warning, danger, info }

extension AppToneColors on AppTone {
  Color get foreground => switch (this) {
    AppTone.neutral => AppColors.textSecondary,
    AppTone.primary => AppColors.primary,
    AppTone.success => AppColors.success,
    AppTone.warning => AppColors.warning,
    AppTone.danger => AppColors.dangerText,
    AppTone.info => AppColors.info,
  };

  Color get container => this == AppTone.neutral
      ? AppColors.surfaceRaised
      : foreground.withValues(alpha: 0.12);

  Color get outline => this == AppTone.neutral
      ? AppColors.border
      : foreground.withValues(alpha: 0.35);
}

abstract final class AppTheme {
  /// Space Mono is reserved for labels, badges, numerics and code; body text
  /// uses the platform sans so prose stays readable.
  static const monoFamily = 'SpaceMono';

  // Type scale 12/14/16/20/24/32. Colors are set per style (not via
  // TextTheme.apply, which would flatten the secondary/muted roles).
  static const _textTheme = TextTheme(
    displaySmall: TextStyle(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    headlineSmall: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    titleLarge: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    titleMedium: TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.w700,
      height: 1.35,
      letterSpacing: 0,
      color: AppColors.textPrimary,
    ),
    titleSmall: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      height: 1.35,
      letterSpacing: 0,
      color: AppColors.textPrimary,
    ),
    // bodyLarge is also the TextField input style, so it stays compact.
    bodyLarge: TextStyle(
      fontSize: 15,
      height: 1.45,
      letterSpacing: 0.1,
      color: AppColors.textPrimary,
    ),
    bodyMedium: TextStyle(
      fontSize: 14,
      height: 1.45,
      letterSpacing: 0.1,
      color: AppColors.textPrimary,
    ),
    bodySmall: TextStyle(
      fontSize: 12,
      height: 1.4,
      letterSpacing: 0.2,
      color: AppColors.textSecondary,
    ),
    labelLarge: TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    labelMedium: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: AppColors.textPrimary,
    ),
    labelSmall: TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      fontFamily: monoFamily,
      letterSpacing: 1.0,
      color: AppColors.textMuted,
    ),
  );

  static ThemeData dark() {
    const scheme = ColorScheme(
      brightness: Brightness.dark,
      primary: AppColors.primary,
      onPrimary: AppColors.onPrimary,
      primaryContainer: Color(0xFF0F3B2E),
      onPrimaryContainer: Color(0xFFA7EBD3),
      secondary: AppColors.textSecondary,
      onSecondary: AppColors.background,
      secondaryContainer: AppColors.surfaceOverlay,
      onSecondaryContainer: AppColors.textPrimary,
      tertiary: AppColors.info,
      onTertiary: AppColors.background,
      error: AppColors.dangerText,
      onError: AppColors.background,
      errorContainer: Color(0xFF3A1215),
      onErrorContainer: Color(0xFFFCA5A5),
      surface: AppColors.background,
      onSurface: AppColors.textPrimary,
      onSurfaceVariant: AppColors.textSecondary,
      surfaceContainerLowest: AppColors.background,
      surfaceContainerLow: AppColors.surface,
      surfaceContainer: AppColors.surface,
      surfaceContainerHigh: AppColors.surfaceRaised,
      surfaceContainerHighest: AppColors.surfaceOverlay,
      outline: AppColors.borderStrong,
      outlineVariant: AppColors.border,
      shadow: Colors.black,
      scrim: Colors.black,
      inverseSurface: AppColors.textPrimary,
      onInverseSurface: AppColors.background,
      inversePrimary: Color(0xFF1E7A5D),
      surfaceTint: Colors.transparent,
    );

    const controlShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
    );
    const hairline = BorderSide(color: AppColors.border);
    OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          borderSide: BorderSide(color: color, width: width),
        );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: scheme,
      textTheme: _textTheme,
      scaffoldBackgroundColor: AppColors.background,
      canvasColor: AppColors.background,
      splashFactory: InkRipple.splashFactory,
      iconTheme: const IconThemeData(color: AppColors.textSecondary, size: 20),
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: const AppBarThemeData(
        backgroundColor: AppColors.background,
        foregroundColor: AppColors.textPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: hairline),
        iconTheme: IconThemeData(color: AppColors.textSecondary, size: 20),
        actionsIconTheme: IconThemeData(
          color: AppColors.textSecondary,
          size: 20,
        ),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: AppColors.primaryTint,
        indicatorShape: controlShape,
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected)
                ? FontWeight.w700
                : FontWeight.w400,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 22,
            color: states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textMuted,
          ),
        ),
      ),
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textMuted,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelStyle: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(fontSize: 11),
      ),
      cardTheme: const CardThemeData(
        color: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          side: hairline,
        ),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppSpace.md,
          vertical: AppSpace.md,
        ),
        border: inputBorder(AppColors.border),
        enabledBorder: inputBorder(AppColors.border),
        disabledBorder: inputBorder(AppColors.border),
        focusedBorder: inputBorder(AppColors.primary, 1.5),
        errorBorder: inputBorder(AppColors.dangerText),
        focusedErrorBorder: inputBorder(AppColors.dangerText, 1.5),
        labelStyle: const TextStyle(color: AppColors.textSecondary),
        floatingLabelStyle: const TextStyle(color: AppColors.primary),
        hintStyle: const TextStyle(color: AppColors.textMuted),
        helperStyle: const TextStyle(color: AppColors.textMuted, fontSize: 12),
        prefixIconColor: AppColors.textMuted,
        suffixIconColor: AppColors.textMuted,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          // No background/foreground here: this theme also styles
          // FilledButton.tonal, which must stay a muted secondary action.
          disabledBackgroundColor: AppColors.surfaceOverlay,
          disabledForegroundColor: AppColors.textMuted,
          minimumSize: const Size(0, 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.lg),
          shape: controlShape,
          textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.textPrimary,
          disabledForegroundColor: AppColors.textMuted,
          side: const BorderSide(color: AppColors.borderStrong),
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: AppSpace.md),
          shape: controlShape,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          shape: controlShape,
          textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: AppColors.textSecondary,
          disabledForegroundColor: AppColors.border,
          shape: controlShape,
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.surface,
        selectedColor: AppColors.primaryTint,
        disabledColor: AppColors.surface,
        checkmarkColor: AppColors.primary,
        side: WidgetStateBorderSide.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? AppColors.primary.withValues(alpha: 0.6)
                : AppColors.border,
          ),
        ),
        shape: controlShape,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        labelStyle: TextStyle(
          fontSize: 12,
          color: WidgetStateColor.resolveWith(
            (states) => states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textPrimary,
          ),
        ),
        iconTheme: const IconThemeData(
          color: AppColors.textSecondary,
          size: 16,
        ),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: AppColors.textSecondary,
        textColor: AppColors.textPrimary,
        selectedColor: AppColors.primary,
        selectedTileColor: AppColors.primaryTint,
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpace.lg),
        titleTextStyle: TextStyle(fontSize: 14, color: AppColors.textPrimary),
        subtitleTextStyle: TextStyle(
          fontSize: 12,
          color: AppColors.textSecondary,
        ),
      ),
      expansionTileTheme: const ExpansionTileThemeData(
        shape: Border(),
        collapsedShape: Border(),
        iconColor: AppColors.textSecondary,
        collapsedIconColor: AppColors.textMuted,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: AppColors.surface,
        modalBackgroundColor: AppColors.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        modalElevation: 0,
        dragHandleColor: AppColors.borderStrong,
        dragHandleSize: Size(32, 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.md),
          ),
          side: hairline,
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
          side: BorderSide(color: AppColors.borderStrong),
        ),
        titleTextStyle: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14,
          height: 1.45,
          color: AppColors.textSecondary,
        ),
      ),
      popupMenuTheme: const PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          side: BorderSide(color: AppColors.borderStrong),
        ),
        textStyle: TextStyle(fontSize: 14, color: AppColors.textPrimary),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: AppColors.surfaceOverlay,
        actionTextColor: AppColors.primary,
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        contentTextStyle: TextStyle(fontSize: 13, color: AppColors.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.sm)),
          side: BorderSide(color: AppColors.borderStrong),
        ),
      ),
      tooltipTheme: const TooltipThemeData(
        decoration: BoxDecoration(
          color: AppColors.surfaceOverlay,
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs)),
          border: Border.fromBorderSide(
            BorderSide(color: AppColors.borderStrong),
          ),
        ),
        textStyle: TextStyle(fontSize: 12, color: AppColors.textPrimary),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
        linearTrackColor: AppColors.surfaceOverlay,
        circularTrackColor: Colors.transparent,
      ),
      sliderTheme: const SliderThemeData(
        activeTrackColor: AppColors.primary,
        inactiveTrackColor: AppColors.surfaceOverlay,
        thumbColor: AppColors.primary,
        overlayColor: AppColors.primaryTint,
        valueIndicatorColor: AppColors.surfaceOverlay,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : Colors.transparent,
        ),
        checkColor: const WidgetStatePropertyAll(AppColors.onPrimary),
        side: const BorderSide(color: AppColors.borderStrong, width: 1.5),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.xs)),
        ),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.onPrimary
              : AppColors.textMuted,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.primary
              : AppColors.surfaceOverlay,
        ),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(AppColors.borderStrong),
        radius: Radius.circular(AppRadius.xs),
        thickness: WidgetStatePropertyAll(4),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: AppColors.primary,
        selectionColor: AppColors.primary.withValues(alpha: 0.3),
        selectionHandleColor: AppColors.primary,
      ),
    );
  }
}

import 'package:flutter/material.dart';

/// Palette in stile macOS: grigi neutri, linee sottili, un solo accento.
abstract final class AppColors {
  static const canvas = Color(0xFFF5F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const surfaceMuted = Color(0xFFF2F2F4);
  static const text = Color(0xFF1D1D1F);
  static const textMuted = Color(0xFF6E6E73);
  static const textFaint = Color(0xFFA1A1A6);
  static const border = Color(0xFFE3E3E8);
  static const green = Color(0xFF089B68);
  static const greenSoft = Color(0xFFE3F5EC);
  static const greenPale = Color(0xFFF2F7F4);
  static const warning = Color(0xFF9B6B2F);
  static const warningSoft = Color(0xFFF7EFE3);
  static const danger = Color(0xFFC6453F);
  static const dangerSoft = Color(0xFFFBECEB);

  /// Cornice dell'app: barra laterale, barra superiore, riga selezionata.
  static const sidebar = Color(0xFFEDEDF0);
  static const toolbar = Color(0xFFFBFBFD);
  static const selection = Color(0x14000000);
  static const hover = Color(0x0A000000);
  static const fill = Color(0x0F000000);
  static const controlBorder = Color(0xFFD9D9DE);
}

abstract final class AppSpacing {
  static const xxs = 4.0;
  static const xs = 8.0;
  static const sm = 12.0;
  static const md = 16.0;
  static const lg = 24.0;
  static const xl = 32.0;
  static const xxl = 48.0;
}

abstract final class AppRadius {
  static const control = 8.0;
  static const card = 12.0;
  static const feature = 14.0;
}

abstract final class AppShadows {
  static const card = <BoxShadow>[
    BoxShadow(color: Color(0x0A000000), blurRadius: 3, offset: Offset(0, 1)),
  ];
  static const popover = <BoxShadow>[
    BoxShadow(color: Color(0x33000000), blurRadius: 34, offset: Offset(0, 12)),
  ];
}

ThemeData buildDesktopTheme() {
  final scheme =
      ColorScheme.fromSeed(
        seedColor: AppColors.green,
        brightness: Brightness.light,
        primary: AppColors.green,
        surface: AppColors.surface,
        error: AppColors.danger,
      ).copyWith(
        // Niente velature verdi sulle superfici Material: solo grigi neutri.
        surfaceTint: Colors.transparent,
        onSurface: AppColors.text,
        onSurfaceVariant: AppColors.textMuted,
        outline: const Color(0xFFC7C7CC),
        outlineVariant: AppColors.border,
        surfaceContainerLowest: AppColors.surface,
        surfaceContainerLow: const Color(0xFFF8F8FA),
        surfaceContainer: AppColors.surfaceMuted,
        surfaceContainerHigh: const Color(0xFFECECEF),
        surfaceContainerHighest: const Color(0xFFE6E6EA),
        secondaryContainer: const Color(0xFFE6E6EA),
        onSecondaryContainer: AppColors.text,
      );
  const controlShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
  );
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: scheme,
    scaffoldBackgroundColor: AppColors.canvas,
    fontFamily: 'Segoe UI Variable',
    fontFamilyFallback: const <String>[
      'SF Pro Display',
      'SF Pro Text',
      'Segoe UI',
      'Inter',
      'Arial',
      'sans-serif',
    ],
    // Come su macOS: nessuna onda al clic, solo un leggero cambio di tono.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: AppColors.hover,
  );
  return base.copyWith(
    textTheme: base.textTheme.copyWith(
      displayLarge: const TextStyle(
        fontSize: 42,
        height: 1.08,
        fontWeight: FontWeight.w700,
        letterSpacing: -1.6,
        color: AppColors.text,
      ),
      headlineLarge: const TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.8,
        color: AppColors.text,
      ),
      headlineMedium: const TextStyle(
        fontSize: 24,
        height: 1.2,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: AppColors.text,
      ),
      titleLarge: const TextStyle(
        fontSize: 19,
        height: 1.25,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.2,
        color: AppColors.text,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        height: 1.35,
        fontWeight: FontWeight.w600,
        color: AppColors.text,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.5,
        color: AppColors.text,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.45,
        color: AppColors.textMuted,
      ),
      labelLarge: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    ),
    cardTheme: const CardThemeData(
      color: AppColors.surface,
      margin: EdgeInsets.zero,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.card)),
        side: BorderSide(color: AppColors.border),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.surface,
      hoverColor: Colors.transparent,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.controlBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.controlBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.control),
        borderSide: const BorderSide(color: AppColors.green, width: 2),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      hintStyle: const TextStyle(color: AppColors.textFaint),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 38),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        shape: controlShape,
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 36),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        foregroundColor: AppColors.text,
        backgroundColor: AppColors.surface,
        side: const BorderSide(color: AppColors.controlBorder),
        shape: controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(shape: controlShape),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size.square(40),
        foregroundColor: AppColors.textMuted,
        shape: controlShape,
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        visualDensity: VisualDensity.compact,
        shape: const WidgetStatePropertyAll(controlShape),
        side: const WidgetStatePropertyAll(
          BorderSide(color: AppColors.controlBorder),
        ),
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? const Color(0xFFE6E6EA)
              : AppColors.surface,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? AppColors.text
              : AppColors.textMuted,
        ),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
    ),
    chipTheme: const ChipThemeData(
      backgroundColor: AppColors.surface,
      side: BorderSide(color: AppColors.controlBorder),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(7)),
      ),
      labelStyle: TextStyle(fontSize: 12.5, color: AppColors.text),
    ),
    dialogTheme: const DialogThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 12,
      shadowColor: Color(0x55000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.feature)),
      ),
      titleTextStyle: TextStyle(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        color: AppColors.text,
      ),
      contentTextStyle: TextStyle(
        fontSize: 13.5,
        height: 1.45,
        color: AppColors.text,
      ),
    ),
    popupMenuTheme: const PopupMenuThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 10,
      shadowColor: Color(0x44000000),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        side: BorderSide(color: AppColors.border),
      ),
      textStyle: TextStyle(fontSize: 13, color: AppColors.text),
    ),
    menuTheme: const MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(AppColors.surface),
        surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(10),
        shadowColor: WidgetStatePropertyAll(Color(0x44000000)),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
            side: BorderSide(color: AppColors.border),
          ),
        ),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Color(0xF22C2C2E),
      contentTextStyle: TextStyle(color: Colors.white, fontSize: 13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? AppColors.green
            : const Color(0xFFD9D9DE),
      ),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    checkboxTheme: CheckboxThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
      side: const BorderSide(color: Color(0xFFB9B9BF), width: 1.5),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: AppColors.green,
      linearTrackColor: Color(0xFFE6E6EA),
      circularTrackColor: Colors.transparent,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(7),
      radius: const Radius.circular(8),
      thumbColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.dragged)
            ? const Color(0x99808080)
            : const Color(0x59808080),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: AppColors.textMuted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(AppRadius.control)),
      ),
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border, space: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 450),
      decoration: BoxDecoration(
        color: const Color(0xF22C2C2E),
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(color: Colors.white, fontSize: 12),
    ),
  );
}

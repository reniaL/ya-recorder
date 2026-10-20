import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Shared visual rules for action menus and preference choices.
abstract final class AppMenuStyle {
  static const radius = 16.0;
  static const elevation = 8.0;
  static const horizontalPadding = 16.0;
  static const selectedOpacity = 0.35;
  static const scrimOpacity = 0.32;
  static const maxWidth = 340.0;
  static const shadowColor = Color(0x3d000000);

  static RoundedRectangleBorder get shape =>
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius));

  static Color selectedColor(ColorScheme colors) =>
      colors.primaryContainer.withValues(alpha: selectedOpacity);

  static BoxConstraints constraints(BuildContext context) => BoxConstraints(
    minWidth: math.min(180, MediaQuery.sizeOf(context).width - 32),
    maxWidth: math.min(maxWidth, MediaQuery.sizeOf(context).width - 32),
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final colors =
      ColorScheme.fromSeed(
        seedColor: const Color(0xff0b6657),
        brightness: brightness,
      ).copyWith(
        surface: dark ? const Color(0xff141615) : const Color(0xfff8f9f8),
        surfaceContainerLowest: dark ? const Color(0xff0f1110) : Colors.white,
        surfaceContainerLow: dark
            ? const Color(0xff1c1e1d)
            : const Color(0xfff2f4f3),
        surfaceContainer: dark
            ? const Color(0xff202321)
            : const Color(0xffeceeed),
        surfaceContainerHigh: dark
            ? const Color(0xff2a2d2b)
            : const Color(0xffe6e9e7),
        surfaceContainerHighest: dark
            ? const Color(0xff353836)
            : const Color(0xffdfe3e0),
      );
  final theme = ThemeData(colorScheme: colors, useMaterial3: true);
  return theme.copyWith(
    scaffoldBackgroundColor: colors.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colors.surface,
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
        statusBarBrightness: brightness,
        systemNavigationBarColor: colors.surface,
        systemNavigationBarIconBrightness: dark
            ? Brightness.light
            : Brightness.dark,
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: AppMenuStyle.shape,
      elevation: AppMenuStyle.elevation,
      shadowColor: AppMenuStyle.shadowColor,
      menuPadding: const EdgeInsets.symmetric(vertical: 6),
      textStyle: theme.textTheme.bodyLarge,
    ),
  );
}

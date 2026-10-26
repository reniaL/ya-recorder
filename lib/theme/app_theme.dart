import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'app_palette.dart';

/// Player accents are brighter than text accents, especially for yellow.
class AppPlaybackColors extends ThemeExtension<AppPlaybackColors> {
  const AppPlaybackColors({required this.accent, required this.onAccent});

  final Color accent;
  final Color onAccent;

  @override
  AppPlaybackColors copyWith({Color? accent, Color? onAccent}) =>
      AppPlaybackColors(
        accent: accent ?? this.accent,
        onAccent: onAccent ?? this.onAccent,
      );

  @override
  AppPlaybackColors lerp(AppPlaybackColors? other, double t) => other == null
      ? this
      : AppPlaybackColors(
          accent: Color.lerp(accent, other.accent, t)!,
          onAccent: Color.lerp(onAccent, other.onAccent, t)!,
        );
}

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

ThemeData buildAppTheme(
  Brightness brightness, {
  AppPalette palette = AppPalette.teal,
}) {
  final dark = brightness == Brightness.dark;
  final duckYellow = palette == AppPalette.duckYellow;
  final colors =
      ColorScheme.fromSeed(
        seedColor: palette.seedColor,
        brightness: brightness,
      ).copyWith(
        primary: duckYellow
            ? (dark ? const Color(0xffe4c451) : const Color(0xff705d00))
            : null,
        onPrimary: duckYellow
            ? (dark ? const Color(0xff282100) : Colors.white)
            : null,
        primaryContainer: duckYellow
            ? (dark ? const Color(0xff514400) : const Color(0xfffff0ac))
            : null,
        onPrimaryContainer: duckYellow
            ? (dark ? const Color(0xfffff0ac) : const Color(0xff282100))
            : null,
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
  // Yellow text needs a darker tone on light surfaces. Keep distinct
  // semantic roles for text; use duck yellow only for solid primary actions.
  final actionBackground = dark ? const Color(0xffe4c451) : palette.seedColor;
  const actionForeground = Color(0xff282100);
  final playbackAccent = dark
      ? const Color(0xffffda57)
      : const Color(0xffffd43b);
  return theme.copyWith(
    extensions: [
      if (duckYellow)
        AppPlaybackColors(accent: playbackAccent, onAccent: actionForeground),
    ],
    sliderTheme: duckYellow
        ? SliderThemeData(
            activeTrackColor: playbackAccent,
            thumbColor: playbackAccent,
            inactiveTrackColor: dark
                ? const Color(0xff494944)
                : const Color(0xffe4e4de),
            overlayColor: playbackAccent.withValues(alpha: 0.16),
            thumbShape: const RoundSliderThumbShape(elevation: 3),
          )
        : null,
    filledButtonTheme: duckYellow
        ? FilledButtonThemeData(
            style: FilledButton.styleFrom(
              backgroundColor: actionBackground,
              foregroundColor: actionForeground,
            ),
          )
        : null,
    floatingActionButtonTheme: duckYellow
        ? FloatingActionButtonThemeData(
            backgroundColor: actionBackground,
            foregroundColor: actionForeground,
          )
        : null,
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

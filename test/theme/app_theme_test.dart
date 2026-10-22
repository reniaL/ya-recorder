import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ya_recorder/theme/app_palette.dart';
import 'package:ya_recorder/theme/app_theme.dart';

double contrast(Color a, Color b) {
  final x = a.computeLuminance();
  final y = b.computeLuminance();
  return x > y ? (x + 0.05) / (y + 0.05) : (y + 0.05) / (x + 0.05);
}

void main() {
  for (final brightness in Brightness.values) {
    for (final palette in AppPalette.values) {
      test(
        '$palette $brightness keeps text, actions and selections readable',
        () {
          final theme = buildAppTheme(brightness, palette: palette);
          final colors = theme.colorScheme;
          final selected = Color.alphaBlend(
            AppMenuStyle.selectedColor(colors),
            colors.surfaceContainerLow,
          );
          for (final pair in [
            (colors.onSurface, colors.surface),
            (colors.onSurfaceVariant, colors.surfaceContainerLow),
            (colors.primary, colors.surface),
            (colors.primary, selected),
            (colors.onSurface, selected),
            (colors.onPrimary, colors.primary),
            (colors.onPrimaryContainer, colors.primaryContainer),
            (colors.error, colors.surface),
            (colors.onError, colors.error),
          ]) {
            expect(
              contrast(pair.$1, pair.$2),
              greaterThanOrEqualTo(4.5),
              reason: '$pair',
            );
          }
          final teal = buildAppTheme(brightness).colorScheme;
          expect(colors.surface, teal.surface);
          expect(colors.error, teal.error);
          expect(colors.onError, teal.onError);
          if (palette == AppPalette.duckYellow) {
            final style = theme.filledButtonTheme.style!;
            final background = style.backgroundColor!.resolve({})!;
            final foreground = style.foregroundColor!.resolve({})!;
            expect(contrast(foreground, background), greaterThanOrEqualTo(4.5));
            expect(background, theme.floatingActionButtonTheme.backgroundColor);
            expect(foreground, theme.floatingActionButtonTheme.foregroundColor);
            // Disabled controls still use Material's distinct disabled colors.
            expect(
              style.backgroundColor!.resolve({WidgetState.disabled}),
              isNull,
            );
          }
        },
      );
    }
  }
}

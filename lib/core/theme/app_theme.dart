import 'package:buscar_audifonos/core/theme/app_colors.dart';
import 'package:buscar_audifonos/core/theme/app_spacing.dart';
import 'package:flutter/material.dart';

/// Material 3 themes for the "Faro" brand.
///
/// Sora carries titles and the proximity numbers (light weight, large: a
/// reading you glance at while walking); Manrope carries everything you read.
/// Shapes are thin 1 px lines, round controls and a lot of air — no shadows,
/// no tinted elevation.
///
/// No dynamic colour: Material You would repaint the brand with the user's
/// wallpaper.
abstract final class AppTheme {
  static const String displayFont = 'Sora';
  static const String bodyFont = 'Manrope';

  static ThemeData light() => _build(AppColors.light, AppSemanticColors.light);

  static ThemeData dark() => _build(AppColors.dark, AppSemanticColors.dark);

  static ThemeData _build(ColorScheme scheme, AppSemanticColors semantic) {
    final ThemeData base = ThemeData(colorScheme: scheme, fontFamily: bodyFont);
    final TextTheme text = _textTheme(base.textTheme);
    const RoundedRectangleBorder pill = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill)),
    );
    final BorderSide hairline = BorderSide(color: scheme.outlineVariant);

    return base.copyWith(
      textTheme: text,
      scaffoldBackgroundColor: scheme.surface,
      extensions: <ThemeExtension<dynamic>>[semantic],
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: 1,
        space: 1,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: text.titleLarge,
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainer,
        shape: RoundedRectangleBorder(
          side: hairline,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: AppSpacing.md),
      ),
      chipTheme: ChipThemeData(
        shape: pill,
        side: hairline,
        backgroundColor: Colors.transparent,
        selectedColor: scheme.surfaceContainerHigh,
        checkmarkColor: scheme.primary,
        labelStyle: text.labelLarge?.copyWith(color: scheme.onSurface),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: pill,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          shape: pill,
          side: hairline,
          foregroundColor: scheme.onSurface,
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(shape: pill, textStyle: text.labelLarge),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(foregroundColor: scheme.onSurfaceVariant),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.outlineVariant,
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        insetPadding: EdgeInsets.all(AppSpacing.md),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainer,
        titleTextStyle: text.titleLarge,
        shape: RoundedRectangleBorder(
          side: hairline,
          borderRadius: const BorderRadius.all(Radius.circular(AppRadius.lg)),
        ),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(AppRadius.md)),
        ),
      ),
    );
  }

  /// Sora for headings and numbers, Manrope for the rest. Headings stay at a
  /// semibold; the display sizes are light, which is what makes a large
  /// percentage read as a calm instrument rather than an alarm.
  static TextTheme _textTheme(TextTheme base) {
    TextStyle? sora(TextStyle? style, FontWeight weight) => style?.copyWith(
      fontFamily: displayFont,
      fontWeight: weight,
      letterSpacing: -0.2,
    );

    return base.copyWith(
      displayLarge: sora(base.displayLarge, FontWeight.w300),
      displayMedium: sora(base.displayMedium, FontWeight.w300),
      displaySmall: sora(base.displaySmall, FontWeight.w300),
      headlineLarge: sora(base.headlineLarge, FontWeight.w600),
      headlineMedium: sora(base.headlineMedium, FontWeight.w600),
      headlineSmall: sora(base.headlineSmall, FontWeight.w600),
      titleLarge: sora(
        base.titleLarge,
        FontWeight.w600,
      )?.copyWith(fontSize: 19),
      titleMedium: base.titleMedium?.copyWith(fontWeight: FontWeight.w500),
      labelLarge: base.labelLarge?.copyWith(fontWeight: FontWeight.w700),
    );
  }
}

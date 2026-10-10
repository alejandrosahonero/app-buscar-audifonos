import 'package:flutter/material.dart';

/// "Faro" brand palette.
///
/// Dark-first: a finder is used under beds and in cars, in poor light, so the
/// dark scheme is the default and the light one is its daytime counterpart.
/// One accent only — the amber of a lighthouse — and proximity is a scale of
/// that same light rather than a traffic light.
///
/// Built by hand, never with `ColorScheme.fromSeed`: a seed re-derives every
/// tone and the amber stops being this amber. Rejected along the way, so no one
/// reintroduces them: the template indigo, the red/amber/green proximity
/// traffic light, Bluetooth blue and sonar green (what every competitor uses).
abstract final class AppColors {
  /// Brand dark: header, splash, launcher icon background.
  static const Color marea = Color(0xFF071820);

  /// Lighthouse amber on dark surfaces.
  static const Color luz = Color(0xFFF2B455);

  /// Lighthouse amber on light surfaces: the bright one fails contrast there.
  static const Color luzDia = Color(0xFFA3620A);

  static const Color espuma = Color(0xFFE4EDEF);
  static const Color tinta = Color(0xFF13232A);
  static const Color casco = Color(0xFF0F2A33);
  static const Color niebla = Color(0xFFEDF1F1);
  static const Color bruma = Color(0xFF8FA6AC);
  static const Color brumaDia = Color(0xFF5A6C72);
  static const Color linea = Color(0xFF1E3C47);
  static const Color lineaDia = Color(0xFFD3DCDD);

  static const ColorScheme dark = ColorScheme(
    brightness: Brightness.dark,
    primary: luz,
    onPrimary: Color(0xFF1A1206),
    primaryContainer: Color(0xFF3A2C14),
    onPrimaryContainer: Color(0xFFF7DCAE),
    secondary: bruma,
    onSecondary: marea,
    secondaryContainer: casco,
    onSecondaryContainer: espuma,
    tertiary: luz,
    onTertiary: Color(0xFF1A1206),
    error: Color(0xFFFF8A80),
    onError: Color(0xFF3B0A06),
    surface: marea,
    onSurface: espuma,
    onSurfaceVariant: bruma,
    surfaceContainerLowest: Color(0xFF040F14),
    surfaceContainerLow: Color(0xFF0B2129),
    surfaceContainer: casco,
    surfaceContainerHigh: Color(0xFF143440),
    surfaceContainerHighest: Color(0xFF1A3D4A),
    outline: Color(0xFF3B5B66),
    outlineVariant: linea,
    inverseSurface: espuma,
    onInverseSurface: marea,
    inversePrimary: luzDia,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );

  static const ColorScheme light = ColorScheme(
    brightness: Brightness.light,
    primary: luzDia,
    onPrimary: Colors.white,
    primaryContainer: Color(0xFFF6E3C4),
    onPrimaryContainer: Color(0xFF3A2400),
    secondary: brumaDia,
    onSecondary: Colors.white,
    secondaryContainer: Color(0xFFE2EAEB),
    onSecondaryContainer: tinta,
    tertiary: luzDia,
    onTertiary: Colors.white,
    error: Color(0xFFB3261E),
    onError: Colors.white,
    surface: niebla,
    onSurface: tinta,
    onSurfaceVariant: brumaDia,
    surfaceContainerLowest: Colors.white,
    surfaceContainerLow: Color(0xFFF6F8F8),
    surfaceContainer: Colors.white,
    surfaceContainerHigh: Color(0xFFE6ECEC),
    surfaceContainerHighest: Color(0xFFDDE5E6),
    outline: Color(0xFF8A9CA1),
    outlineVariant: lineaDia,
    inverseSurface: tinta,
    onInverseSurface: niebla,
    inversePrimary: luz,
    shadow: Colors.black,
    scrim: Colors.black,
    surfaceTint: Colors.transparent,
  );
}

/// Colours Material does not model, resolved per brightness and exposed
/// through `context.semanticColors`.
///
/// The proximity bands are one hue at three strengths: the closer the device,
/// the brighter the light. They never use the error red — "far" is not a
/// failure, it is where every search starts.
@immutable
class AppSemanticColors extends ThemeExtension<AppSemanticColors> {
  const AppSemanticColors({
    required this.success,
    required this.warning,
    required this.far,
    required this.near,
    required this.veryNear,
  });

  final Color success;
  final Color warning;
  final Color far;
  final Color near;
  final Color veryNear;

  static const AppSemanticColors dark = AppSemanticColors(
    success: AppColors.luz,
    warning: Color(0xFFFFB4A9),
    far: AppColors.bruma,
    near: Color(0xFFC7965A),
    veryNear: AppColors.luz,
  );

  static const AppSemanticColors light = AppSemanticColors(
    success: AppColors.luzDia,
    warning: Color(0xFFB3261E),
    far: AppColors.brumaDia,
    near: Color(0xFF8C6A3C),
    veryNear: AppColors.luzDia,
  );

  @override
  AppSemanticColors copyWith({
    Color? success,
    Color? warning,
    Color? far,
    Color? near,
    Color? veryNear,
  }) {
    return AppSemanticColors(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      far: far ?? this.far,
      near: near ?? this.near,
      veryNear: veryNear ?? this.veryNear,
    );
  }

  @override
  AppSemanticColors lerp(ThemeExtension<AppSemanticColors>? other, double t) {
    if (other is! AppSemanticColors) return this;
    return AppSemanticColors(
      success: Color.lerp(success, other.success, t) ?? success,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      far: Color.lerp(far, other.far, t) ?? far,
      near: Color.lerp(near, other.near, t) ?? near,
      veryNear: Color.lerp(veryNear, other.veryNear, t) ?? veryNear,
    );
  }
}

import 'package:flutter/material.dart';

class ThemeSurfaceStyle extends ThemeExtension<ThemeSurfaceStyle> {
  final double opacity;
  final double blur;
  final double borderWidth;
  const ThemeSurfaceStyle({
    this.opacity = .52,
    this.blur = 26,
    this.borderWidth = 1,
  });
  @override
  ThemeSurfaceStyle copyWith({
    double? opacity,
    double? blur,
    double? borderWidth,
  }) => ThemeSurfaceStyle(
    opacity: opacity ?? this.opacity,
    blur: blur ?? this.blur,
    borderWidth: borderWidth ?? this.borderWidth,
  );
  @override
  ThemeSurfaceStyle lerp(covariant ThemeSurfaceStyle? other, double t) =>
      other == null
      ? this
      : ThemeSurfaceStyle(
          opacity: opacity + (other.opacity - opacity) * t,
          blur: blur + (other.blur - blur) * t,
          borderWidth: borderWidth + (other.borderWidth - borderWidth) * t,
        );
}

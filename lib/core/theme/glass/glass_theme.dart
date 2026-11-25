import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';

@immutable
class GlassTheme extends ThemeExtension<GlassTheme> {
  const GlassTheme({
    this.blurSigma = 12,
    this.darkOpacity = .54,
    this.lightOpacity = .76,
    this.lowDarkOpacity = .78,
    this.lowLightOpacity = .92,
    this.highDarkOpacity = .44,
    this.highLightOpacity = .68,
    this.borderWidth = 1,
    this.radius = 24,
    this.animationDuration = const Duration(milliseconds: 260),
  });

  final double blurSigma;
  final double darkOpacity;
  final double lightOpacity;
  final double lowDarkOpacity;
  final double lowLightOpacity;
  final double highDarkOpacity;
  final double highLightOpacity;
  final double borderWidth;
  final double radius;
  final Duration animationDuration;

  @override
  GlassTheme copyWith({
    double? blurSigma,
    double? darkOpacity,
    double? lightOpacity,
    double? lowDarkOpacity,
    double? lowLightOpacity,
    double? highDarkOpacity,
    double? highLightOpacity,
    double? borderWidth,
    double? radius,
    Duration? animationDuration,
  }) => GlassTheme(
    blurSigma: blurSigma ?? this.blurSigma,
    darkOpacity: darkOpacity ?? this.darkOpacity,
    lightOpacity: lightOpacity ?? this.lightOpacity,
    lowDarkOpacity: lowDarkOpacity ?? this.lowDarkOpacity,
    lowLightOpacity: lowLightOpacity ?? this.lowLightOpacity,
    highDarkOpacity: highDarkOpacity ?? this.highDarkOpacity,
    highLightOpacity: highLightOpacity ?? this.highLightOpacity,
    borderWidth: borderWidth ?? this.borderWidth,
    radius: radius ?? this.radius,
    animationDuration: animationDuration ?? this.animationDuration,
  );

  @override
  GlassTheme lerp(ThemeExtension<GlassTheme>? other, double t) {
    if (other is! GlassTheme) return this;
    return GlassTheme(
      blurSigma: lerpDouble(blurSigma, other.blurSigma, t)!,
      darkOpacity: lerpDouble(darkOpacity, other.darkOpacity, t)!,
      lightOpacity: lerpDouble(lightOpacity, other.lightOpacity, t)!,
      lowDarkOpacity: lerpDouble(lowDarkOpacity, other.lowDarkOpacity, t)!,
      lowLightOpacity: lerpDouble(lowLightOpacity, other.lowLightOpacity, t)!,
      highDarkOpacity: lerpDouble(highDarkOpacity, other.highDarkOpacity, t)!,
      highLightOpacity: lerpDouble(
        highLightOpacity,
        other.highLightOpacity,
        t,
      )!,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t)!,
      radius: lerpDouble(radius, other.radius, t)!,
      animationDuration: Duration(
        milliseconds:
            (animationDuration.inMilliseconds +
                    (other.animationDuration.inMilliseconds -
                            animationDuration.inMilliseconds) *
                        t)
                .round(),
      ),
    );
  }
}

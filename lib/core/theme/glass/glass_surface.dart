import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'glass_quality.dart';
import 'glass_theme.dart';

class GlassSurface extends ConsumerWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.radius,
    this.quality,
    this.padding,
    this.tintColor,
  });
  final Widget child;
  final double? radius;
  final GlassQuality? quality;
  final EdgeInsetsGeometry? padding;
  final Color? tintColor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final preference = ref.watch(glassQualityProvider);
    var resolvedQuality = preference == GlassQuality.automatic
        ? ref.watch(adaptiveGlassQualityProvider)
        : preference;
    // Local surfaces may cap effects, but never override a more restrictive
    // global choice such as Low or Off.
    if (quality != null && quality!.rank < resolvedQuality.rank) {
      resolvedQuality = quality!;
    }
    final tokens = theme.extension<GlassTheme>() ?? const GlassTheme();
    final dark = tintColor != null
        ? tintColor!.computeLuminance() < .35
        : theme.brightness == Brightness.dark;
    final corner = radius ?? tokens.radius;
    final highContrast = MediaQuery.highContrastOf(context);
    final blur = switch (resolvedQuality) {
      GlassQuality.high => tokens.blurSigma,
      GlassQuality.medium => 8.0,
      _ => 0.0,
    };
    final opaque = resolvedQuality == GlassQuality.off || highContrast;
    final opacity = switch (resolvedQuality) {
      GlassQuality.high =>
        dark ? tokens.highDarkOpacity : tokens.highLightOpacity,
      GlassQuality.medium ||
      GlassQuality.automatic => dark ? tokens.darkOpacity : tokens.lightOpacity,
      GlassQuality.low => dark ? tokens.lowDarkOpacity : tokens.lowLightOpacity,
      GlassQuality.off => 1.0,
    };
    final borderColor = highContrast
        ? (dark ? Colors.white : Colors.black).withValues(alpha: .82)
        : Colors.white.withValues(
            alpha: dark
                ? resolvedQuality == GlassQuality.low
                      ? .28
                      : .18
                : resolvedQuality == GlassQuality.low
                ? .52
                : .38,
          );
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(corner),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: dark ? .22 : .10),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(corner),
          child: (resolvedQuality == GlassQuality.low || opaque)
              ? _decoration(
                  theme,
                  tokens,
                  corner,
                  opaque,
                  opacity,
                  borderColor,
                  highContrast,
                  tintColor,
                )
              : BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
                  child: _decoration(
                    theme,
                    tokens,
                    corner,
                    opaque,
                    opacity,
                    borderColor,
                    highContrast,
                    tintColor,
                  ),
                ),
        ),
      ),
    );
  }

  Widget _decoration(
    ThemeData theme,
    GlassTheme tokens,
    double corner,
    bool opaque,
    double opacity,
    Color borderColor,
    bool highContrast,
    Color? tintColor,
  ) => DecoratedBox(
    decoration: BoxDecoration(
      color: (tintColor ?? theme.colorScheme.surface).withValues(
        alpha: opaque ? 1 : opacity,
      ),
      gradient: opaque
          ? null
          : LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: highContrast ? 0 : .20),
                Colors.white.withValues(alpha: .015),
              ],
            ),
      borderRadius: BorderRadius.circular(corner),
      border: Border.all(
        color: borderColor,
        width: highContrast ? tokens.borderWidth * 1.5 : tokens.borderWidth,
      ),
    ),
    child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
  );
}

class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.child,
    this.onPressed,
    this.borderRadius,
  });
  final Widget child;
  final VoidCallback? onPressed;
  final BorderRadius? borderRadius;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;
  bool get _reduceMotion => MediaQuery.disableAnimationsOf(context);

  void _setPressed(bool value) {
    if (_reduceMotion) value = false;
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTapDown: (_) => _setPressed(true),
    onTapUp: (_) => _setPressed(false),
    onTapCancel: () => _setPressed(false),
    onTap: widget.onPressed,
    child: AnimatedScale(
      scale: _pressed ? .96 : 1,
      duration: _reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 130),
      child: widget.child,
    ),
  );
}

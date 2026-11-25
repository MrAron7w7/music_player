import 'package:flutter/material.dart';

import 'glass_surface.dart';
import 'glass_quality.dart';

class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.child,
    this.pill = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final Widget? child;
  final bool pill;

  @override
  Widget build(BuildContext context) => PressableScale(
    onPressed: null,
    child: GlassSurface(
      radius: pill ? 28 : 18,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(pill ? 28 : 18),
          onTap: onPressed,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: pill ? 16 : 12,
                vertical: 10,
              ),
              child:
                  child ??
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (icon != null) ...[
                        Icon(icon, size: 20),
                        const SizedBox(width: 8),
                      ],
                      Text(label),
                    ],
                  ),
            ),
          ),
        ),
      ),
    ),
  );
}

class GlassIconButton extends StatelessWidget {
  const GlassIconButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.iconSize = 22,
    this.active = false,
    this.iconColor,
    this.surfaceTint,
  });
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final double size;
  final double iconSize;
  final bool active;
  final Color? iconColor;
  final Color? surfaceTint;

  @override
  Widget build(BuildContext context) => Semantics(
    label: label,
    button: true,
    child: Tooltip(
      message: label,
      child: PressableScale(
        onPressed: null,
        child: GlassSurface(
          radius: size / 2,
          quality: GlassQuality.low,
          tintColor: surfaceTint,
          child: SizedBox(
            width: size < 48 ? 48 : size,
            height: size < 48 ? 48 : size,
            child: IconButton(
              tooltip: null,
              onPressed: onPressed,
              icon: Icon(
                icon,
                size: iconSize,
                color:
                    iconColor ??
                    (active
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurface),
              ),
              constraints: const BoxConstraints(minHeight: 48, minWidth: 48),
            ),
          ),
        ),
      ),
    ),
  );
}

class GlassPill extends StatelessWidget {
  const GlassPill({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    this.quality = GlassQuality.low,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final GlassQuality quality;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 30,
    quality: quality,
    padding: padding,
    child: child,
  );
}

class GlassSheet extends StatelessWidget {
  const GlassSheet({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 12, 20, 24),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 30,
    padding: padding,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .3),
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(height: 14),
        child,
      ],
    ),
  );
}

class GlassDialog extends StatelessWidget {
  const GlassDialog({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => Dialog(
    backgroundColor: Colors.transparent,
    child: GlassSurface(
      radius: 28,
      padding: const EdgeInsets.all(20),
      child: child,
    ),
  );
}

class GlassAppBar extends StatelessWidget {
  const GlassAppBar({
    super.key,
    required this.title,
    this.leading,
    this.actions = const [],
  });
  final Widget title;
  final Widget? leading;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => GlassSurface(
    radius: 22,
    child: SizedBox(
      height: 56,
      child: Row(
        children: [
          if (leading != null) leading!,
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: title,
            ),
          ),
          ...actions,
        ],
      ),
    ),
  );
}

class GlassSnackBar {
  const GlassSnackBar._();

  static SnackBar create({
    required Widget content,
    Duration duration = const Duration(seconds: 3),
    SnackBarAction? action,
  }) => SnackBar(
    content: GlassSurface(
      radius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: content,
    ),
    duration: duration,
    behavior: SnackBarBehavior.floating,
    action: action,
    backgroundColor: Colors.transparent,
    elevation: 0,
    padding: EdgeInsets.zero,
    margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
  );
}

class AmbientBackground extends StatelessWidget {
  const AmbientBackground({
    super.key,
    required this.color,
    required this.child,
  });
  final Color color;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          color.withValues(alpha: .16),
          Theme.of(context).scaffoldBackgroundColor,
        ],
        stops: const [0, .72],
      ),
    ),
    child: child,
  );
}

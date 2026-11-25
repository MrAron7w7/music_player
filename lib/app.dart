import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'core/theme/glass/glass_quality.dart';
import 'presentation/widgets/home_widget_sync.dart';
import 'presentation/widgets/permission_onboarding.dart';
import 'presentation/widgets/update_check_host.dart';
import 'router/app_router.dart';

class MusicApp extends ConsumerWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final glassPreference = ref.watch(glassQualityProvider);
    final glassLevel = glassPreference == GlassQuality.automatic
        ? ref.watch(adaptiveGlassQualityProvider)
        : glassPreference;
    final snackAlpha = switch (glassLevel) {
      GlassQuality.high => .90,
      GlassQuality.medium || GlassQuality.automatic => .95,
      GlassQuality.low => .98,
      GlassQuality.off => 1.0,
    };
    ThemeData glassAwareTheme(ThemeData base) => base.copyWith(
      snackBarTheme: base.snackBarTheme.copyWith(
        backgroundColor: base.colorScheme.surface.withValues(alpha: snackAlpha),
        behavior: SnackBarBehavior.floating,
        elevation: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: base.colorScheme.surface.withValues(alpha: snackAlpha),
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: base.bottomSheetTheme.copyWith(
        backgroundColor: base.colorScheme.surface.withValues(alpha: snackAlpha),
        modalBackgroundColor: base.colorScheme.surface.withValues(
          alpha: snackAlpha,
        ),
        surfaceTintColor: Colors.transparent,
      ),
    );
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'Simple Music',
        debugShowCheckedModeBanner: false,
        theme: glassAwareTheme(AppTheme.light()),
        darkTheme: glassAwareTheme(AppTheme.dark()),
        themeMode: mode,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeInOutCubic,
        routerConfig: appRouter,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          final accessibleTheme = media.highContrast
              ? Theme.of(context).copyWith(
                  snackBarTheme: Theme.of(context).snackBarTheme.copyWith(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                  ),
                  dialogTheme: Theme.of(context).dialogTheme.copyWith(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                  ),
                  bottomSheetTheme: Theme.of(context).bottomSheetTheme.copyWith(
                    backgroundColor: Theme.of(context).colorScheme.surface,
                    modalBackgroundColor: Theme.of(context).colorScheme.surface,
                  ),
                )
              : null;
          // Evita que una escala de texto extrema rompa los layouts sin
          // impedir que el usuario aumente el tamaño de letra.
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 1,
                maxScaleFactor: 1.4,
              ),
            ),
            child: Theme(
              data: accessibleTheme ?? Theme.of(context),
              child: HomeWidgetSync(
                child: PermissionOnboarding(
                  child: UpdateCheckHost(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'presentation/widgets/home_widget_sync.dart';
import 'presentation/widgets/permission_onboarding.dart';
import 'presentation/widgets/update_check_host.dart';
import 'router/app_router.dart';

class MusicApp extends StatelessWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'Simple Music',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: mode,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeInOutCubic,
        routerConfig: appRouter,
        builder: (context, child) {
          final media = MediaQuery.of(context);
          // Evita que una escala de texto extrema rompa los layouts sin
          // impedir que el usuario aumente el tamaño de letra.
          return MediaQuery(
            data: media.copyWith(
              textScaler: media.textScaler.clamp(
                minScaleFactor: 1,
                maxScaleFactor: 1.4,
              ),
            ),
            child: HomeWidgetSync(
              child: PermissionOnboarding(
                child: UpdateCheckHost(child: child ?? const SizedBox.shrink()),
              ),
            ),
          );
        },
      ),
    );
  }
}

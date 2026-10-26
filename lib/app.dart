import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/app_theme.dart';
import 'presentation/widgets/home_widget_sync.dart';
import 'presentation/widgets/permission_onboarding.dart';
import 'presentation/widgets/update_check_host.dart';
import 'providers/player_providers.dart';
import 'router/app_router.dart';

class MusicApp extends ConsumerWidget {
  const MusicApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albumColor = ref.watch(
      albumArtColorProvider.select((state) => state.valueOrNull),
    );
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: AppTheme.themeMode,
      builder: (context, mode, _) => MaterialApp.router(
        title: 'Simple Music',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(albumColor),
        darkTheme: AppTheme.dark(albumColor),
        themeMode: mode,
        themeAnimationDuration: const Duration(milliseconds: 300),
        themeAnimationCurve: Curves.easeInOutCubic,
        routerConfig: appRouter,
        builder: (context, child) => HomeWidgetSync(
          child: PermissionOnboarding(
            child: UpdateCheckHost(child: child ?? const SizedBox.shrink()),
          ),
        ),
      ),
    );
  }
}

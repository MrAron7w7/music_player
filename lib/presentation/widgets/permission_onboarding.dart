import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/utils/notification_permissions.dart';
import '../../providers/library_providers.dart';
import '../../router/app_router.dart';

/// Muestra una invitación amable a activar las notificaciones al arrancar.
///
/// Se muestra como máximo una vez por sesión. Si el usuario la rechaza, la
/// reproducción sigue funcionando y se vuelve a pedir de forma contextual.
class PermissionOnboarding extends ConsumerStatefulWidget {
  const PermissionOnboarding({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<PermissionOnboarding> createState() =>
      _PermissionOnboardingState();
}

class _PermissionOnboardingState extends ConsumerState<PermissionOnboarding> {
  static const _cooldown = Duration(days: 7);
  static const _promptKey = 'notificationPromptAt';
  static bool _promptedThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_maybePrompt());
    });
  }

  Future<void> _maybePrompt() async {
    if (_promptedThisSession || !mounted) return;
    _promptedThisSession = true;
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

    try {
      final status = await notificationPermissionStatus();
      if (status.isGranted || status.isLimited) return;
      if (status.isPermanentlyDenied || status.isRestricted) return;

      final settings = ref.read(localRepositoryProvider).settings;
      final lastPrompt = settings.get(_promptKey);
      final lastPromptMs = lastPrompt is int ? lastPrompt : null;
      if (lastPromptMs != null &&
          DateTime.now().millisecondsSinceEpoch - lastPromptMs <
              _cooldown.inMilliseconds) {
        return;
      }

      final navigatorContext = await _waitForNavigator();
      if (navigatorContext == null || !mounted || !navigatorContext.mounted) {
        return;
      }

      final accepted = await _showPermissionDialog(navigatorContext);
      await settings.put(_promptKey, DateTime.now().millisecondsSinceEpoch);
      if (accepted != true || !mounted) return;

      final granted = await requestNotificationPermission();
      if (!mounted || !navigatorContext.mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(navigatorContext);
      if (granted) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Notificaciones activadas')),
        );
        return;
      }

      final current = await notificationPermissionStatus();
      final blocked = current.isPermanentlyDenied || current.isRestricted;
      messenger?.showSnackBar(
        SnackBar(
          content: Text(
            blocked
                ? 'Activa las notificaciones desde Ajustes para ver los controles.'
                : 'Puedes activar las notificaciones más tarde desde Ajustes.',
          ),
          action: blocked
              ? SnackBarAction(
                  label: 'Ajustes',
                  onPressed: () {
                    openAppSettings();
                  },
                )
              : null,
        ),
      );
    } catch (error) {
      debugPrint('No se pudo mostrar la invitación de permisos: $error');
    }
  }

  Future<BuildContext?> _waitForNavigator() async {
    for (var i = 0; i < 20; i++) {
      final context = rootNavigatorKey.currentContext;
      if (context != null) return context;
      await Future<void>.delayed(const Duration(milliseconds: 30));
      if (!mounted) return null;
    }
    return null;
  }

  Future<bool?> _showPermissionDialog(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: Container(
          constraints: const BoxConstraints(maxWidth: 420),
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.surface, colors.surfaceContainerHigh],
            ),
            border: Border.all(color: colors.onSurface.withValues(alpha: .07)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: .38),
                blurRadius: 48,
                offset: const Offset(0, 22),
              ),
            ],
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: .35),
                          blurRadius: 26,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        fit: BoxFit.cover,
                        filterQuality: FilterQuality.high,
                        semanticLabel: 'Simple Music',
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Que la música no se detenga',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.4,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Permite las notificaciones para disfrutar de Simple Music al máximo.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colors.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                const _PermissionReason(
                  icon: Icons.play_circle_outline_rounded,
                  text: 'Controles en la notificación y pantalla de bloqueo',
                  highlight: true,
                ),
                const SizedBox(height: 12),
                const _PermissionReason(
                  icon: Icons.graphic_eq_rounded,
                  text: 'Reproducción estable en segundo plano',
                ),
                const SizedBox(height: 12),
                const _PermissionReason(
                  icon: Icons.tune_rounded,
                  text: 'Solo se usa para los controles de reproducción',
                ),
                const SizedBox(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(dialogContext, false),
                        child: const Text('Ahora no'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(dialogContext, true),
                        style: FilledButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                        child: const Text('Permitir notificaciones'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'No accedemos a tus archivos ni a tus contactos.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant.withValues(alpha: .8),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Puedes cambiarlo cuando quieras en Ajustes.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colors.onSurfaceVariant.withValues(alpha: .8),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _PermissionReason extends StatelessWidget {
  const _PermissionReason({
    required this.icon,
    required this.text,
    this.highlight = false,
  });

  final IconData icon;
  final String text;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: highlight ? .16 : .09),
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(
            icon,
            size: 18,
            color: colors.primary.withValues(alpha: highlight ? 1 : .8),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 7),
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                height: 1.35,
                fontWeight: highlight ? FontWeight.w600 : FontWeight.w500,
                color: colors.onSurface.withValues(alpha: .9),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

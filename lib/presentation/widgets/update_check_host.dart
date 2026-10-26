import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/update_providers.dart';
import '../../router/app_router.dart';
import 'update_dialog.dart';

/// Comprueba actualizaciones una vez por sesión, sin bloquear el arranque.
class UpdateCheckHost extends ConsumerStatefulWidget {
  const UpdateCheckHost({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<UpdateCheckHost> createState() => _UpdateCheckHostState();
}

class _UpdateCheckHostState extends ConsumerState<UpdateCheckHost> {
  static bool _checkedThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_checkForUpdates());
    });
  }

  Future<void> _checkForUpdates() async {
    if (_checkedThisSession) return;
    _checkedThisSession = true;

    // Deja que el primer frame y la navegación inicial terminen.
    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;

    try {
      final update = await ref.read(updateServiceProvider).checkForUpdate();
      if (update == null || !mounted) return;
      final navigatorContext = await _waitForNavigator();
      if (navigatorContext == null || !mounted) return;
      if (!navigatorContext.mounted) return;
      await showUpdateDialog(navigatorContext, update);
    } catch (error) {
      // Una actualización no disponible nunca debe afectar al uso de la app.
      debugPrint('No se pudo comprobar la actualización: $error');
    }
  }

  Future<BuildContext?> _waitForNavigator() async {
    for (var i = 0; i < 20; i++) {
      final context = rootNavigatorKey.currentContext;
      if (context != null) return context;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (!mounted) return null;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

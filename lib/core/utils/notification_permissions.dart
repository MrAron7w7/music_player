import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

/// Estado actual del permiso de notificaciones.
Future<PermissionStatus> notificationPermissionStatus() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
    return PermissionStatus.granted;
  }
  try {
    return await Permission.notification.status;
  } catch (_) {
    return PermissionStatus.granted;
  }
}

/// Pide el permiso de notificaciones de forma directa.
///
/// Devuelve `true` si el usuario lo concedió. La reproducción funciona igual
/// aunque se rechace, solo se pierden los controles en la notificación.
Future<bool> requestNotificationPermission() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return true;
  try {
    var status = await Permission.notification.status;
    if (status.isGranted || status.isLimited) return true;
    if (status.isPermanentlyDenied || status.isRestricted) return false;
    status = await Permission.notification.request();
    return status.isGranted || status.isLimited;
  } catch (_) {
    return false;
  }
}

/// Pide el permiso en el momento de reproducir.
///
/// Si el usuario lo bloqueó definitivamente se muestra una acción para abrir
/// los ajustes del sistema, sin interrumpir la reproducción.
Future<void> requestPlaybackNotificationPermission({
  BuildContext? context,
}) async {
  final granted = await requestNotificationPermission();
  if (granted || context == null || !context.mounted) return;

  final status = await notificationPermissionStatus();
  final blocked = status.isPermanentlyDenied || status.isRestricted;
  if (!blocked || !context.mounted) return;

  final messenger = ScaffoldMessenger.maybeOf(context);
  messenger?.showSnackBar(
    SnackBar(
      content: const Text(
        'Activa las notificaciones para controlar la música desde la barra de estado.',
      ),
      action: SnackBarAction(
        label: 'Ajustes',
        onPressed: () {
          openAppSettings();
        },
      ),
    ),
  );
}

/// Expone el estado del permiso para la pantalla de ajustes.
final notificationPermissionProvider = FutureProvider<bool>((ref) async {
  final status = await notificationPermissionStatus();
  return status.isGranted || status.isLimited;
});

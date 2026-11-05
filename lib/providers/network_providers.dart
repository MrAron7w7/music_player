import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'settings_providers.dart';

/// Detección de conectividad con un pequeño debounce para evitar falsos
/// positivos al cambiar de red. El modo offline manual siempre tiene prioridad.
final networkOfflineProvider = StreamProvider<bool>((ref) {
  final connectivity = Connectivity();
  return (() async* {
    try {
      final initial = await connectivity.checkConnectivity();
      yield initial.every((result) => result == ConnectivityResult.none);
    } catch (_) {
      yield false;
    }
    await for (final results in connectivity.onConnectivityChanged) {
      await Future<void>.delayed(const Duration(milliseconds: 700));
      yield results.every((result) => result == ConnectivityResult.none);
    }
  })();
});

/// `true` si el modo offline manual está activo o no hay conexión.
final effectiveOfflineProvider = Provider<bool>((ref) {
  if (ref.watch(offlineModeProvider)) return true;
  return ref.watch(networkOfflineProvider).valueOrNull == true;
});

/// `true` solo cuando el usuario activó el modo offline manualmente (para
/// ofrecer “Desactivar modo offline” sin confundirlo con una caída de red).
final manualOfflineProvider = Provider<bool>(
  (ref) => ref.watch(offlineModeProvider),
);

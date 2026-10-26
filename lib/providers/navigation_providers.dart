import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pestaña visible en la navegación principal.
///
/// Permite que las pantallas que viven dentro del `IndexedStack` no mantengan
/// activas búsquedas, recomendaciones ni escaneos de caché cuando no se ven.
final selectedTabProvider = StateProvider<int>((ref) => 0);

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/app_cache.dart';
import '../data/services/audio_cache_service.dart';

/// Caché persistente de metadatos, búsquedas, letras y colores.
final appCacheProvider = Provider<AppCache>(
  (ref) => throw UnimplementedError('AppCache no inicializado'),
);

/// Caché de archivos de audio recientes.
final audioCacheProvider = Provider<AudioCacheService>(
  (ref) => throw UnimplementedError('AudioCacheService no inicializado'),
);

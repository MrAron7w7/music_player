import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/download_service.dart';
import '../data/services/listening_stats_service.dart';

final downloadServiceProvider = Provider<DownloadService>(
  (ref) => throw UnimplementedError('DownloadService no inicializado'),
);

final downloadsProvider = StreamProvider<List<DownloadEntry>>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return (() async* {
    yield service.entries;
    yield* service.stream;
  })();
});

final downloadProgressProvider = StreamProvider<Map<String, double>>((ref) {
  final service = ref.watch(downloadServiceProvider);
  return (() async* {
    yield service.progress;
    yield* service.progressStream;
  })();
});

/// Estado de descarga aislado por canción.
///
/// Antes cada fila observaba la lista y el mapa de progreso completos, así que
/// un solo cambio reconstruía todas las filas visibles. Con `family` solo se
/// reconstruye la canción cuyo valor booleano/progreso cambia.
final isDownloadedProvider = Provider.autoDispose.family<bool, String>((
  ref,
  songId,
) {
  final service = ref.watch(downloadServiceProvider);
  return ref.watch(
    downloadsProvider.select((state) {
      final entries = state.valueOrNull;
      if (entries == null) return service.isDownloaded(songId);
      return entries.any((entry) => entry.song.id == songId);
    }),
  );
});

final downloadProgressForProvider = Provider.autoDispose
    .family<double?, String>(
      (ref, songId) => ref.watch(
        downloadProgressProvider.select((state) => state.valueOrNull?[songId]),
      ),
    );

final downloadEntryForProvider = Provider.autoDispose
    .family<DownloadEntry?, String>((ref, songId) {
      final service = ref.watch(downloadServiceProvider);
      return ref.watch(
        downloadsProvider.select((state) {
          final entries = state.valueOrNull ?? service.entries;
          for (final entry in entries) {
            if (entry.song.id == songId) return entry;
          }
          return null;
        }),
      );
    });

final statsServiceProvider = Provider<ListeningStatsService>(
  (ref) => throw UnimplementedError('ListeningStatsService no inicializado'),
);

final statsProvider = StreamProvider.autoDispose<StatsSnapshot>((ref) {
  final service = ref.watch(statsServiceProvider);
  return (() async* {
    yield service.snapshot();
    yield* service.stream;
  })();
});

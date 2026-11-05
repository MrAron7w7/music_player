import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/song_model.dart';
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

/// IDs de canciones descargadas. Usa `select` para no reconstruir la UI cuando
/// solo cambia el progreso de una descarga.
final downloadedSongIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(
    downloadsProvider.select(
      (state) => {
        for (final entry in state.valueOrNull ?? const <DownloadEntry>[])
          entry.song.id,
      },
    ),
  );
});

final downloadedAlbumIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(
    downloadsProvider.select((state) {
      final result = <String>{};
      for (final entry in state.valueOrNull ?? const <DownloadEntry>[]) {
        final albumId = entry.song.albumId;
        if (albumId != null && albumId.isNotEmpty) result.add(albumId);
      }
      return result;
    }),
  );
});

final downloadedArtistIdsProvider = Provider<Set<String>>((ref) {
  return ref.watch(
    downloadsProvider.select((state) {
      final result = <String>{};
      for (final entry in state.valueOrNull ?? const <DownloadEntry>[]) {
        for (final id in entry.song.artistIds ?? const <String>[]) {
          if (id.isNotEmpty) result.add(id);
        }
      }
      return result;
    }),
  );
});

final downloadQualityByIdProvider = Provider<Map<String, String>>((ref) {
  return ref.watch(
    downloadsProvider.select(
      (state) => {
        for (final entry in state.valueOrNull ?? const <DownloadEntry>[])
          entry.song.id: entry.quality,
      },
    ),
  );
});

final downloadedSongsProvider = Provider<List<SongModel>>((ref) {
  return ref.watch(
    downloadsProvider.select(
      (state) => [
        for (final entry in state.valueOrNull ?? const <DownloadEntry>[])
          entry.song,
      ],
    ),
  );
});

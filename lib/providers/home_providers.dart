import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/song_model.dart';
import '../data/services/app_cache.dart';
import '../data/services/listening_stats_service.dart';
import '../data/services/yt_service.dart';
import 'cache_providers.dart';
import 'downloads_providers.dart';
import 'library_providers.dart';
import 'music_providers.dart';
import 'player_providers.dart';

/// Álbum reciente derivado del historial, sin llamadas de red extra.
class RecentAlbum {
  const RecentAlbum({
    required this.id,
    required this.title,
    required this.artist,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String artist;
  final String? coverUrl;
}

/// Sección contextual de Inicio cuando hay una canción sonando.
class ArtistSpotlight {
  const ArtistSpotlight({
    required this.artistId,
    required this.artistName,
    required this.songs,
  });

  final String artistId;
  final String artistName;
  final List<SongModel> songs;
}

/// Recomendaciones personalizadas: combina historial reciente, estadísticas y
/// favoritos, y mezcla canciones relacionadas con radios de los artistas que
/// más escuchas. Se excluyen las canciones ya conocidas para que la sección se
/// sienta fresca y no repita siempre lo mismo.
final homeRecommendationsProvider = FutureProvider.autoDispose<List<SongModel>>((
  ref,
) async {
  final history = ref.watch(historyProvider);
  final favorites = ref.watch(favoritesProvider);

  StatsSnapshot? stats;
  try {
    stats = ref.read(statsServiceProvider).snapshot();
  } catch (_) {
    // En tests o arranques parciales el servicio puede no estar disponible.
  }

  final source = <SongModel>[];
  final sourceIds = <String>{};
  void addSource(Iterable<SongModel> songs) {
    for (final song in songs) {
      if (song.id.isEmpty || !sourceIds.add(song.id)) continue;
      source.add(song);
    }
  }

  addSource(history.take(6));
  addSource(favorites.take(3));
  addSource(
    stats?.topSongs.take(10).map((stat) => stat.song) ?? const <SongModel>[],
  );
  addSource(history.skip(6).take(4));
  if (source.isEmpty) return const [];

  final yt = ref.watch(ytServiceProvider);
  final AppCache cache = ref.watch(appCacheProvider);

  // Una rotación diaria entre las canciones conocidas evita que la Home
  // enseñe exactamente las mismas semillas cada vez.
  final random = math.Random(
    DateTime.now().day * 31 + history.length + favorites.length,
  );
  final seedPool = source.take(8).toList()..shuffle(random);
  final seeds = seedPool.take(3).toList();
  if (seeds.isEmpty) return const [];

  final day = DateTime.now().day;
  final cacheKey =
      'home:recommendations:v3:${seeds.map((song) => song.id).join('|')}:$day';
  final stored = cache.get<List>(cacheKey);
  if (stored != null) {
    final cached = stored
        .whereType<Map>()
        .map((e) => SongModel.fromJson(Map<String, dynamic>.from(e)))
        .where((song) => song.id.isNotEmpty)
        .toList();
    if (cached.isNotEmpty) return cached;
  }

  final artistIds = <String>{};
  for (final song in <SongModel>[
    ...seeds,
    ...(stats?.topSongs.take(8).map((stat) => stat.song) ??
        const <SongModel>[]),
  ]) {
    for (final id in song.artistIds ?? const <String>[]) {
      if (id.isNotEmpty) artistIds.add(id);
      if (artistIds.length >= 2) break;
    }
    if (artistIds.length >= 2) break;
  }

  final relatedBatches = await Future.wait(
    seeds.take(2).map((song) async {
      try {
        return await yt.getRelatedSongs(song.id);
      } catch (_) {
        return <SongModel>[];
      }
    }),
  );
  final artistBatches = await Future.wait(
    artistIds.take(2).map((id) async {
      try {
        return await yt.getArtistRecommendations(id, limit: 14);
      } catch (_) {
        return <SongModel>[];
      }
    }),
  );
  final batches = [...relatedBatches, ...artistBatches];
  if (batches.isEmpty) return const [];

  final excluded = <String>{
    for (final song in history) song.id,
    for (final song in favorites) song.id,
    for (final song in seeds) song.id,
  };
  final seen = <String>{};
  final artistCounts = <String, int>{};
  final albumCounts = <String, int>{};
  final recommendations = <SongModel>[];
  final longest = batches.fold<int>(
    0,
    (length, batch) => batch.length > length ? batch.length : length,
  );

  // Intercala las fuentes y limita repeticiones por artista y álbum para que
  // una sola semilla no domine toda la sección.
  for (var index = 0; index < longest; index++) {
    for (final batch in batches) {
      if (index >= batch.length) continue;
      final song = batch[index];
      if (song.id.isEmpty || excluded.contains(song.id) || !seen.add(song.id)) {
        continue;
      }
      final artistKey = _artistKey(song);
      if (artistKey.isNotEmpty && (artistCounts[artistKey] ?? 0) >= 2) {
        continue;
      }
      final albumKey = song.albumId ?? song.album ?? '';
      if (albumKey.isNotEmpty && (albumCounts[albumKey] ?? 0) >= 2) {
        continue;
      }
      if (artistKey.isNotEmpty) {
        artistCounts[artistKey] = (artistCounts[artistKey] ?? 0) + 1;
      }
      if (albumKey.isNotEmpty) {
        albumCounts[albumKey] = (albumCounts[albumKey] ?? 0) + 1;
      }
      recommendations.add(song);
      if (recommendations.length >= 18) break;
    }
    if (recommendations.length >= 18) break;
  }

  if (recommendations.isNotEmpty) {
    await cache.put(
      cacheKey,
      recommendations.map((song) => song.toJson()).toList(),
      ttl: const Duration(minutes: 45),
      maxEntries: 60,
    );
  }
  return recommendations;
});

/// Sugerencias contextuales para la canción actual: más del artista y
/// artistas parecidos, evitando lo que acaba de sonar.
final artistSpotlightProvider = FutureProvider.autoDispose<ArtistSpotlight?>((
  ref,
) async {
  final current = ref.watch(currentSongProvider).valueOrNull;
  if (current == null || current.id.isEmpty) return null;
  final artistName = current.artists.isNotEmpty
      ? current.artists.first
      : 'tu artista';
  final history = ref.watch(historyProvider);
  final yt = ref.watch(ytServiceProvider);

  var artistId = current.artistIds?.firstOrNull;
  if (artistId == null || artistId.isEmpty) {
    // Canciones antiguas guardadas sin IDs: buscamos el artista una vez.
    try {
      final artists = await yt.searchArtists(artistName);
      artistId = artists.firstOrNull?.id;
    } catch (_) {
      return null;
    }
  }
  if (artistId == null || artistId.isEmpty) return null;

  final excluded = <String>{
    current.id,
    for (final song in history.take(24)) song.id,
  };
  final songs = await _safeArtistRecommendations(yt, artistId);
  final seen = <String>{...excluded};
  final artistCounts = <String, int>{};
  final result = <SongModel>[];

  for (final song in songs) {
    if (result.length >= 12) break;
    if (song.id.isEmpty || !seen.add(song.id)) continue;
    final artistKey = _artistKey(song);
    final sameArtist =
        artistKey.isNotEmpty && artistKey == artistName.trim().toLowerCase();
    final maxForArtist = sameArtist ? 4 : 2;
    if (artistKey.isNotEmpty &&
        (artistCounts[artistKey] ?? 0) >= maxForArtist) {
      continue;
    }
    if (artistKey.isNotEmpty) {
      artistCounts[artistKey] = (artistCounts[artistKey] ?? 0) + 1;
    }
    result.add(song);
  }

  if (result.isEmpty) return null;
  return ArtistSpotlight(
    artistId: artistId,
    artistName: artistName,
    songs: result,
  );
});

String _artistKey(SongModel song) =>
    song.artists.isEmpty ? '' : song.artists.first.trim().toLowerCase();

Future<List<SongModel>> _safeArtistRecommendations(
  YtService yt,
  String artistId,
) async {
  try {
    return await yt.getArtistRecommendations(artistId, limit: 14);
  } catch (_) {
    return const [];
  }
}

/// Álbumes que aparecen en el historial, en orden de escucha reciente.
final homeRecentAlbumsProvider = Provider.autoDispose<List<RecentAlbum>>((ref) {
  final history = ref.watch(historyProvider);
  final albums = <String, RecentAlbum>{};
  for (final song in history) {
    final id = song.albumId;
    if (id == null || id.isEmpty || albums.containsKey(id)) continue;
    albums[id] = RecentAlbum(
      id: id,
      title: song.album?.trim().isNotEmpty == true ? song.album! : 'Álbum',
      artist: song.artists.join(', '),
      coverUrl: song.artworkUrl,
    );
    if (albums.length >= 8) break;
  }
  return albums.values.toList();
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/mix_utils.dart';
import '../data/models/album_model.dart';
import '../data/models/home_models.dart';
import '../data/models/song_model.dart';
import '../data/services/daily_mix_service.dart';
import '../data/services/listening_stats_service.dart';
import 'cache_providers.dart';
import 'downloads_providers.dart';
import 'followed_artists_providers.dart';
import 'home_providers.dart';
import 'library_providers.dart';
import 'music_providers.dart';
import 'network_providers.dart';
import 'search_providers.dart';

final dailyMixServiceProvider = Provider<DailyMixService>(
  (ref) => DailyMixService(ref.watch(ytServiceProvider)),
);

StatsSnapshot _emptyStats() => const StatsSnapshot(
  topSongs: [],
  topArtists: [],
  recent: [],
  totalSeconds: 0,
  todaySeconds: 0,
  weekSeconds: 0,
  monthSeconds: 0,
  totalPlays: 0,
);

/// Mezclas del día: se cachean una vez por fecha. Si no hay red, se reintenta
/// con el último día disponible y, como último recurso, con el pool local.
final dailyMixesProvider = FutureProvider.autoDispose<List<DailyMix>>((ref) async {
  final cache = ref.watch(appCacheProvider);
  final today = DateTime.now();
  for (var offset = 0; offset < 3; offset++) {
    final key = 'home:dailyMixes:${dayKey(today.subtract(Duration(days: offset)))}';
    final stored = cache.getStale<List>(key);
    if (stored == null) continue;
    final mixes = stored
        .whereType<Map>()
        .map((entry) => DailyMix.fromJson(Map<String, dynamic>.from(entry)))
        .where((mix) => mix.songs.isNotEmpty)
        .toList();
    if (mixes.isNotEmpty) return mixes;
  }

  StatsSnapshot stats;
  try {
    stats = ref.read(statsServiceProvider).snapshot();
  } catch (_) {
    stats = _emptyStats();
  }
  final downloads = ref.watch(downloadedSongsProvider);
  final favorites = ref.watch(favoritesProvider);
  final history = ref.watch(historyProvider);
  final offline = ref.watch(effectiveOfflineProvider);
  final service = ref.watch(dailyMixServiceProvider);

  List<DailyMix> mixes;
  try {
    mixes = await service.generate(
      stats: stats,
      favorites: favorites,
      history: history,
      downloads: downloads,
      offline: offline,
    );
  } catch (_) {
    mixes = await service.generate(
      stats: stats,
      favorites: favorites,
      history: history,
      downloads: downloads,
      offline: true,
    );
  }
  if (mixes.isNotEmpty) {
    await cache.put(
      'home:dailyMixes:${dayKey(today)}',
      mixes.map((mix) => mix.toJson()).toList(),
      ttl: const Duration(hours: 30),
      maxEntries: 6,
    );
  }
  return mixes;
});

/// Historial reciente para “Seguir escuchando” y los chips de arriba.
final continueListeningProvider = Provider.autoDispose<List<SongModel>>((ref) {
  final history = ref.watch(historyProvider);
  final seen = <String>{};
  final result = <SongModel>[];
  for (final song in history) {
    if (song.id.isEmpty || !seen.add(song.id)) continue;
    result.add(song);
    if (result.length >= 12) break;
  }
  return result;
});

final recentChipsProvider = Provider.autoDispose<List<SongModel>>(
  (ref) => ref.watch(continueListeningProvider).take(4).toList(),
);

/// “Porque escuchaste…”: usa el último artista del historial. Si no hay red,
/// cae al pool local sin bloquear el resto de Inicio.
final becauseYouListenedProvider =
    FutureProvider.autoDispose<BecauseYouListened?>((ref) async {
      final history = ref.watch(historyProvider);
      final stats = ref.watch(statsProvider).valueOrNull;
      final favorites = ref.watch(favoritesProvider);
      final downloads = ref.watch(downloadedSongsProvider);

      SongModel? seed;
      for (final song in history) {
        if (song.artists.isEmpty) continue;
        seed = song;
        break;
      }
      if (seed == null && stats != null && stats.topSongs.isNotEmpty) {
        seed = stats.topSongs.first.song;
      }
      if (seed == null) return null;

      final artistName = seed.artists.isNotEmpty
          ? seed.artists.first
          : 'tu artista';
      final localService = ref.watch(localSearchServiceProvider);
      final pool = uniqueSongs([...downloads, ...favorites, ...history]);
      final localSongs = localService.relatedLocal(
        pool,
        seed,
        limit: 18,
        excludeIds: {seed.id},
      );

      if (ref.watch(effectiveOfflineProvider)) {
        if (localSongs.isEmpty) return null;
        return BecauseYouListened(
          seedArtistId: seed.artistIds?.firstOrNull ?? '',
          seedArtistName: artistName,
          songs: localSongs.take(12).toList(),
          isOffline: true,
        );
      }

      final yt = ref.watch(ytServiceProvider);
      final remote = <SongModel>[];
      try {
        final artistId = seed.artistIds?.firstOrNull;
        if (artistId != null && artistId.isNotEmpty) {
          remote.addAll(await yt.getArtistSongs(artistId));
        } else {
          remote.addAll(await yt.getRelatedSongs(seed.id));
        }
      } catch (_) {
        // El fallback local ya está preparado.
      }

      final songs = interleaveBalanced(
        [remote, localSongs],
        limit: 12,
        excludeIds: {seed.id},
      );
      if (songs.isEmpty) return null;
      return BecauseYouListened(
        seedArtistId: seed.artistIds?.firstOrNull ?? '',
        seedArtistName: artistName,
        songs: songs,
      );
    });

/// Novedades de los artistas seguidos. Cada artista falla de forma aislada.
final followedReleasesProvider = FutureProvider.autoDispose<List<AlbumModel>>((
  ref,
) async {
  final followed = ref.watch(followedArtistsProvider);
  if (followed.isEmpty || ref.watch(effectiveOfflineProvider)) return const [];
  final yt = ref.watch(ytServiceProvider);
  final batches = await Future.wait(
    followed.take(6).map((artist) async {
      try {
        final page = await yt.getArtistPage(artist.id);
        return page.albumes;
      } catch (_) {
        return <AlbumModel>[];
      }
    }),
  );
  final seen = <String>{};
  final albums = <AlbumModel>[];
  for (final batch in batches) {
    for (final album in batch) {
      if (album.id.isEmpty || !seen.add(album.id)) continue;
      albums.add(album);
    }
  }
  albums.sort((a, b) => (b.year ?? 0).compareTo(a.year ?? 0));
  return albums.take(18).toList();
});

/// Álbumes del historial, ya tipados para la sección de Inicio.
final recentAlbumsProvider = Provider.autoDispose<List<RecentAlbum>>(
  (ref) => ref.watch(homeRecentAlbumsProvider),
);

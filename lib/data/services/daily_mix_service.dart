import 'dart:math' as math;

import '../../core/utils/mix_utils.dart';
import '../models/home_models.dart';
import '../models/song_model.dart';
import 'listening_stats_service.dart';
import 'yt_service.dart';

/// Genera tres mezclas diarias deterministas a partir de estadísticas locales y
/// recomendaciones de YouTube Music. La caché por fecha vive en el provider.
class DailyMixService {
  DailyMixService(this.yt);

  final YtService yt;

  Future<List<DailyMix>> generate({
    required StatsSnapshot stats,
    required List<SongModel> favorites,
    required List<SongModel> history,
    required List<SongModel> downloads,
    required bool offline,
    DateTime? now,
  }) async {
    final moment = now ?? DateTime.now();
    final seedValue = dailySeed(moment);
    final pool = _localPool(downloads, favorites, history, stats);
    final songsById = <String, SongModel>{};
    for (final song in pool) {
      songsById[song.id] = song;
    }

    if (offline) {
      return _offlineMixes(pool, moment, seedValue);
    }

    final seeds = _buildSeeds(stats, favorites, history, pool);
    if (seeds.isEmpty) {
      return _offlineMixes(pool, moment, seedValue);
    }

    final used = <String>{};
    final mixes = <DailyMix>[];
    for (var index = 0; index < 3; index++) {
      final seed = seeds[index % seeds.length];
      List<SongModel> candidates = const [];
      if (seed.artistId != null && seed.artistId!.isNotEmpty) {
        try {
          candidates = await yt.getArtistRadioSongs(
            seed.artistId!,
            limit: 30,
          );
        } catch (_) {
          candidates = const [];
        }
      }
      if (candidates.isEmpty && seed.song != null) {
        try {
          candidates = await yt.getRelatedSongs(seed.song!.id);
        } catch (_) {
          candidates = const [];
        }
      }

      final excluded = <String>{
        ...used,
        if (seed.song != null) seed.song!.id,
      };
      final balanced = interleaveBalanced(
        [candidates],
        limit: 25,
        excludeIds: excluded,
      );
      final songs = fillMix(
        balanced,
        shuffleDeterministic(pool, seedValue + index * 31),
        target: 25,
        excludeIds: excluded,
      );
      if (songs.length < 5) continue;
      used.addAll(songs.map((song) => song.id));

      final artistName = seed.artistName?.trim();
      mixes.add(
        DailyMix(
          id: 'mix-${dayKey(moment)}-${mixes.length + 1}',
          title: artistName != null && artistName.isNotEmpty
              ? 'Mix de $artistName'
              : 'Mix ${mixes.length + 1}',
          subtitle: artistName != null && artistName.isNotEmpty
              ? 'Porque te gusta $artistName · ${songs.length} canciones'
              : 'Hecho para ti · ${songs.length} canciones',
          coverUrls: coverUrlsFor(songs),
          songs: songs,
          generatedAt: moment,
          seedArtist: artistName,
        ),
      );
      if (mixes.length >= 3) break;
    }

    if (mixes.isEmpty) {
      return _offlineMixes(pool, moment, seedValue);
    }
    return mixes;
  }

  List<DailyMix> _offlineMixes(
    List<SongModel> pool,
    DateTime moment,
    int seedValue,
  ) {
    if (pool.length < 5) return const [];
    final shuffled = shuffleDeterministic(pool, seedValue);
    final maxMixes = math.min(3, shuffled.length ~/ 5);
    if (maxMixes <= 0) return const [];
    final perMix = (shuffled.length / maxMixes).floor().clamp(5, 25);
    final result = <DailyMix>[];
    for (var index = 0; index < maxMixes; index++) {
      final start = index * perMix;
      if (start >= shuffled.length) break;
      final songs = shuffled.skip(start).take(perMix).toList();
      final seedArtist = songs.first.artists.isNotEmpty
          ? songs.first.artists.first
          : null;
      result.add(
        DailyMix(
          id: 'mix-${dayKey(moment)}-${index + 1}',
          title: seedArtist != null
              ? 'Mix de $seedArtist'
              : 'Mix ${index + 1}',
          subtitle: 'Offline · ${songs.length} canciones',
          coverUrls: coverUrlsFor(songs),
          songs: songs,
          generatedAt: moment,
          isOffline: true,
          seedArtist: seedArtist,
        ),
      );
    }
    return result;
  }

  List<SongModel> _localPool(
    List<SongModel> downloads,
    List<SongModel> favorites,
    List<SongModel> history,
    StatsSnapshot stats,
  ) {
    final seen = <String>{};
    final pool = <SongModel>[];
    void add(Iterable<SongModel> songs) {
      for (final song in songs) {
        if (song.id.isEmpty || !seen.add(song.id)) continue;
        pool.add(song);
      }
    }

    add(downloads);
    add(favorites);
    add(stats.topSongs.map((stat) => stat.song));
    add(history);
    return pool;
  }

  List<_MixSeed> _buildSeeds(
    StatsSnapshot stats,
    List<SongModel> favorites,
    List<SongModel> history,
    List<SongModel> pool,
  ) {
    final idsByName = <String, String>{};
    for (final song in pool) {
      final names = song.artists;
      final ids = song.artistIds ?? const <String>[];
      for (var index = 0; index < names.length; index++) {
        if (index < ids.length && ids[index].isNotEmpty) {
          idsByName.putIfAbsent(names[index], () => ids[index]);
        }
      }
    }

    final seeds = <_MixSeed>[];
    for (final artist in stats.topArtists.take(3)) {
      seeds.add(
        _MixSeed(
          artistId: idsByName[artist.name],
          artistName: artist.name,
        ),
      );
    }
    for (final stat in stats.topSongs.take(3)) {
      final song = stat.song;
      seeds.add(
        _MixSeed(
          song: song,
          artistId: song.artistIds?.firstOrNull,
          artistName: song.artists.isNotEmpty ? song.artists.first : null,
        ),
      );
    }
    if (seeds.isEmpty) {
      final source = [...favorites, ...history];
      for (final song in source.take(3)) {
        seeds.add(
          _MixSeed(
            song: song,
            artistId: song.artistIds?.firstOrNull,
            artistName: song.artists.isNotEmpty ? song.artists.first : null,
          ),
        );
      }
    }
    // Elimina semillas repetidas sin id ni canción.
    final unique = <String>{};
    return seeds.where((seed) {
      final key = seed.artistId ?? seed.song?.id ?? seed.artistName ?? '';
      return key.isNotEmpty && unique.add(key);
    }).toList();
  }
}

class _MixSeed {
  const _MixSeed({this.artistId, this.artistName, this.song});

  final String? artistId;
  final String? artistName;
  final SongModel? song;
}

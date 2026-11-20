import 'package:hive/hive.dart';

import '../models/song_model.dart';
import '../repositories/music_repository.dart';
import '../../core/utils/song_variant_utils.dart';
import 'listening_stats_service.dart';

/// Construye recomendaciones sin mutar el estado de reproducción.
class SmartQueueService {
  SmartQueueService({
    required this.repository,
    this.stats,
    this.history,
    this.favorites,
  });

  final MusicRepository repository;
  final ListeningStatsService? stats;
  final Box? history;
  final Box? favorites;

  Future<List<SongModel>> recommendations({
    required SongModel seed,
    required List<SongModel> queuedSongs,
    int limit = 24,
  }) async {
    final recentSongs = <SongModel>[];
    final recentIds = <String>{};
    try {
      final entries = history?.values.whereType<Map>().toList().reversed.take(
        14,
      );
      for (final entry in entries ?? const <Map>[]) {
        try {
          final song = SongModel.fromJson(Map<String, dynamic>.from(entry));
          final id = song.id.isNotEmpty
              ? song.id
              : '${entry['id'] ?? entry['videoId'] ?? ''}';
          if (id.isNotEmpty) recentIds.add(id);
          if (song.id.isNotEmpty) recentSongs.add(song);
        } catch (_) {
          final id = '${entry['id'] ?? entry['videoId'] ?? ''}';
          if (id.isNotEmpty) recentIds.add(id);
        }
      }
    } catch (_) {}

    final recentTitles = recentSongs
        .map((song) => songTitleKey(song.title))
        .where((key) => key.isNotEmpty)
        .toSet();
    final queuedIds = queuedSongs.map((song) => song.id).toSet();
    final queuedTitles = queuedSongs
        .map((song) => songTitleKey(song.title))
        .where((key) => key.isNotEmpty)
        .toSet();
    final seedTitle = songTitleKey(seed.title);

    final candidates = await repository.yt.getSmartQueue(
      seed,
      excludeIds: {...queuedIds, ...recentIds},
      excludeTitleKeys: {
        ...queuedTitles,
        ...recentTitles,
        if (seedTitle.isNotEmpty) seedTitle,
      },
      preferredArtistIds: _preferredArtistIds(seed),
      limit: limit,
    );
    return filterSongVariants(
      candidates,
      excludeIds: queuedIds,
      excludeTitleKeys: {...queuedTitles, ...recentTitles},
      reference: seed,
      limit: limit,
    );
  }

  List<String> _preferredArtistIds(SongModel seed) {
    final result = <String>[];
    final seedArtists = seed.artistIds?.toSet() ?? const <String>{};

    void add(String? id) {
      if (id == null ||
          id.isEmpty ||
          seedArtists.contains(id) ||
          result.contains(id)) {
        return;
      }
      result.add(id);
    }

    try {
      final snapshot = stats?.snapshot();
      if (snapshot != null) {
        final idsByName = <String, String>{};
        for (final stat in snapshot.topSongs) {
          final names = stat.song.artists;
          final ids = stat.song.artistIds ?? const <String>[];
          for (
            var index = 0;
            index < names.length && index < ids.length;
            index++
          ) {
            idsByName.putIfAbsent(names[index], () => ids[index]);
          }
        }
        for (final artist in snapshot.topArtists) {
          add(idsByName[artist.name]);
          if (result.length == 2) break;
        }
        if (result.length < 2) {
          for (final stat in snapshot.topSongs) {
            for (final id in stat.song.artistIds ?? const <String>[]) {
              add(id);
              if (result.length == 2) break;
            }
            if (result.length == 2) break;
          }
        }
      }
      if (result.length < 2 && favorites != null) {
        for (final value in favorites!.values) {
          if (value is! Map) continue;
          try {
            final song = SongModel.fromJson(Map<String, dynamic>.from(value));
            for (final id in song.artistIds ?? const <String>[]) {
              add(id);
              if (result.length == 2) break;
            }
          } catch (_) {}
          if (result.length == 2) break;
        }
      }
      if (result.length < 2 && history != null) {
        for (final entry
            in history!.values.whereType<Map>().toList().reversed.take(30)) {
          try {
            final song = SongModel.fromJson(Map<String, dynamic>.from(entry));
            for (final id in song.artistIds ?? const <String>[]) {
              add(id);
              if (result.length == 2) break;
            }
          } catch (_) {}
          if (result.length == 2) break;
        }
      }
    } catch (_) {}
    return result;
  }
}

import 'dart:math' as math;

import '../../data/models/song_model.dart';

String songArtistKey(SongModel song) =>
    song.artists.isEmpty ? '' : song.artists.first.trim().toLowerCase();

String songAlbumKey(SongModel song) {
  final id = song.albumId;
  if (id != null && id.isNotEmpty) return id;
  return song.album?.trim().toLowerCase() ?? '';
}

/// Deduplica por id conservando el primer orden.
List<SongModel> uniqueSongs(Iterable<SongModel> songs, {Set<String>? seen}) {
  final used = seen ?? <String>{};
  final result = <SongModel>[];
  for (final song in songs) {
    if (song.id.isEmpty || !used.add(song.id)) continue;
    result.add(song);
  }
  return result;
}

/// Intercala varias listas y limita repeticiones por artista y álbum para que
/// una sola semilla no domine el resultado.
List<SongModel> interleaveBalanced(
  List<List<SongModel>> batches, {
  int limit = 20,
  int maxPerArtist = 2,
  int maxPerAlbum = 2,
  Set<String> excludeIds = const {},
  Set<String>? seenIds,
}) {
  if (limit <= 0) return const [];
  final seen = <String>{...excludeIds, ...?seenIds};
  final artistCounts = <String, int>{};
  final albumCounts = <String, int>{};
  final result = <SongModel>[];
  final longest = batches.fold<int>(
    0,
    (length, batch) => batch.length > length ? batch.length : length,
  );

  void consider(SongModel song) {
    if (result.length >= limit) return;
    if (song.id.isEmpty || seen.contains(song.id)) return;
    final artistKey = songArtistKey(song);
    if (artistKey.isNotEmpty &&
        (artistCounts[artistKey] ?? 0) >= maxPerArtist) {
      return;
    }
    final albumKey = songAlbumKey(song);
    if (albumKey.isNotEmpty && (albumCounts[albumKey] ?? 0) >= maxPerAlbum) {
      return;
    }
    seen.add(song.id);
    if (artistKey.isNotEmpty) {
      artistCounts[artistKey] = (artistCounts[artistKey] ?? 0) + 1;
    }
    if (albumKey.isNotEmpty) {
      albumCounts[albumKey] = (albumCounts[albumKey] ?? 0) + 1;
    }
    result.add(song);
  }

  for (var index = 0; index < longest && result.length < limit; index++) {
    for (final batch in batches) {
      if (index >= batch.length) continue;
      consider(batch[index]);
      if (result.length >= limit) break;
    }
  }
  if (result.length < limit) {
    for (final batch in batches) {
      for (final song in batch) {
        consider(song);
        if (result.length >= limit) break;
      }
      if (result.length >= limit) break;
    }
  }
  return result;
}

/// Añade canciones de relleno respetando los límites de variedad.
List<SongModel> fillMix(
  List<SongModel> base,
  Iterable<SongModel> pool, {
  int target = 25,
  int maxPerArtist = 2,
  int maxPerAlbum = 2,
  Set<String> excludeIds = const {},
}) {
  final seen = <String>{
    ...base.map((song) => song.id),
    ...excludeIds,
  };
  final artistCounts = <String, int>{};
  final albumCounts = <String, int>{};
  for (final song in base) {
    final artistKey = songArtistKey(song);
    if (artistKey.isNotEmpty) {
      artistCounts[artistKey] = (artistCounts[artistKey] ?? 0) + 1;
    }
    final albumKey = songAlbumKey(song);
    if (albumKey.isNotEmpty) {
      albumCounts[albumKey] = (albumCounts[albumKey] ?? 0) + 1;
    }
  }
  final result = List<SongModel>.from(base);
  for (final song in pool) {
    if (result.length >= target) break;
    if (song.id.isEmpty || seen.contains(song.id)) continue;
    final artistKey = songArtistKey(song);
    if (artistKey.isNotEmpty &&
        (artistCounts[artistKey] ?? 0) >= maxPerArtist) {
      continue;
    }
    final albumKey = songAlbumKey(song);
    if (albumKey.isNotEmpty && (albumCounts[albumKey] ?? 0) >= maxPerAlbum) {
      continue;
    }
    seen.add(song.id);
    if (artistKey.isNotEmpty) {
      artistCounts[artistKey] = (artistCounts[artistKey] ?? 0) + 1;
    }
    if (albumKey.isNotEmpty) {
      albumCounts[albumKey] = (albumCounts[albumKey] ?? 0) + 1;
    }
    result.add(song);
  }
  // Si aún falta, relajamos los límites para no dejar mixes diminutos.
  if (result.length < target) {
    for (final song in pool) {
      if (result.length >= target) break;
      if (song.id.isEmpty || !seen.add(song.id)) continue;
      result.add(song);
    }
  }
  return result;
}

List<SongModel> shuffleDeterministic(
  Iterable<SongModel> songs,
  int seed,
) {
  final result = List<SongModel>.from(songs);
  result.shuffle(math.Random(seed));
  return result;
}

int dailySeed(DateTime date, [int salt = 0]) =>
    date.year * 10000 + date.month * 100 + date.day + salt * 7919;

String dayKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-'
    '${date.day.toString().padLeft(2, '0')}';

List<String> coverUrlsFor(Iterable<SongModel> songs, {int limit = 4}) {
  final result = <String>[];
  final seen = <String>{};
  for (final song in songs) {
    final url = song.artworkUrl;
    if (url == null || url.isEmpty || !seen.add(url)) continue;
    result.add(url);
    if (result.length >= limit) break;
  }
  return result;
}

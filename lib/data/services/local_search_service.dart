import 'dart:math' as math;

import '../../core/utils/text_utils.dart';
import '../models/playlist_model.dart';
import '../models/song_model.dart';

enum LocalSongSource { downloaded, favorite, history, playlist }

class IndexedSong {
  IndexedSong({
    required this.song,
    required this.sources,
    required this.normalizedTitle,
    required this.normalizedArtist,
    required this.normalizedAlbum,
    this.playlistNames = const [],
  });

  final SongModel song;
  final Set<LocalSongSource> sources;
  final String normalizedTitle;
  final String normalizedArtist;
  final String normalizedAlbum;
  final List<String> playlistNames;

  bool get isDownloaded => sources.contains(LocalSongSource.downloaded);

  int get sourcePriority {
    if (sources.contains(LocalSongSource.downloaded)) return 4;
    if (sources.contains(LocalSongSource.favorite)) return 3;
    if (sources.contains(LocalSongSource.history)) return 2;
    return 1;
  }
}

class IndexedAlbum {
  IndexedAlbum({
    required this.id,
    required this.title,
    required this.artist,
    required this.songs,
    this.coverUrl,
    this.year,
    this.downloaded = false,
  });

  final String id;
  final String title;
  final String artist;
  final List<SongModel> songs;
  final String? coverUrl;
  final int? year;
  final bool downloaded;

  bool get isDownloaded => downloaded;
}

class IndexedArtist {
  IndexedArtist({
    required this.id,
    required this.name,
    required this.songs,
    this.imageUrl,
    this.downloaded = false,
  });

  final String id;
  final String name;
  final List<SongModel> songs;
  final String? imageUrl;
  final bool downloaded;
}

class IndexedPlaylist {
  IndexedPlaylist(this.playlist)
    : normalizedName = normalize(playlist.name),
      normalizedSongs = normalize(
        playlist.songs.map((song) => song.title).join(' '),
      );

  final PlaylistModel playlist;
  final String normalizedName;
  final String normalizedSongs;
}

class LocalSearchIndex {
  const LocalSearchIndex({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
  });

  final List<IndexedSong> songs;
  final List<IndexedAlbum> albums;
  final List<IndexedArtist> artists;
  final List<IndexedPlaylist> playlists;

  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  Map<String, int> get playCounts => const {};

  Set<String> get downloadedSongIds => {
    for (final entry in songs)
      if (entry.isDownloaded) entry.song.id,
  };

  Set<String> get downloadedAlbumIds => {
    for (final album in albums)
      if (album.isDownloaded) album.id,
  };

  Set<String> get downloadedArtistIds => {
    for (final artist in artists)
      if (artist.downloaded) artist.id,
  };
}

class LocalSearchResult {
  const LocalSearchResult({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.hits = const [],
  });

  final List<IndexedSong> songs;
  final List<IndexedAlbum> albums;
  final List<IndexedArtist> artists;
  final List<IndexedPlaylist> playlists;
  final List<IndexedSong> hits;

  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  IndexedSong? get best => songs.isEmpty ? null : songs.first;
}

/// Índice en memoria construido a partir de descargas, favoritos, historial y
/// playlists locales. No persiste ni llama a la red y se reconstruye cuando
/// cambian las fuentes.
class LocalSearchService {
  const LocalSearchService();

  LocalSearchIndex buildIndex({
    required List<SongModel> downloads,
    required List<SongModel> favorites,
    required List<SongModel> history,
    required List<PlaylistModel> playlists,
  }) {
    final entries = <String, _MutableIndexedSong>{};

    void add(Iterable<SongModel> songs, LocalSongSource source) {
      for (final song in songs) {
        if (song.id.isEmpty) continue;
        final entry = entries.putIfAbsent(
          song.id,
          () => _MutableIndexedSong(song),
        );
        entry.sources.add(source);
        if (entry.song.album == null && song.album != null) {
          entry.song = song;
        }
      }
    }

    add(downloads, LocalSongSource.downloaded);
    add(favorites, LocalSongSource.favorite);
    add(history, LocalSongSource.history);
    for (final playlist in playlists) {
      add(playlist.songs, LocalSongSource.playlist);
      for (final song in playlist.songs) {
        final entry = entries[song.id];
        entry?.playlistNames.add(playlist.name);
      }
    }

    final indexedSongs = entries.values.map((entry) {
      final song = entry.song;
      return IndexedSong(
        song: song,
        sources: Set.unmodifiable(entry.sources),
        normalizedTitle: normalize(song.title),
        normalizedArtist: normalize(song.artists.join(' ')),
        normalizedAlbum: normalize(song.album ?? ''),
        playlistNames: entry.playlistNames.toList(),
      );
    }).toList();

    final albums = <String, List<IndexedSong>>{};
    final artists = <String, List<IndexedSong>>{};
    final artistNames = <String, String>{};
    for (final entry in indexedSongs) {
      final song = entry.song;
      final albumKey = (song.albumId?.isNotEmpty ?? false)
          ? song.albumId!
          : normalize(song.album ?? '');
      if (albumKey.isNotEmpty) {
        albums.putIfAbsent(albumKey, () => []).add(entry);
      }
      final ids = song.artistIds ?? const <String>[];
      final names = song.artists;
      for (var index = 0; index < names.length; index++) {
        final name = names[index];
        if (name.trim().isEmpty) continue;
        final id = index < ids.length && ids[index].isNotEmpty
            ? ids[index]
            : normalize(name);
        artistNames[id] = name;
        artists.putIfAbsent(id, () => []).add(entry);
      }
    }

    final indexedAlbums = albums.entries.map((entry) {
      final songs = entry.value.map((item) => item.song).toList();
      final first = entry.value.first;
      return IndexedAlbum(
        id: entry.key,
        title: first.song.album ?? songs.first.title,
        artist: first.song.artists.join(', '),
        songs: songs,
        coverUrl: first.song.artworkUrl,
        year: first.song.year,
        downloaded: entry.value.every((item) => item.isDownloaded),
      );
    }).toList();

    final indexedArtists = artists.entries.map((entry) {
      final entries = entry.value;
      final first = entries.first;
      return IndexedArtist(
        id: entry.key,
        name: artistNames[entry.key] ?? first.song.artists.first,
        songs: entries.map((item) => item.song).toList(),
        imageUrl: first.song.artworkUrl,
        downloaded: entries.every((item) => item.isDownloaded),
      );
    }).toList();

    return LocalSearchIndex(
      songs: indexedSongs,
      albums: indexedAlbums,
      artists: indexedArtists,
      playlists: playlists
          .where((playlist) => playlist.songs.isNotEmpty || playlist.name.isNotEmpty)
          .map(IndexedPlaylist.new)
          .toList(),
    );
  }

  LocalSearchResult search(LocalSearchIndex index, String query) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return const LocalSearchResult();
    final tokens = tokenize(query);

    final songs = <({IndexedSong entry, int score})>[];
    for (final entry in index.songs) {
      final score = _scoreEntry(entry, normalized, tokens);
      if (score <= 0) continue;
      songs.add((entry: entry, score: score));
    }
    songs.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      final bySource = b.entry.sourcePriority.compareTo(a.entry.sourcePriority);
      if (bySource != 0) return bySource;
      return a.entry.normalizedTitle.compareTo(b.entry.normalizedTitle);
    });

    final albums = <({IndexedAlbum entry, int score})>[];
    for (final album in index.albums) {
      final title = normalize(album.title);
      final artist = normalize(album.artist);
      var score = _fieldScore(title, normalized);
      if (score == 0 && artist.contains(normalized)) score = 30;
      if (score == 0) continue;
      if (album.isDownloaded) score += 10;
      albums.add((entry: album, score: score));
    }
    albums.sort((a, b) => b.score.compareTo(a.score));

    final artists = <({IndexedArtist entry, int score})>[];
    for (final artist in index.artists) {
      final name = normalize(artist.name);
      var score = _fieldScore(name, normalized);
      if (score == 0) continue;
      if (artist.downloaded) score += 10;
      artists.add((entry: artist, score: score));
    }
    artists.sort((a, b) => b.score.compareTo(a.score));

    final playlists = <({IndexedPlaylist entry, int score})>[];
    for (final playlist in index.playlists) {
      var score = _fieldScore(playlist.normalizedName, normalized);
      if (score == 0 && playlist.normalizedSongs.contains(normalized)) {
        score = 20;
      }
      if (score == 0) continue;
      playlists.add((entry: playlist, score: score));
    }
    playlists.sort((a, b) => b.score.compareTo(a.score));

    return LocalSearchResult(
      songs: songs.map((item) => item.entry).toList(),
      albums: albums.map((item) => item.entry).toList(),
      artists: artists.map((item) => item.entry).toList(),
      playlists: playlists.map((item) => item.entry).toList(),
      hits: songs.map((item) => item.entry).take(1).toList(),
    );
  }

  /// Filtra y ordena canciones por relevancia local. Se usa en el detalle de
  /// playlists, descargas y la cola.
  List<SongModel> searchInSongs(Iterable<SongModel> songs, String query) {
    final normalized = normalize(query);
    if (normalized.isEmpty) return List<SongModel>.from(songs);
    final tokens = tokenize(query);
    final scored = <({SongModel song, int score, int index})>[];
    var index = 0;
    for (final song in songs) {
      final title = normalize(song.title);
      final artist = normalize(song.artists.join(' '));
      final album = normalize(song.album ?? '');
      var score = _fieldScore(title, normalized);
      if (score == 0 && artist.contains(normalized)) score = 40;
      if (score == 0 && album.contains(normalized)) score = 30;
      if (score > 0 && tokens.length > 1) {
        final haystack = '$title $artist $album';
        if (tokens.every(haystack.contains)) score += 10;
      }
      if (score > 0) {
        scored.add((song: song, score: score, index: index));
      }
      index++;
    }
    scored.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      if (byScore != 0) return byScore;
      return a.index.compareTo(b.index);
    });
    return scored.map((item) => item.song).toList();
  }

  int _scoreEntry(
    IndexedSong entry,
    String query,
    List<String> tokens,
  ) {
    final titleScore = _fieldScore(entry.normalizedTitle, query);
    var score = titleScore;
    if (score == 0 && entry.normalizedArtist.contains(query)) score = 40;
    if (score == 0 && entry.normalizedAlbum.contains(query)) score = 30;
    if (score == 0 &&
        entry.playlistNames.any((name) => normalize(name).contains(query))) {
      score = 20;
    }
    if (score == 0) return 0;
    if (tokens.length > 1) {
      final haystack =
          '${entry.normalizedTitle} ${entry.normalizedArtist} ${entry.normalizedAlbum}';
      if (tokens.every(haystack.contains)) score += 10;
    }
    if (entry.sources.contains(LocalSongSource.downloaded)) score += 15;
    if (entry.sources.contains(LocalSongSource.favorite)) score += 8;
    if (entry.sources.contains(LocalSongSource.history)) score += 4;
    return score;
  }

  int _fieldScore(String field, String query) {
    if (field.isEmpty) return 0;
    if (field == query) return 100;
    if (field.startsWith(query)) return 80;
    if (field.contains(query)) return 60;
    return 0;
  }

  /// Devuelve hasta [limit] canciones relacionadas localmente con una semilla,
  /// priorizando el mismo artista y álbum. Es el fallback offline de Daily Mix.
  List<SongModel> relatedLocal(
    List<SongModel> pool,
    SongModel seed, {
    int limit = 25,
    Set<String> excludeIds = const {},
  }) {
    final artistKey = seed.artists.isEmpty
        ? ''
        : normalize(seed.artists.first);
    final albumKey = normalize(seed.album ?? '');
    final scored = <({SongModel song, int score})>[];
    final seen = <String>{seed.id, ...excludeIds};
    for (final song in pool) {
      if (song.id.isEmpty || !seen.add(song.id)) continue;
      var score = 0;
      final songArtist = song.artists.isEmpty
          ? ''
          : normalize(song.artists.first);
      if (artistKey.isNotEmpty && songArtist == artistKey) score += 20;
      if (albumKey.isNotEmpty && normalize(song.album ?? '') == albumKey) {
        score += 12;
      }
      score += song.title.length % 5;
      scored.add((song: song, score: score));
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    final result = scored.map((item) => item.song).take(limit).toList();
    result.shuffle(math.Random(seed.id.hashCode ^ DateTime.now().day));
    return result;
  }
}

class _MutableIndexedSong {
  _MutableIndexedSong(this.song);
  SongModel song;
  final Set<LocalSongSource> sources = {};
  final Set<String> playlistNames = {};
}

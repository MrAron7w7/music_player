import 'dart:async';
import 'dart:math' as math;

import 'package:ytmusicapi_dart/ytmusicapi_dart.dart';
import 'package:ytmusicapi_dart/enums.dart';
import 'package:ytmusicapi_dart/models/lyrics.dart';

import '../models/album_model.dart';
import '../models/artist_model.dart';
import '../models/public_playlist_model.dart';
import '../models/search_models.dart';
import '../models/song_model.dart';
import 'app_cache.dart';

class YtService {
  YtService(this.api, {this.cache});
  final YTMusic api;

  /// Caché persistente opcional para que las segundas visitas sean instantáneas.
  final AppCache? cache;

  final Map<String, ({Object? value, DateTime createdAt})> _cache = {};
  final Map<String, Future<Object?>> _pending = {};

  Future<T> _cached<T>(
    String key,
    Future<T> Function() load, {
    Duration ttl = const Duration(minutes: 3),
    Duration persistTtl = const Duration(days: 7),
    int persistMaxEntries = 500,
    Object? Function(T value)? encode,
    T Function(Object? data)? decode,
    Duration timeout = const Duration(seconds: 14),
    /// Si se proporciona y devuelve `false`, el resultado no se guarda ni en
    /// caché de memoria ni en disco (útil para evitar cachear listas vacías
    /// o fallos parciales).
    bool Function(T value)? cacheIf,
  }) async {
    final entry = _cache[key];
    if (entry != null && DateTime.now().difference(entry.createdAt) < ttl) {
      _cache.remove(key);
      _cache[key] = entry;
      return entry.value as T;
    }
    if (entry != null) _cache.remove(key);

    if (decode != null && cache != null) {
      final stored = cache!.get<Object>(key);
      if (stored != null) {
        try {
          final value = decode(stored);
          if (cacheIf != null && !cacheIf(value)) {
            return value;
          }
          _cache[key] = (value: value, createdAt: DateTime.now());
          return value;
        } catch (_) {
          // Un dato antiguo o incompatible se descarta.
          unawaited(cache!.remove(key));
        }
      }
    }

    final pending = _pending[key];
    if (pending != null) return await pending as T;
    final request = load().timeout(timeout);
    _pending[key] = request;
    try {
      final value = await request;
      if (cacheIf != null && !cacheIf(value)) {
        return value;
      }
      _cache[key] = (value: value, createdAt: DateTime.now());
      while (_cache.length > 100) {
        _cache.remove(_cache.keys.first);
      }
      if (encode != null && cache != null) {
        final encoded = encode(value);
        if (encoded != null) {
          unawaited(
            cache!.put(
              key,
              encoded,
              ttl: persistTtl,
              maxEntries: persistMaxEntries,
            ),
          );
        }
      }
      return value;
    } finally {
      _pending.remove(key);
    }
  }

  String _queryKey(String query) => query.trim().toLowerCase();

  Future<List<Map<String, dynamic>>> _search(
    String q,
    SearchFilterType type, {
    int limit = 20,
    bool ignoreSpelling = false,
  }) async => _cached(
    'search:${type.name}:${_queryKey(q)}:$limit:${ignoreSpelling ? 1 : 0}',
    () async => (await api.search(
      q,
      filter: type,
      limit: limit,
      ignoreSpelling: ignoreSpelling,
    )).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    ttl: const Duration(minutes: 10),
    persistTtl: const Duration(hours: 6),
    persistMaxEntries: 120,
    encode: (value) => value,
    decode: (data) => (data as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
  );

  Future<List<SongModel>> searchSongs(
    String query, {
    int limit = 20,
    bool ignoreSpelling = false,
  }) => _cached(
    'search:songs:${_queryKey(query)}:$limit:${ignoreSpelling ? 1 : 0}',
    () async =>
        (await api.search(
              query,
              filter: SearchFilterType.songs,
              limit: limit,
              ignoreSpelling: ignoreSpelling,
            ))
            .whereType<Map>()
            .map((e) => SongModel.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.id.isNotEmpty)
            .toList(),
    ttl: const Duration(minutes: 10),
    persistTtl: const Duration(hours: 6),
    persistMaxEntries: 120,
    encode: (songs) => songs.map((song) => song.toJson()).toList(),
    decode: (data) => (data as List)
        .whereType<Map>()
        .map((song) => SongModel.fromJson(Map<String, dynamic>.from(song)))
        .where((song) => song.id.isNotEmpty)
        .toList(),
  );

  Future<List<Map<String, dynamic>>> _searchAllRaw(
    String query, {
    int limit = 20,
    bool ignoreSpelling = false,
  }) => _cached(
    'search:all:${_queryKey(query)}:$limit:${ignoreSpelling ? 1 : 0}',
    () async => (await api.search(
      query,
      limit: limit,
      ignoreSpelling: ignoreSpelling,
    )).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
    ttl: const Duration(minutes: 10),
    persistTtl: const Duration(hours: 6),
    persistMaxEntries: 120,
    encode: (value) => value,
    decode: (data) => (data as List)
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(),
  );

  /// Búsqueda mixta para la pestaña “Todo”. Agrupa por `resultType` y conserva
  /// el mejor resultado que destaca YouTube Music.
  Future<SearchAllResult> searchAll(
    String query, {
    int limit = 20,
    bool ignoreSpelling = false,
  }) async {
    final raw = await _searchAllRaw(
      query,
      limit: limit,
      ignoreSpelling: ignoreSpelling,
    );
    final songs = <SongModel>[];
    final albums = <AlbumModel>[];
    final artists = <ArtistModel>[];
    final playlists = <PublicPlaylistModel>[];
    final songIds = <String>{};
    final albumIds = <String>{};
    final artistIds = <String>{};
    final playlistIds = <String>{};
    SearchHit? topHit;

    for (final map in raw) {
      final resultType = '${map['resultType'] ?? ''}';
      final isTop = '${map['category'] ?? ''}'.toLowerCase() == 'top result';
      switch (resultType) {
        case 'song':
        case 'video':
          final song = SongModel.fromJson(map);
          if (song.id.isEmpty || !songIds.add(song.id)) continue;
          songs.add(song);
          if (isTop) topHit ??= SearchHit.song(song);
        case 'album':
          final album = AlbumModel.fromJson(map);
          if (album.id.isEmpty || !albumIds.add(album.id)) continue;
          albums.add(album);
          if (isTop) topHit ??= SearchHit.album(album);
        case 'artist':
          final artist = ArtistModel.fromJson(map);
          if (artist.id.isEmpty || !artistIds.add(artist.id)) continue;
          artists.add(artist);
          if (isTop) topHit ??= SearchHit.artist(artist);
        case 'playlist':
          final playlist = PublicPlaylistModel.fromJson(map);
          if (playlist.id.isEmpty || !playlistIds.add(playlist.id)) continue;
          playlists.add(playlist);
          if (isTop) topHit ??= SearchHit.playlist(playlist);
        default:
          // profile, podcast y episode no forman parte de los resultados.
          break;
      }
    }

    topHit ??= songs.isNotEmpty
        ? SearchHit.song(songs.first)
        : albums.isNotEmpty
        ? SearchHit.album(albums.first)
        : artists.isNotEmpty
        ? SearchHit.artist(artists.first)
        : playlists.isNotEmpty
        ? SearchHit.playlist(playlists.first)
        : null;

    return SearchAllResult(
      songs: songs,
      albums: albums,
      artists: artists,
      playlists: playlists,
      best: topHit,
    );
  }

  Future<List<AlbumModel>> searchAlbums(
    String q, {
    int limit = 40,
    bool ignoreSpelling = false,
  }) async => (await _search(
    q,
    SearchFilterType.albums,
    limit: limit,
    ignoreSpelling: ignoreSpelling,
  )).map(AlbumModel.fromJson).where((album) => album.id.isNotEmpty).toList();

  Future<List<ArtistModel>> searchArtists(
    String q, {
    int limit = 40,
    bool ignoreSpelling = false,
  }) async => (await _search(
    q,
    SearchFilterType.artists,
    limit: limit,
    ignoreSpelling: ignoreSpelling,
  ))
      .map(ArtistModel.fromJson)
      .where((artist) => artist.id.isNotEmpty)
      .toList();

  Future<List<PublicPlaylistModel>> searchPlaylists(
    String q, {
    int limit = 20,
    bool ignoreSpelling = false,
  }) async => (await _search(
    q,
    SearchFilterType.playlists,
    limit: limit,
    ignoreSpelling: ignoreSpelling,
  ))
      .map(PublicPlaylistModel.fromJson)
      .where((playlist) => playlist.id.isNotEmpty)
      .toList();

  /// Detalle completo de una playlist pública. Filtra entradas que no son
  /// reproducibles (episodios, podcasts y álbumes encadenados).
  Future<PublicPlaylistPage> getPublicPlaylist(
    String id, {
    int limit = 100,
  }) => _cached(
    'publicPlaylist:$id:$limit',
    () async {
      final raw = Map<String, dynamic>.from(
        await api.getPlaylist(id, limit: limit),
      );
      final tracks = (raw['tracks'] as List? ?? raw['songs'] as List? ?? const [])
          .whereType<Map>()
          .map((entry) => Map<String, dynamic>.from(entry))
          .toList();
      final songs = <SongModel>[];
      final seen = <String>{};
      for (final track in tracks) {
        final song = SongModel.fromJson(track);
        if (song.id.isEmpty || !seen.add(song.id)) continue;
        if (song.id.startsWith('MPRE') ||
            song.id.startsWith('MPLA') ||
            song.id.startsWith('MPED') ||
            song.id.startsWith('UC')) {
          continue;
        }
        songs.add(song);
      }
      final header = PublicPlaylistModel.fromJson({
        ...raw,
        'browseId': raw['browseId'] ?? id,
      });
      final playlist = header.copyWith(
        itemCount: header.itemCount ?? songs.length,
        thumbnailUrl:
            header.thumbnailUrl ?? songs.firstOrNull?.thumbnailUrl,
      );
      return PublicPlaylistPage(playlist: playlist, songs: songs);
    },
    ttl: const Duration(minutes: 30),
    persistTtl: const Duration(hours: 6),
    persistMaxEntries: 80,
    timeout: const Duration(seconds: 20),
    encode: (page) => page.toJson(),
    decode: (data) =>
        PublicPlaylistPage.fromJson(Map<String, dynamic>.from(data as Map)),
  );

  /// Sugerencias de autocompletado normalizadas.
  Future<List<SearchSuggestion>> getSearchSuggestions(
    String query, {
    bool detailedRuns = true,
  }) => _cached(
    'search:suggestions:${_queryKey(query)}',
    () async {
      final raw = await api.getSearchSuggestions(
        query,
        detailedRuns: detailedRuns,
      );
      final list = raw is List ? raw : const [];
      return list.whereType<Map>().map((entry) {
        final map = Map<String, dynamic>.from(entry);
        final runs = (map['runs'] as List? ?? const [])
            .whereType<Map>()
            .map(
              (run) => SuggestionRun(
                '${run['text'] ?? ''}',
                bold: run['bold'] == true,
              ),
            )
            .where((run) => run.text.isNotEmpty)
            .toList();
        return SearchSuggestion(
          text: '${map['text'] ?? ''}',
          runs: runs,
          fromHistory: map['fromHistory'] == true,
          feedbackToken: map['feedbackToken'] as String?,
        );
      }).where((suggestion) => suggestion.text.isNotEmpty).toList();
    },
    ttl: const Duration(minutes: 15),
    persistTtl: const Duration(days: 1),
    persistMaxEntries: 100,
    timeout: const Duration(seconds: 8),
    cacheIf: (suggestions) => suggestions.isNotEmpty,
    encode: (suggestions) => suggestions
        .map(
          (suggestion) => {
            'text': suggestion.text,
            'runs': suggestion.runs
                .map((run) => {'text': run.text, 'bold': run.bold})
                .toList(),
            'fromHistory': suggestion.fromHistory,
            'feedbackToken': suggestion.feedbackToken,
          },
        )
        .toList(),
    decode: (data) => (data as List)
        .whereType<Map>()
        .map((entry) {
          final map = Map<String, dynamic>.from(entry);
          return SearchSuggestion(
            text: '${map['text'] ?? ''}',
            runs: (map['runs'] as List? ?? const [])
                .whereType<Map>()
                .map(
                  (run) => SuggestionRun(
                    '${run['text'] ?? ''}',
                    bold: run['bold'] == true,
                  ),
                )
                .toList(),
            fromHistory: map['fromHistory'] == true,
            feedbackToken: map['feedbackToken'] as String?,
          );
        })
        .where((suggestion) => suggestion.text.isNotEmpty)
        .toList(),
  );

  Future<Map<String, dynamic>> getExploreRaw() => _cached(
    'explore:v1',
    () async => Map<String, dynamic>.from(await api.getExplore()),
    ttl: const Duration(hours: 12),
    persistTtl: const Duration(hours: 24),
    persistMaxEntries: 4,
    encode: (value) => value,
    decode: (data) => Map<String, dynamic>.from(data as Map),
  );

  Future<Map<String, dynamic>> getMoodCategoriesRaw() => _cached(
    'explore:moods:v1',
    () async => Map<String, dynamic>.from(await api.getMoodCategories()),
    ttl: const Duration(days: 7),
    persistTtl: const Duration(days: 7),
    persistMaxEntries: 2,
    encode: (value) => value,
    decode: (data) => Map<String, dynamic>.from(data as Map),
  );

  Future<List<Map<String, dynamic>>> getMoodPlaylistsRaw(String params) =>
      _cached(
        'explore:genre:${params.hashCode}',
        () async => (await api.getMoodPlaylists(params))
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(),
        ttl: const Duration(hours: 24),
        persistTtl: const Duration(hours: 24),
        persistMaxEntries: 40,
        encode: (value) => value,
        decode: (data) => (data as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList(),
      );

  Future<Map<String, dynamic>> getChartsRaw(String country) => _cached(
    'charts:v1:$country',
    () async => Map<String, dynamic>.from(
      await api.getCharts(country: country),
    ),
    ttl: const Duration(hours: 12),
    persistTtl: const Duration(hours: 24),
    persistMaxEntries: 20,
    encode: (value) => value,
    decode: (data) => Map<String, dynamic>.from(data as Map),
  );

  Future<SongModel?> getSongDetails(String id) => _cached(
    'song:$id',
    () async {
      final data = Map<String, dynamic>.from(await api.getSong(id));
      data['id'] = id;
      return SongModel.fromJson(data);
    },
    ttl: const Duration(minutes: 15),
    persistTtl: const Duration(days: 2),
    persistMaxEntries: 300,
    encode: (song) => song?.toJson(),
    decode: (data) =>
        SongModel.fromJson(Map<String, dynamic>.from(data as Map)),
  );

  Future<List<SongModel>> getRelatedSongs(String videoId) => _cached(
    'related:v2:$videoId',
    () async {
      final songs = <SongModel>[];
      final seen = <String>{videoId};

      void addContents(dynamic value) {
        if (value is List) {
          for (final item in value) {
            addContents(item);
          }
          return;
        }
        if (value is! Map) return;
        final map = Map<String, dynamic>.from(value);
        final rawId = '${map['videoId'] ?? map['id'] ?? ''}';
        if (rawId.isEmpty ||
            rawId.startsWith('MPRE') ||
            rawId.startsWith('MPLA') ||
            rawId.startsWith('UC') ||
            rawId.startsWith('PL') ||
            rawId.startsWith('RD') ||
            rawId.startsWith('VL')) {
          return;
        }
        final song = SongModel.fromJson(map);
        if (song.id.isEmpty || !seen.add(song.id)) return;
        songs.add(song);
      }

      Map<String, dynamic>? watch;
      bool watchLoaded = false;
      try {
        watch = await api.getWatchPlaylist(videoId: videoId, limit: 30);
        watchLoaded = true;
      } catch (_) {
        try {
          watch = await api.getWatchPlaylist(
            videoId: videoId,
            limit: 30,
            radio: true,
          );
          watchLoaded = true;
        } catch (_) {
          watch = null;
        }
      }

      if (!watchLoaded) {
        throw StateError('No se pudo cargar la lista de reproducción relacionada de este video.');
      }

      if (watch != null) {
        // La página "Relacionado" es la señal de mayor calidad; la cola de
        // radio del watch playlist sirve como respaldo y para dar variedad.
        final relatedId = watch['related'] as String?;
        if (relatedId != null && relatedId.isNotEmpty) {
          try {
            final sections = await api.getSongRelated(relatedId);
            for (final section in sections.whereType<Map>()) {
              addContents(section['contents']);
            }
          } catch (_) {
            // Si falla "Relacionado" seguimos con la radio del watch.
          }
        }
        addContents(watch['tracks']);
      }

      return songs;
    },
    ttl: const Duration(minutes: 10),
    persistTtl: const Duration(hours: 6),
    persistMaxEntries: 200,
    timeout: const Duration(seconds: 22),
    cacheIf: (songs) => songs.isNotEmpty,
    encode: (songs) => songs.map((song) => song.toJson()).toList(),
    decode: (data) => (data as List)
        .whereType<Map>()
        .map((song) => SongModel.fromJson(Map<String, dynamic>.from(song)))
        .where((song) => song.id.isNotEmpty)
        .toList(),
  );

  /// Cola inteligente para una canción: equilibra pistas del álbum,
  /// canciones relacionadas y éxitos del mismo artista. Las listas que fallan
  /// simplemente no aportan candidatos, sin romper la reproducción.
  Future<List<SongModel>> getSmartQueue(
    SongModel seed, {
    Set<String> excludeIds = const {},
    int limit = 24,
  }) async {
    if (seed.id.isEmpty || limit <= 0) return const [];
    final excluded = {...excludeIds, seed.id};

    final batches = await Future.wait<List<SongModel>>([
      _albumTracksFor(seed),
      _safeRelatedSongs(seed.id),
      _safeArtistSongs(seed.artistIds),
    ]);
    final album = _uniqueSongs(batches[0], excluded).take(6).toList();
    final related = _uniqueSongs(batches[1], excluded).take(14).toList();
    final artist = _uniqueSongs(batches[2], excluded).take(8).toList();

    // Un pequeño giro estable por día evita que siempre suenen las mismas
    // canciones, sin cambiar la cola mientras se está escuchando.
    final random = math.Random(seed.id.hashCode ^ DateTime.now().day);
    related.shuffle(random);
    artist.shuffle(random);

    final pools = [album, related, artist];
    final indices = [0, 0, 0];
    final seen = <String>{...excluded};
    final artistCounts = <String, int>{};
    final result = <SongModel>[];

    bool addFrom(int pool) {
      while (indices[pool] < pools[pool].length) {
        final song = pools[pool][indices[pool]++];
        if (song.id.isEmpty || !seen.add(song.id)) continue;
        final artistKey = song.artists.isEmpty
            ? ''
            : song.artists.first.trim().toLowerCase();
        final maxForArtist = pool == 0 ? 4 : 2;
        if (artistKey.isNotEmpty &&
            (artistCounts[artistKey] ?? 0) >= maxForArtist) {
          continue;
        }
        if (artistKey.isNotEmpty) {
          artistCounts[artistKey] = (artistCounts[artistKey] ?? 0) + 1;
        }
        result.add(song);
        return true;
      }
      return false;
    }

    // Relacionadas primero, con apariciones medidas del álbum y del artista.
    const pattern = [
      1,
      1,
      2,
      1,
      0,
      1,
      2,
      1,
      0,
      1,
      2,
      1,
      1,
      0,
      1,
      2,
      1,
      1,
      0,
      1,
      2,
      1,
    ];
    for (final pool in pattern) {
      if (result.length >= limit) break;
      addFrom(pool);
    }
    for (final pool in [1, 2, 0]) {
      while (result.length < limit && addFrom(pool)) {}
    }
    return result;
  }

  Future<List<SongModel>> _safeRelatedSongs(String id) async {
    try {
      return await getRelatedSongs(id);
    } catch (_) {
      return const [];
    }
  }

  Future<List<SongModel>> _safeArtistSongs(List<String>? artistIds) async {
    for (final id in (artistIds ?? const <String>[]).take(2)) {
      if (id.isEmpty) continue;
      try {
        final songs = await getArtistSongs(id);
        if (songs.isNotEmpty) return songs;
      } catch (_) {
        // Probamos con el siguiente artista acreditado.
      }
    }
    return const [];
  }

  Future<List<SongModel>> _albumTracksFor(SongModel seed) async {
    final albumId = seed.albumId;
    if (albumId == null || !albumId.startsWith('MPRE')) return const [];
    try {
      final album = await getAlbum(albumId);
      final songs = album?.songs ?? const <SongModel>[];
      final index = songs.indexWhere((song) => song.id == seed.id);
      if (index < 0) return songs;
      // Si la semilla está en el álbum, continuamos por el orden del disco y
      // dejamos las anteriores como variedad al final.
      return [...songs.skip(index + 1), ...songs.take(index)];
    } catch (_) {
      return const [];
    }
  }

  List<SongModel> _uniqueSongs(
    Iterable<SongModel> songs,
    Set<String> excluded,
  ) {
    final seen = <String>{...excluded};
    final result = <SongModel>[];
    for (final song in songs) {
      if (song.id.isEmpty || !seen.add(song.id)) continue;
      result.add(song);
    }
    return result;
  }

  Future<Map<String, dynamic>?> getLyricsForSong(String videoId) => _cached(
    'lyrics:$videoId',
    () => _loadLyricsForSong(videoId),
    ttl: const Duration(hours: 6),
    persistTtl: const Duration(days: 7),
    persistMaxEntries: 200,
    encode: (value) => value,
    decode: (data) => Map<String, dynamic>.from(data as Map),
  ).catchError((_) => null);

  Future<Map<String, dynamic>?> _loadLyricsForSong(String videoId) async {
    try {
      final watch = await api.getWatchPlaylist(videoId: videoId, limit: 1);
      final browseId = watch['lyrics'] as String?;
      if (browseId == null || browseId.isEmpty) return null;

      final timed = await api.getLyrics(browseId, timestamps: true);
      final timedLines = timed?['lyrics'];
      if (timedLines is List && timedLines.isNotEmpty) {
        final lines = timedLines
            .map((line) {
              if (line is LyricLine) {
                return {
                  'text': line.text,
                  'startMs': line.startTime,
                  'endMs': line.endTime,
                };
              }
              return <String, dynamic>{};
            })
            .where((line) => (line['text'] as String?)?.isNotEmpty == true)
            .toList();
        if (lines.isNotEmpty) return {'timed': true, 'lines': lines};
      }

      final plain = await api.getLyrics(browseId);
      final text = plain?['lyrics'] as String?;
      if (text == null || text.trim().isEmpty) return null;
      return {
        'timed': false,
        'lines': text
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map((line) => {'text': line.trim()})
            .toList(),
        'source': plain?['source'],
      };
    } catch (_) {
      return null;
    }
  }

  Future<Map<String, dynamic>> _artistPage(String id) => _cached(
    'artistPage:v2:$id',
    () async => Map<String, dynamic>.from(await api.getArtist(id)),
    ttl: const Duration(minutes: 30),
    persistTtl: const Duration(hours: 12),
    persistMaxEntries: 100,
    encode: (page) => page,
    decode: (data) => Map<String, dynamic>.from(data as Map),
  );

  Future<List<SongModel>> getArtistSongs(String id) => _cached(
    'artist:songs:v2:$id',
    () async {
      final j = await _artistPage(id);
      final tracks =
          (j['songs'] is Map ? j['songs']['results'] : null) as List? ??
          const [];
      return _songsFromMaps(tracks);
    },
    ttl: const Duration(minutes: 20),
    persistTtl: const Duration(hours: 6),
    persistMaxEntries: 100,
    encode: (songs) => songs.map((song) => song.toJson()).toList(),
    decode: (data) => (data as List)
        .whereType<Map>()
        .map((song) => SongModel.fromJson(Map<String, dynamic>.from(song)))
        .where((song) => song.id.isNotEmpty)
        .toList(),
  );

  /// Radio del artista: mezcla sus canciones con artistas parecidos. Es una
  /// fuente ideal para recomendaciones porque YouTube Music ya la equilibra.
  Future<List<SongModel>> getArtistRadioSongs(String id, {int limit = 20}) =>
      _cached(
        'artist:radio:v2:$id:$limit',
        () async {
          final page = await _artistPage(id);
          final radioId = page['radioId'] as String?;
          if (radioId == null || radioId.isEmpty) {
            return getArtistSongs(id);
          }
          try {
            final watch = await api.getWatchPlaylist(
              playlistId: radioId,
              limit: limit,
            );
            final songs = _songsFromMaps(watch['tracks']);
            if (songs.isNotEmpty) return songs;
          } catch (_) {
            // La radio es opcional; los éxitos del artista siguen disponibles.
          }
          return getArtistSongs(id);
        },
        ttl: const Duration(minutes: 20),
        persistTtl: const Duration(hours: 6),
        persistMaxEntries: 120,
        timeout: const Duration(seconds: 22),
        encode: (songs) => songs.map((song) => song.toJson()).toList(),
        decode: (data) => (data as List)
            .whereType<Map>()
            .map((song) => SongModel.fromJson(Map<String, dynamic>.from(song)))
            .where((song) => song.id.isNotEmpty)
            .toList(),
      );

  /// Página pública de un artista: nombre, portada, canciones top y álbumes.
  Future<ArtistPageModel> getArtistPage(String id) => _cached(
    'artistPageModel:v2:$id',
    () async {
      final j = await _artistPage(id);
      final name = '${j['name'] ?? 'Artista'}';
      final thumb = SongModel.fromJson(j).thumbnailUrl;
      final topSongs = await getArtistSongs(id);
      final albumRaw = j['albums'];
      final params =
          albumRaw is Map ? albumRaw['params'] as String? : null;
      final albumes = <AlbumModel>[];
      if (params != null && params.isNotEmpty) {
        try {
          final rawAlbums = await api.getArtistAlbums(id, params, limit: 24);
          for (final a in rawAlbums.whereType<Map>()) {
            try {
              final map = Map<String, dynamic>.from(a);
              map['id'] = '${map['browseId'] ?? map['id'] ?? ''}';
              if (map['id'].isEmpty) continue;
              map['title'] ??= '${map['title'] ?? 'Álbum'}';
              final artists = (map['artists'] as List? ?? const [])
                  .whereType<Map>()
                  .map((e) => '${e['name'] ?? e}')
                  .whereType<String>()
                  .toList();
              map['artists'] = artists;
              albumes.add(AlbumModel.fromJson(map));
            } catch (_) {}
          }
        } catch (_) {}
      }
      return ArtistPageModel(
        name: name,
        thumb: thumb,
        cancionesTop: topSongs,
        albumes: albumes,
      );
    },
    ttl: const Duration(minutes: 30),
    persistTtl: const Duration(hours: 12),
    persistMaxEntries: 100,
    encode: (page) => {
      'name': page.name,
      'thumb': page.thumb,
      'cancionesTop': page.cancionesTop.map((s) => s.toJson()).toList(),
      'albumes': page.albumes.map((a) => a.toJson()).toList(),
    },
    decode: (data) {
      final d = Map<String, dynamic>.from(data as Map);
      return ArtistPageModel(
        name: '${d['name'] ?? 'Artista'}',
        thumb: d['thumb'] as String?,
        cancionesTop: (d['cancionesTop'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => SongModel.fromJson(Map<String, dynamic>.from(e)))
            .where((s) => s.id.isNotEmpty)
            .toList(),
        albumes: (d['albumes'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => AlbumModel.fromJson(Map<String, dynamic>.from(e)))
            .where((a) => a.id.isNotEmpty)
            .toList(),
      );
    },
  );

  /// Recomendaciones contextuales de un artista: sus canciones más conocidas
  /// y su radio, intercaladas y sin duplicados.
  Future<List<SongModel>> getArtistRecommendations(
    String id, {
    int limit = 12,
  }) async {
    final batches = await Future.wait<List<SongModel>>([
      getArtistSongs(id).catchError((_) => const <SongModel>[]),
      getArtistRadioSongs(
        id,
        limit: limit + 6,
      ).catchError((_) => const <SongModel>[]),
    ]);
    final seen = <String>{};
    final result = <SongModel>[];
    final longest = batches.fold<int>(
      0,
      (length, batch) => batch.length > length ? batch.length : length,
    );
    for (var index = 0; index < longest && result.length < limit; index++) {
      for (final batch in batches) {
        if (index >= batch.length) continue;
        final song = batch[index];
        if (song.id.isEmpty || !seen.add(song.id)) continue;
        result.add(song);
        if (result.length >= limit) break;
      }
    }
    return result;
  }

  List<SongModel> _songsFromMaps(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <SongModel>[];
    for (final entry in value) {
      if (entry is! Map) continue;
      final song = SongModel.fromJson(Map<String, dynamic>.from(entry));
      if (song.id.isEmpty || !seen.add(song.id)) continue;
      result.add(song);
    }
    return result;
  }

  Future<AlbumModel?> getAlbum(String id) => _cached(
    'album:v2:$id',
    () async {
      final j = await api.getAlbum(id);
      final rawTracks = j['tracks'] ?? j['songs'];
      final tracks = (rawTracks as List? ?? const [])
          .whereType<Map>()
          .map((entry) {
            final map = Map<String, dynamic>.from(entry);
            map['albumId'] = id;
            map['album'] ??= j['title'];
            return SongModel.fromJson(map);
          })
          .where((song) => song.id.isNotEmpty)
          .toList();
      final artists = j['artists'] is List
          ? (j['artists'] as List)
                .map((e) => '${e is Map ? e['name'] : e}')
                .where((name) => name.isNotEmpty)
                .toList()
          : const <String>[];
      return AlbumModel(
        id: id,
        title: '${j['title'] ?? 'Álbum'}',
        artists: artists,
        year: int.tryParse('${j['year'] ?? ''}'),
        thumbnailUrl:
            SongModel.fromJson(j).thumbnailUrl ??
            tracks.firstOrNull?.thumbnailUrl,
        songCount: tracks.length,
        songs: tracks,
      );
    },
    ttl: const Duration(minutes: 20),
    persistTtl: const Duration(days: 1),
    persistMaxEntries: 100,
    encode: (album) => album?.toJson(),
    decode: (data) =>
        AlbumModel.fromJson(Map<String, dynamic>.from(data as Map)),
  );
}

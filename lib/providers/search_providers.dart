import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/search_sort.dart';
import '../data/models/album_model.dart';
import '../data/models/artist_model.dart';
import '../data/models/home_models.dart';
import '../data/models/public_playlist_model.dart';
import '../data/models/search_models.dart';
import '../data/models/song_model.dart';
import '../data/services/app_cache.dart';
import '../data/services/local_search_service.dart';
import '../data/services/lyrics_index_service.dart';
import 'cache_providers.dart';
import 'downloads_providers.dart';
import 'library_providers.dart';
import 'music_providers.dart';
import 'network_providers.dart';

final localSearchServiceProvider = Provider<LocalSearchService>(
  (ref) => const LocalSearchService(),
);

/// Índice local compartido entre offline, “Mi biblioteca” y las búsquedas
/// internas. Se reconstruye solo cuando cambian sus fuentes.
final localSearchIndexProvider = Provider<LocalSearchIndex>((ref) {
  final service = ref.watch(localSearchServiceProvider);
  return service.buildIndex(
    downloads: ref.watch(downloadedSongsProvider),
    favorites: ref.watch(favoritesProvider),
    history: ref.watch(historyProvider),
    playlists: ref.watch(playlistsProvider),
  );
});

final searchFiltersProvider = StateProvider<SearchFilters>(
  (ref) => const SearchFilters(),
);

final ignoreSpellingProvider = StateProvider<bool>((ref) => false);

final suggestionsQueryProvider = StateProvider<String>((ref) => '');

final localPlaysProvider = Provider<Map<String, int>>((ref) {
  final snapshot = ref.watch(statsProvider).valueOrNull;
  if (snapshot == null) return const {};
  return {for (final stat in snapshot.topSongs) stat.song.id: stat.plays};
});

final _effectiveQueryProvider = Provider.family<String, String>((ref, query) {
  final filters = ref.watch(searchFiltersProvider);
  return filters.refineQuery(query.trim());
});

/// Resultado de búsqueda offline/local para un término.
final offlineSearchProvider = Provider.autoDispose
    .family<LocalSearchResult, String>((ref, query) {
      final index = ref.watch(localSearchIndexProvider);
      return ref.watch(localSearchServiceProvider).search(index, query);
    });

/// Mantiene viva la página dos minutos para no perderla al cambiar de pestaña.
void _keepAlive(Ref ref) {
  final link = ref.keepAlive();
  final timer = Timer(const Duration(minutes: 2), link.close);
  ref.onDispose(timer.cancel);
}

class SearchPageNotifier<T> extends StateNotifier<SearchPageState<T>> {
  SearchPageNotifier({
    required this.loadPage,
    required this.idOf,
    this.pageSize = 20,
    this.maxLimit = 100,
  }) : super(SearchPageState<T>()) {
    _loadInitial();
  }

  final Future<List<T>> Function(int limit) loadPage;
  final String Function(T item) idOf;
  final int pageSize;
  final int maxLimit;

  int _requestId = 0;

  Future<void> _loadInitial() async {
    final request = ++_requestId;
    state = SearchPageState<T>(loading: true, requestId: request);
    try {
      final items = await loadPage(pageSize);
      if (!mounted || request != _requestId) return;
      state = SearchPageState<T>(
        items: items.take(maxLimit).toList(),
        page: 0,
        loading: false,
        hasMore: items.length >= pageSize && pageSize < maxLimit,
        requestId: request,
      );
    } catch (error) {
      if (!mounted || request != _requestId) return;
      state = SearchPageState<T>(
        loading: false,
        error: error,
        requestId: request,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.loading || state.loadingMore || !state.hasMore) return;
    final request = ++_requestId;
    final nextPage = state.page + 1;
    final nextLimit = math.min((nextPage + 1) * pageSize, maxLimit);
    state = state.copyWith(
      loadingMore: true,
      error: null,
      clearError: true,
      requestId: request,
    );
    try {
      final fetched = await loadPage(nextLimit);
      if (!mounted || request != _requestId) return;
      final existing = state.items.map(idOf).toSet();
      final newItems = <T>[];
      for (final item in fetched) {
        if (existing.add(idOf(item))) newItems.add(item);
      }
      final merged = [...state.items, ...newItems].take(maxLimit).toList();
      state = SearchPageState<T>(
        items: merged,
        page: nextPage,
        loading: false,
        hasMore:
            newItems.isNotEmpty &&
            nextLimit < maxLimit &&
            fetched.length >= nextLimit,
        requestId: request,
      );
    } catch (error) {
      if (!mounted || request != _requestId) return;
      state = state.copyWith(
        loadingMore: false,
        error: error,
        requestId: request,
      );
    }
  }

  Future<void> retry() async {
    state = SearchPageState<T>();
    await _loadInitial();
  }
}

final searchSongsProvider = StateNotifierProvider.autoDispose
    .family<SearchPageNotifier<SongModel>, SearchPageState<SongModel>, String>((
      ref,
      query,
    ) {
      _keepAlive(ref);
      final q = ref.watch(_effectiveQueryProvider(query));
      return SearchPageNotifier<SongModel>(
        idOf: (song) => song.id,
        loadPage: (limit) => ref
            .read(ytServiceProvider)
            .searchSongs(
              q,
              limit: limit,
              ignoreSpelling: ref.read(ignoreSpellingProvider),
            ),
      );
    });

final searchAlbumsProvider = StateNotifierProvider.autoDispose
    .family<
      SearchPageNotifier<AlbumModel>,
      SearchPageState<AlbumModel>,
      String
    >((ref, query) {
      _keepAlive(ref);
      final q = ref.watch(_effectiveQueryProvider(query));
      return SearchPageNotifier<AlbumModel>(
        idOf: (album) => album.id,
        loadPage: (limit) => ref
            .read(ytServiceProvider)
            .searchAlbums(
              q,
              limit: limit,
              ignoreSpelling: ref.read(ignoreSpellingProvider),
            ),
      );
    });

final searchArtistsProvider = StateNotifierProvider.autoDispose
    .family<
      SearchPageNotifier<ArtistModel>,
      SearchPageState<ArtistModel>,
      String
    >((ref, query) {
      _keepAlive(ref);
      final q = ref.watch(_effectiveQueryProvider(query));
      return SearchPageNotifier<ArtistModel>(
        idOf: (artist) => artist.id,
        loadPage: (limit) => ref
            .read(ytServiceProvider)
            .searchArtists(
              q,
              limit: limit,
              ignoreSpelling: ref.read(ignoreSpellingProvider),
            ),
      );
    });

final searchPlaylistsProvider = StateNotifierProvider.autoDispose
    .family<
      SearchPageNotifier<PublicPlaylistModel>,
      SearchPageState<PublicPlaylistModel>,
      String
    >((ref, query) {
      _keepAlive(ref);
      final q = ref.watch(_effectiveQueryProvider(query));
      return SearchPageNotifier<PublicPlaylistModel>(
        idOf: (playlist) => playlist.id,
        loadPage: (limit) => ref
            .read(ytServiceProvider)
            .searchPlaylists(
              q,
              limit: limit,
              ignoreSpelling: ref.read(ignoreSpellingProvider),
            ),
      );
    });

final searchAllProvider = FutureProvider.autoDispose
    .family<SearchAllResult, String>((ref, query) async {
      if (query.trim().length < 2 || ref.watch(effectiveOfflineProvider)) {
        return const SearchAllResult();
      }
      _keepAlive(ref);
      return ref
          .read(ytServiceProvider)
          .searchAll(
            ref.watch(_effectiveQueryProvider(query)),
            limit: 20,
            ignoreSpelling: ref.watch(ignoreSpellingProvider),
          );
    });

final publicPlaylistProvider = FutureProvider.autoDispose
    .family<PublicPlaylistPage, String>(
      (ref, id) => ref.watch(ytServiceProvider).getPublicPlaylist(id),
    );

/// Sugerencias combinadas: historial local primero y después YouTube Music.
final searchSuggestionsProvider = FutureProvider.autoDispose
    .family<List<SearchSuggestion>, String>((ref, query) async {
      final normalized = query.trim();
      if (normalized.isEmpty) return const [];
      final history = ref.watch(searchHistoryNotifierProvider);
      final local = history
          .where(
            (item) =>
                item.toLowerCase().contains(normalized.toLowerCase()) ||
                normalized.toLowerCase().contains(item.toLowerCase()),
          )
          .take(8)
          .map(
            (item) => SearchSuggestion(
              text: item,
              fromHistory: true,
              runs: [SuggestionRun(item)],
            ),
          )
          .toList();
      if (normalized.length < 2 || ref.watch(effectiveOfflineProvider)) {
        return local.take(8).toList();
      }
      try {
        final remote = await ref
            .read(ytServiceProvider)
            .getSearchSuggestions(normalized);
        final seen = <String>{
          for (final item in local) item.text.toLowerCase(),
        };
        final merged = [...local];
        for (final suggestion in remote) {
          if (!seen.add(suggestion.text.toLowerCase())) continue;
          merged.add(suggestion);
          if (merged.length >= 8) break;
        }
        return merged.take(8).toList();
      } catch (_) {
        return local.take(8).toList();
      }
    });

/// Artistas que se comprobó que no tienen canciones ni álbumes. Se ocultan
/// durante la sesión para no volver a ofrecer una página vacía.
final hiddenArtistIdsProvider = StateProvider<Set<String>>((ref) => <String>{});

/// Estado de contenido de un artista. Se consulta en segundo plano para
/// retirar de los resultados los canales que no tienen canciones ni álbumes.
final artistContentStatusProvider = FutureProvider.family<bool, String>((
  ref,
  id,
) async {
  if (id.isEmpty) return false;
  try {
    return await ref.watch(ytServiceProvider).getArtistHasContent(id);
  } catch (_) {
    // Ante un fallo de red no se oculta al artista.
    return true;
  }
});

final filteredSearchAllProvider = Provider.autoDispose
    .family<SearchAllResult, String>((ref, query) {
      final filters = ref.watch(searchFiltersProvider);
      final downloadedSongs = ref.watch(downloadedSongIdsProvider);
      final downloadedAlbums = ref.watch(downloadedAlbumIdsProvider);
      final downloadedArtists = ref.watch(downloadedArtistIdsProvider);
      final hiddenArtists = ref.watch(hiddenArtistIdsProvider);
      final qualities = ref.watch(downloadQualityByIdProvider);

      final source = ref.watch(searchAllProvider(query)).valueOrNull;
      if (source == null) return const SearchAllResult();
      final songs = sortSongs(
        source.songs
            .where(
              (song) => filters.matchesSong(
                song,
                downloadedSongIds: downloadedSongs,
                downloadQualityById: qualities,
              ),
            )
            .toList(),
        filters.sort,
        localPlays: ref.watch(localPlaysProvider),
      );
      final albums = sortAlbums(
        source.albums
            .where(
              (album) => filters.matchesAlbum(
                album,
                downloadedAlbumIds: downloadedAlbums,
              ),
            )
            .toList(),
        filters.sort,
      );
      final artists = sortArtists(
        source.artists
            .where(
              (artist) =>
                  !hiddenArtists.contains(artist.id) &&
                  filters.matchesArtist(
                    artist,
                    downloadedArtistIds: downloadedArtists,
                  ),
            )
            .toList(),
        filters.sort,
      );
      final playlists = sortPublicPlaylists(
        source.playlists.where(filters.matchesPublicPlaylist).toList(),
        filters.sort,
      );
      final best = source.best;
      return SearchAllResult(
        songs: songs,
        albums: albums,
        artists: artists,
        playlists: playlists,
        best:
            best != null &&
                _bestVisible(best, songs, albums, artists, playlists)
            ? best
            : null,
      );
    });

bool _bestVisible(
  SearchHit best,
  List<SongModel> songs,
  List<AlbumModel> albums,
  List<ArtistModel> artists,
  List<PublicPlaylistModel> playlists,
) {
  return switch (best.type) {
    SearchHitType.song => songs.any((song) => song.id == best.song?.id),
    SearchHitType.album => albums.any((album) => album.id == best.album?.id),
    SearchHitType.artist => artists.any(
      (artist) => artist.id == best.artist?.id,
    ),
    SearchHitType.playlist => playlists.any(
      (playlist) => playlist.id == best.playlist?.id,
    ),
  };
}

final filteredSongsProvider = Provider.autoDispose
    .family<List<SongModel>, String>((ref, query) {
      final filters = ref.watch(searchFiltersProvider);
      final downloaded = ref.watch(downloadedSongIdsProvider);
      final qualities = ref.watch(downloadQualityByIdProvider);
      final state = ref.watch(searchSongsProvider(query));
      return sortSongs(
        state.items
            .where(
              (song) => filters.matchesSong(
                song,
                downloadedSongIds: downloaded,
                downloadQualityById: qualities,
              ),
            )
            .toList(),
        filters.sort,
        localPlays: ref.watch(localPlaysProvider),
      );
    });

final filteredAlbumsProvider = Provider.autoDispose
    .family<List<AlbumModel>, String>((ref, query) {
      final filters = ref.watch(searchFiltersProvider);
      final downloaded = ref.watch(downloadedAlbumIdsProvider);
      final state = ref.watch(searchAlbumsProvider(query));
      return sortAlbums(
        state.items
            .where(
              (album) =>
                  filters.matchesAlbum(album, downloadedAlbumIds: downloaded),
            )
            .toList(),
        filters.sort,
      );
    });

final filteredArtistsProvider = Provider.autoDispose
    .family<List<ArtistModel>, String>((ref, query) {
      final filters = ref.watch(searchFiltersProvider);
      final downloaded = ref.watch(downloadedArtistIdsProvider);
      final hiddenArtists = ref.watch(hiddenArtistIdsProvider);
      final state = ref.watch(searchArtistsProvider(query));
      return sortArtists(
        state.items
            .where(
              (artist) =>
                  !hiddenArtists.contains(artist.id) &&
                  filters.matchesArtist(
                    artist,
                    downloadedArtistIds: downloaded,
                  ),
            )
            .toList(),
        filters.sort,
      );
    });

final filteredPlaylistsProvider = Provider.autoDispose
    .family<List<PublicPlaylistModel>, String>((ref, query) {
      final filters = ref.watch(searchFiltersProvider);
      final state = ref.watch(searchPlaylistsProvider(query));
      return sortPublicPlaylists(
        state.items.where(filters.matchesPublicPlaylist).toList(),
        filters.sort,
      );
    });

class SearchSelectionNotifier extends StateNotifier<SearchSelectionState> {
  SearchSelectionNotifier() : super(const SearchSelectionState());

  void enter(String id) =>
      state = SearchSelectionState(selecting: true, songIds: {id});

  void toggle(String id) {
    final ids = {...state.songIds};
    if (!ids.add(id)) ids.remove(id);
    state = SearchSelectionState(selecting: ids.isNotEmpty, songIds: ids);
  }

  void selectAll(Iterable<String> ids) =>
      state = SearchSelectionState(selecting: true, songIds: ids.toSet());

  void clear() => state = const SearchSelectionState();

  void exit() => state = const SearchSelectionState();
}

final searchSelectionProvider =
    StateNotifierProvider.autoDispose<
      SearchSelectionNotifier,
      SearchSelectionState
    >((ref) => SearchSelectionNotifier());

/// Historial local con operaciones atómicas y persistencia inmediata.
class SearchHistoryNotifier extends StateNotifier<List<String>> {
  SearchHistoryNotifier(this.ref) : super(_read(ref));

  final Ref ref;

  static List<String> _read(Ref ref) {
    final saved = ref
        .read(localRepositoryProvider)
        .settings
        .get('searchHistory');
    return saved is List ? saved.whereType<String>().toList() : <String>[];
  }

  Future<void> add(String text) async {
    final value = text.trim();
    if (value.isEmpty) return;
    final updated = [
      value,
      ...state.where((item) => item.toLowerCase() != value.toLowerCase()),
    ].take(12).toList();
    await _save(updated);
  }

  Future<String?> remove(String text) async {
    final index = state.indexOf(text);
    if (index < 0) return null;
    final updated = [...state]..removeAt(index);
    await _save(updated);
    return text;
  }

  Future<void> insertAt(int index, String text) async {
    final updated = [...state];
    updated.insert(index.clamp(0, updated.length), text);
    await _save(updated.take(12).toList());
  }

  Future<void> clear() async {
    await ref.read(localRepositoryProvider).settings.delete('searchHistory');
    state = const [];
  }

  Future<void> restore(List<String> values) async {
    await _save(values.take(12).toList());
  }

  Future<void> _save(List<String> values) async {
    await ref
        .read(localRepositoryProvider)
        .settings
        .put('searchHistory', values);
    state = values;
  }
}

final searchHistoryNotifierProvider =
    StateNotifierProvider<SearchHistoryNotifier, List<String>>(
      (ref) => SearchHistoryNotifier(ref),
    );

final lyricsIndexServiceProvider = Provider<LyricsIndexService>((ref) {
  final AppCache cache = ref.watch(appCacheProvider);
  return LyricsIndexService(yt: ref.watch(ytServiceProvider), cache: cache);
});

final lyricsWarmUpProvider = FutureProvider<void>((ref) async {
  final songs = <SongModel>[
    ...ref.watch(downloadedSongsProvider),
    ...ref.watch(favoritesProvider),
    ...ref.watch(historyProvider),
  ];
  await ref.watch(lyricsIndexServiceProvider).warmUp(songs);
});

final lyricsSearchProvider = FutureProvider.autoDispose
    .family<List<LyricsHit>, String>((ref, query) async {
      await ref.watch(lyricsWarmUpProvider.future);
      return ref.watch(lyricsIndexServiceProvider).search(query);
    });

class LyricsIndexController extends StateNotifier<LyricsIndexProgress> {
  LyricsIndexController(this.service) : super(const LyricsIndexProgress());

  final LyricsIndexService service;
  bool _cancel = false;

  void cancel() => _cancel = true;

  Future<void> indexDownloads(List<SongModel> songs) async {
    _cancel = false;
    state = LyricsIndexProgress(running: true, total: songs.length);
    final result = await service.indexSongs(
      songs,
      isCancelled: () => _cancel,
      onProgress: (progress) {
        if (mounted) state = progress;
      },
    );
    if (mounted) state = result;
  }
}

final lyricsIndexControllerProvider =
    StateNotifierProvider.autoDispose<
      LyricsIndexController,
      LyricsIndexProgress
    >((ref) => LyricsIndexController(ref.watch(lyricsIndexServiceProvider)));

final spellingSuggestionProvider = Provider.autoDispose.family<String?, String>(
  (ref, query) {
    final suggestions = ref.watch(searchSuggestionsProvider(query)).valueOrNull;
    if (suggestions == null || suggestions.isEmpty) return null;
    final normalized = query.trim().toLowerCase();
    final threshold = normalized.length <= 6 ? 0.72 : 0.60;
    String? best;
    var bestScore = 0.0;
    for (final suggestion in suggestions) {
      final candidate = suggestion.text.trim();
      if (candidate.isEmpty || candidate.toLowerCase() == normalized) continue;
      final score = _similarity(normalized, candidate.toLowerCase());
      if (score >= threshold && score > bestScore) {
        bestScore = score;
        best = candidate;
      }
    }
    return best;
  },
);

double _similarity(String a, String b) {
  final maxLength = a.length > b.length ? a.length : b.length;
  if (maxLength == 0) return 1;
  return 1 - _levenshtein(a, b) / maxLength;
}

int _levenshtein(String a, String b) {
  if (a.isEmpty) return b.length;
  if (b.isEmpty) return a.length;
  var previous = List<int>.generate(b.length + 1, (index) => index);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    for (var j = 1; j <= b.length; j++) {
      final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
      final best = [
        previous[j] + 1,
        current[j - 1] + 1,
        previous[j - 1] + cost,
      ].reduce((left, right) => left < right ? left : right);
      current[j] = best;
    }
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Mezclas locales del inicio: redescubre y artistas top viven aquí porque
/// dependen de estadísticas locales y no hacen red.
final rediscoverProvider = Provider<List<SongModel>>((ref) {
  final snapshot = ref.watch(statsProvider).valueOrNull;
  final favorites = ref.watch(favoritesProvider);
  final downloads = ref.watch(downloadedSongsProvider);
  final recentIds = ref
      .watch(historyProvider)
      .take(30)
      .map((song) => song.id)
      .toSet();

  if (snapshot != null) {
    final now = DateTime.now();
    final candidates = snapshot.topSongs.where((stat) {
      if (stat.plays <= 0) return false;
      final last = stat.lastPlayed;
      return last == null || now.difference(last).inDays > 30;
    }).toList()..sort((a, b) => b.seconds.compareTo(a.seconds));
    if (candidates.isNotEmpty) {
      return candidates.take(12).map((stat) => stat.song).toList();
    }
  }

  final fallback = <SongModel>[];
  final seen = <String>{};
  for (final song in [...favorites, ...downloads]) {
    if (recentIds.contains(song.id) || !seen.add(song.id)) continue;
    fallback.add(song);
    if (fallback.length >= 12) break;
  }
  return fallback;
});

final topArtistsProvider = Provider<List<TopArtist>>((ref) {
  final snapshot = ref.watch(statsProvider).valueOrNull;
  if (snapshot == null) return const [];
  final localSongs = <SongModel>[
    ...ref.watch(downloadedSongsProvider),
    ...ref.watch(favoritesProvider),
    ...ref.watch(historyProvider),
  ];
  final ids = <String, String>{};
  final images = <String, String>{};
  for (final song in localSongs) {
    final names = song.artists;
    final artistIds = song.artistIds ?? const <String>[];
    for (var index = 0; index < names.length; index++) {
      final name = names[index].trim();
      if (name.isEmpty) continue;
      if (index < artistIds.length && artistIds[index].isNotEmpty) {
        ids.putIfAbsent(name, () => artistIds[index]);
      }
      final image = song.artworkUrl;
      if (image != null && image.isNotEmpty) {
        images.putIfAbsent(name, () => image);
      }
    }
  }
  return snapshot.topArtists
      .take(20)
      .map(
        (artist) => TopArtist(
          name: artist.name,
          id: ids[artist.name],
          imageUrl: images[artist.name],
          plays: artist.plays,
          seconds: artist.seconds,
        ),
      )
      .toList();
});

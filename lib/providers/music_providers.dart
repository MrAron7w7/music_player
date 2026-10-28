import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/yt_service.dart';
import '../data/models/song_model.dart';
import '../data/models/album_model.dart';
import '../data/models/artist_model.dart';
import '../data/repositories/music_repository.dart';
import 'library_providers.dart';

final ytServiceProvider = Provider<YtService>(
  (ref) => throw UnimplementedError('YTMusic no inicializado'),
);
final searchQueryProvider = StateProvider<String>((ref) => '');
final searchSongsProvider = StateNotifierProvider.autoDispose
    .family<SearchSongsNotifier, SearchSongsState, String>(
  (ref, query) => SearchSongsNotifier(ref, query),
);
final searchAlbumsProvider = FutureProvider.autoDispose<List<AlbumModel>>((
  ref,
) {
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty) return Future.value(const []);
  return ref.watch(ytServiceProvider).searchAlbums(q);
});
final searchArtistsProvider = FutureProvider.autoDispose<List<ArtistModel>>((
  ref,
) {
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty) return Future.value(const []);
  return ref.watch(ytServiceProvider).searchArtists(q);
});

final musicRepositoryProvider = Provider<MusicRepository>(
  (ref) => throw UnimplementedError('MusicRepository no inicializado'),
);
final albumDetailsProvider = FutureProvider.autoDispose
    .family<AlbumModel?, String>(
      (ref, albumId) => ref.watch(ytServiceProvider).getAlbum(albumId),
    );
final audioQualityProvider = StateProvider<AudioQuality>((ref) {
  final value = ref.watch(localRepositoryProvider).settings.get('audioQuality');
  return switch (value) {
    'low' => AudioQuality.low,
    'medium' => AudioQuality.medium,
    _ => AudioQuality.high,
  };
});
final autoPlayRelatedProvider = StateProvider<bool>(
  (ref) =>
      ref
              .watch(localRepositoryProvider)
              .settings
              .get('autoPlayRelated', defaultValue: true)
          as bool,
);
final searchHistoryProvider = StateProvider<List<String>>((ref) {
  final saved = ref
      .watch(localRepositoryProvider)
      .settings
      .get('searchHistory');
  return saved is List ? saved.whereType<String>().toList() : <String>[];
});
final songLyricsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>(
      (ref, videoId) => ref.watch(ytServiceProvider).getLyricsForSong(videoId),
    );

/// Estado acumulado de búsqueda de canciones con paginación.
class SearchSongsState {
  const SearchSongsState({
    this.songs = const <SongModel>[],
    this.page = 0,
    this.loadingMore = false,
    this.error,
    this.hasMore = false,
  });

  final List<SongModel> songs;
  final int page;
  final bool loadingMore;
  final Object? error;
  final bool hasMore;

  SearchSongsState copyWith({
    List<SongModel>? songs,
    int? page,
    bool? loadingMore,
    Object? error,
    bool? hasMore,
  }) {
    return SearchSongsState(
      songs: songs ?? this.songs,
      page: page ?? this.page,
      loadingMore: loadingMore ?? this.loadingMore,
      error: error ?? this.error,
      hasMore: hasMore ?? this.hasMore,
    );
  }
}

class SearchSongsNotifier extends StateNotifier<SearchSongsState> {
  SearchSongsNotifier(this.ref, this.query)
      : super(const SearchSongsState()) {
    _loadInitial();
  }

  final Ref ref;
  final String query;

  Future<void> _loadInitial() async {
    final q = query.trim();
    if (q.isEmpty) {
      state = const SearchSongsState();
      return;
    }
    state = state.copyWith(loadingMore: true, error: null);
    try {
      final songs = await ref.read(ytServiceProvider).searchSongs(q, limit: 20);
      state = SearchSongsState(
        songs: songs,
        page: 0,
        loadingMore: false,
        hasMore: songs.length == 20,
      );
    } catch (e) {
      state = state.copyWith(
        loadingMore: false,
        error: e,
      );
    }
  }

  Future<void> loadMore() async {
    if (state.loadingMore || !state.hasMore) return;
    final nextPage = state.page + 1;
    state = state.copyWith(loadingMore: true, error: null);
    try {
      final limit = (nextPage + 1) * 20;
      final more =
          await ref.read(ytServiceProvider).searchSongs(query, limit: limit);
      final existingIds = state.songs.map((song) => song.id).toSet();
      final newSongs = more.where((song) => !existingIds.contains(song.id));
      final allSongs = [...state.songs, ...newSongs];
      state = SearchSongsState(
        songs: allSongs,
        page: nextPage,
        loadingMore: false,
        hasMore: more.length == limit && newSongs.isNotEmpty,
      );
    } catch (e) {
      state = state.copyWith(loadingMore: false, error: e);
    }
  }

  Future<void> retry() async {
    state = const SearchSongsState();
    await _loadInitial();
  }
}

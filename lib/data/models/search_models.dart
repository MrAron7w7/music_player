import '../models/album_model.dart';
import '../models/artist_model.dart';
import '../models/song_model.dart';
import 'public_playlist_model.dart';

/// Ámbito activo del buscador.
enum SearchScope { catalog, library, lyrics }

extension SearchScopeX on SearchScope {
  String get label => switch (this) {
    SearchScope.catalog => 'Todo el catálogo',
    SearchScope.library => 'Mi biblioteca',
    SearchScope.lyrics => 'Letras',
  };

  String get shortLabel => switch (this) {
    SearchScope.catalog => 'Catálogo',
    SearchScope.library => 'Biblioteca',
    SearchScope.lyrics => 'Letras',
  };
}

enum SearchSort { relevance, popularity, durationAsc, durationDesc, recent, titleAsc }

extension SearchSortX on SearchSort {
  String get label => switch (this) {
    SearchSort.relevance => 'Relevancia',
    SearchSort.popularity => 'Popularidad',
    SearchSort.durationAsc => 'Duración: menor a mayor',
    SearchSort.durationDesc => 'Duración: mayor a menor',
    SearchSort.recent => 'Recientes',
    SearchSort.titleAsc => 'Título A-Z',
  };
}

enum DownloadQualityFilter { high, medium, low }

extension DownloadQualityFilterX on DownloadQualityFilter {
  String get label => switch (this) {
    DownloadQualityFilter.high => 'Alta',
    DownloadQualityFilter.medium => 'Media',
    DownloadQualityFilter.low => 'Baja',
  };

  String get apiValue => name;

  static DownloadQualityFilter? fromValue(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final item in DownloadQualityFilter.values) {
      if (item.name == value) return item;
    }
    return null;
  }
}

/// Rango de duración aplicable solo a canciones.
class DurationRange {
  const DurationRange(this.label, {this.min, this.max});

  final String label;
  final Duration? min;
  final Duration? max;

  bool matches(Duration? duration) {
    if (duration == null) return false;
    if (min != null && duration < min!) return false;
    if (max != null && duration >= max!) return false;
    return true;
  }

  static const options = <DurationRange>[
    DurationRange('Cualquiera'),
    DurationRange('Menos de 2 min', max: Duration(minutes: 2)),
    DurationRange('2 a 5 min', min: Duration(minutes: 2), max: Duration(minutes: 5)),
    DurationRange('5 a 10 min', min: Duration(minutes: 5), max: Duration(minutes: 10)),
    DurationRange('Más de 10 min', min: Duration(minutes: 10)),
  ];

  @override
  bool operator ==(Object other) =>
      other is DurationRange &&
      other.label == label &&
      other.min == min &&
      other.max == max;

  @override
  int get hashCode => Object.hash(label, min, max);
}

/// Rango de año para canciones y álbumes.
class YearRange {
  const YearRange(this.label, {this.min, this.max});

  final String label;
  final int? min;
  final int? max;

  bool matches(int? year) {
    if (year == null || year <= 0) return false;
    if (min != null && year < min!) return false;
    if (max != null && year > max!) return false;
    return true;
  }

  static const options = <YearRange>[
    YearRange('Cualquiera'),
    YearRange('2020s', min: 2020, max: 2029),
    YearRange('2010s', min: 2010, max: 2019),
    YearRange('2000s', min: 2000, max: 2009),
    YearRange('1990s', min: 1990, max: 1999),
    YearRange('1980s', min: 1980, max: 1989),
    YearRange('Antes de 1980', max: 1979),
  ];

  YearRange custom(int? from, int? to) =>
      YearRange('${from ?? '…'} – ${to ?? '…'}', min: from, max: to);

  @override
  bool operator ==(Object other) =>
      other is YearRange &&
      other.label == label &&
      other.min == min &&
      other.max == max;

  @override
  int get hashCode => Object.hash(label, min, max);
}

/// Filtros de sesión del buscador. No se persisten por defecto.
class SearchFilters {
  const SearchFilters({
    this.scope = SearchScope.catalog,
    this.onlyDownloaded = false,
    this.duration,
    this.year,
    this.genres = const <String>{},
    this.quality,
    this.sort = SearchSort.relevance,
  });

  final SearchScope scope;
  final bool onlyDownloaded;
  final DurationRange? duration;
  final YearRange? year;
  final Set<String> genres;
  final DownloadQualityFilter? quality;
  final SearchSort sort;

  bool get isEmpty =>
      scope == SearchScope.catalog &&
      !onlyDownloaded &&
      duration == null &&
      year == null &&
      genres.isEmpty &&
      quality == null &&
      sort == SearchSort.relevance;

  int get activeCount {
    var count = 0;
    if (scope != SearchScope.catalog) count++;
    if (onlyDownloaded) count++;
    if (duration != null && duration!.label != 'Cualquiera') count++;
    if (year != null && year!.label != 'Cualquiera') count++;
    if (genres.isNotEmpty) count++;
    if (quality != null) count++;
    if (sort != SearchSort.relevance) count++;
    return count;
  }

  bool get hasResultFilters => onlyDownloaded ||
      (duration != null && duration!.label != 'Cualquiera') ||
      (year != null && year!.label != 'Cualquiera') ||
      genres.isNotEmpty ||
      quality != null;

  SearchFilters copyWith({
    SearchScope? scope,
    bool? onlyDownloaded,
    DurationRange? duration,
    YearRange? year,
    Set<String>? genres,
    DownloadQualityFilter? quality,
    SearchSort? sort,
    bool clearDuration = false,
    bool clearYear = false,
    bool clearQuality = false,
    bool clearGenres = false,
  }) => SearchFilters(
    scope: scope ?? this.scope,
    onlyDownloaded: onlyDownloaded ?? this.onlyDownloaded,
    duration: clearDuration ? null : (duration ?? this.duration),
    year: clearYear ? null : (year ?? this.year),
    genres: clearGenres ? const <String>{} : (genres ?? this.genres),
    quality: clearQuality ? null : (quality ?? this.quality),
    sort: sort ?? this.sort,
  );

  String toCacheKey() {
    final genreKey = (genres.toList()..sort()).join('|');
    return '${scope.name}:${onlyDownloaded ? 1 : 0}:'
        '${duration?.label ?? '-'}:${year?.label ?? '-'}:'
        '${quality?.name ?? '-'}:${sort.name}:$genreKey';
  }

  bool matchesSong(
    SongModel song, {
    required Set<String> downloadedSongIds,
    Map<String, String> downloadQualityById = const {},
  }) {
    if (onlyDownloaded && !downloadedSongIds.contains(song.id)) return false;
    if (duration != null &&
        duration!.label != 'Cualquiera' &&
        !duration!.matches(song.duration)) {
      return false;
    }
    if (year != null &&
        year!.label != 'Cualquiera' &&
        !year!.matches(song.year)) {
      return false;
    }
    if (genres.isNotEmpty) {
      final genre = song.genre?.trim().toLowerCase();
      if (genre == null || genre.isEmpty) return false;
      final matchesAny = genres.any(
        (item) => genre.contains(item.trim().toLowerCase()),
      );
      if (!matchesAny) return false;
    }
    if (quality != null) {
      final value = downloadQualityById[song.id];
      if (value != quality!.apiValue) return false;
    }
    return true;
  }

  bool matchesAlbum(
    AlbumModel album, {
    required Set<String> downloadedAlbumIds,
  }) {
    if (onlyDownloaded && !downloadedAlbumIds.contains(album.id)) return false;
    if (year != null &&
        year!.label != 'Cualquiera' &&
        !year!.matches(album.year)) {
      return false;
    }
    if (genres.isNotEmpty) {
      final genre = album.genre?.trim().toLowerCase();
      if (genre == null || genre.isEmpty) return false;
      final matchesAny = genres.any(
        (item) => genre.contains(item.trim().toLowerCase()),
      );
      if (!matchesAny) return false;
    }
    return true;
  }

  bool matchesArtist(
    ArtistModel artist, {
    required Set<String> downloadedArtistIds,
  }) {
    if (onlyDownloaded && !downloadedArtistIds.contains(artist.id)) return false;
    return true;
  }

  bool matchesPublicPlaylist(PublicPlaylistModel playlist) {
    // La pertenencia descargada de una playlist solo se conoce al abrirla.
    return true;
  }

  /// Refina la consulta remota cuando el usuario elige un género en catálogo.
  String refineQuery(String query) {
    if (scope != SearchScope.catalog || genres.isEmpty) return query;
    return '$query ${genres.join(' ')}'.trim();
  }

  @override
  bool operator ==(Object other) =>
      other is SearchFilters &&
      other.scope == scope &&
      other.onlyDownloaded == onlyDownloaded &&
      other.duration == duration &&
      other.year == year &&
      other.quality == quality &&
      other.sort == sort &&
      other.genres.length == genres.length &&
      other.genres.containsAll(genres);

  @override
  int get hashCode => Object.hash(
    scope,
    onlyDownloaded,
    duration,
    year,
    quality,
    sort,
    Object.hashAllUnordered(genres),
  );
}

/// Resultado combinado de la pestaña “Todo”.
class SearchAllResult {
  const SearchAllResult({
    this.songs = const [],
    this.albums = const [],
    this.artists = const [],
    this.playlists = const [],
    this.best,
  });

  final List<SongModel> songs;
  final List<AlbumModel> albums;
  final List<ArtistModel> artists;
  final List<PublicPlaylistModel> playlists;
  final SearchHit? best;

  bool get isEmpty =>
      songs.isEmpty && albums.isEmpty && artists.isEmpty && playlists.isEmpty;

  int get total =>
      songs.length + albums.length + artists.length + playlists.length;

  SearchAllResult copyWith({
    List<SongModel>? songs,
    List<AlbumModel>? albums,
    List<ArtistModel>? artists,
    List<PublicPlaylistModel>? playlists,
    SearchHit? best,
    bool clearBest = false,
  }) => SearchAllResult(
    songs: songs ?? this.songs,
    albums: albums ?? this.albums,
    artists: artists ?? this.artists,
    playlists: playlists ?? this.playlists,
    best: clearBest ? null : (best ?? this.best),
  );
}

enum SearchHitType { song, album, artist, playlist }

class SearchHit {
  const SearchHit.song(SongModel this.song)
    : type = SearchHitType.song,
      album = null,
      artist = null,
      playlist = null;

  const SearchHit.album(AlbumModel this.album)
    : type = SearchHitType.album,
      song = null,
      artist = null,
      playlist = null;

  const SearchHit.artist(ArtistModel this.artist)
    : type = SearchHitType.artist,
      song = null,
      album = null,
      playlist = null;

  const SearchHit.playlist(PublicPlaylistModel this.playlist)
    : type = SearchHitType.playlist,
      song = null,
      album = null,
      artist = null;

  final SearchHitType type;
  final SongModel? song;
  final AlbumModel? album;
  final ArtistModel? artist;
  final PublicPlaylistModel? playlist;

  String get title => switch (type) {
    SearchHitType.song => song?.title ?? '',
    SearchHitType.album => album?.title ?? '',
    SearchHitType.artist => artist?.name ?? '',
    SearchHitType.playlist => playlist?.title ?? '',
  };

  String get subtitle => switch (type) {
    SearchHitType.song => song?.artists.join(', ') ?? '',
    SearchHitType.album => album?.artists.join(', ') ?? '',
    SearchHitType.artist => artist?.subscribers ?? 'Artista',
    SearchHitType.playlist =>
      playlist?.author ?? '${playlist?.itemCount ?? 0} canciones',
  };

  String? get artworkUrl => switch (type) {
    SearchHitType.song => song?.artworkUrl,
    SearchHitType.album => album?.thumbnailUrl,
    SearchHitType.artist => artist?.thumbnailUrl,
    SearchHitType.playlist => playlist?.thumbnailUrl,
  };

  String get typeLabel => switch (type) {
    SearchHitType.song => 'Canción',
    SearchHitType.album => 'Álbum',
    SearchHitType.artist => 'Artista',
    SearchHitType.playlist => 'Playlist',
  };
}

class SuggestionRun {
  const SuggestionRun(this.text, {this.bold = false});
  final String text;
  final bool bold;
}

class SearchSuggestion {
  const SearchSuggestion({
    required this.text,
    this.runs = const [],
    this.fromHistory = false,
    this.feedbackToken,
  });

  final String text;
  final List<SuggestionRun> runs;
  final bool fromHistory;
  final String? feedbackToken;

  SearchSuggestion copyWith({
    String? text,
    List<SuggestionRun>? runs,
    bool? fromHistory,
  }) => SearchSuggestion(
    text: text ?? this.text,
    runs: runs ?? this.runs,
    fromHistory: fromHistory ?? this.fromHistory,
    feedbackToken: feedbackToken,
  );
}

/// Estado genérico de una página de búsqueda paginada.
class SearchPageState<T> {
  const SearchPageState({
    this.items = const [],
    this.page = 0,
    this.loading = false,
    this.loadingMore = false,
    this.error,
    this.hasMore = false,
    this.requestId = 0,
  });

  final List<T> items;
  final int page;
  final bool loading;
  final bool loadingMore;
  final Object? error;
  final bool hasMore;
  final int requestId;

  bool get isEmpty => items.isEmpty;

  SearchPageState<T> copyWith({
    List<T>? items,
    int? page,
    bool? loading,
    bool? loadingMore,
    Object? error,
    bool? hasMore,
    int? requestId,
    bool clearError = false,
  }) => SearchPageState<T>(
    items: items ?? this.items,
    page: page ?? this.page,
    loading: loading ?? this.loading,
    loadingMore: loadingMore ?? this.loadingMore,
    error: clearError ? null : (error ?? this.error),
    hasMore: hasMore ?? this.hasMore,
    requestId: requestId ?? this.requestId,
  );
}

class SearchSelectionState {
  const SearchSelectionState({
    this.selecting = false,
    this.songIds = const <String>{},
  });

  final bool selecting;
  final Set<String> songIds;

  SearchSelectionState copyWith({
    bool? selecting,
    Set<String>? songIds,
  }) => SearchSelectionState(
    selecting: selecting ?? this.selecting,
    songIds: songIds ?? this.songIds,
  );
}

/// Estados de la hoja de filtros.
enum FilterSheetResult { applied, cleared }

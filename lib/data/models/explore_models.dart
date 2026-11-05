import 'album_model.dart';
import 'public_playlist_model.dart';
import 'song_model.dart';

/// Categoría de Moods & Genres. `params` es un token opaco de YouTube Music.
class GenreCategory {
  const GenreCategory({
    required this.title,
    required this.params,
    this.group,
  });

  final String title;
  final String params;
  final String? group;

  factory GenreCategory.fromJson(Map<String, dynamic> json, {String? group}) =>
      GenreCategory(
        title: '${json['title'] ?? 'Género'}',
        params: '${json['params'] ?? ''}',
        group: group ?? json['group'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'title': title,
    'params': params,
    'group': group,
  };
}

class TrendingItem {
  const TrendingItem({
    this.song,
    this.playlistId,
    this.playlistTitle,
  });

  final SongModel? song;
  final String? playlistId;
  final String? playlistTitle;
}

/// Resultado tipado de una sola llamada a `getExplore()`.
class ExploreBundle {
  const ExploreBundle({
    this.newReleases = const [],
    this.trending = const [],
    this.trendingPlaylistId,
    this.trendingPlaylistTitle,
    this.genres = const [],
    this.topSongs = const [],
    this.topSongsPlaylistId,
    this.newVideos = const [],
  });

  final List<AlbumModel> newReleases;
  final List<SongModel> trending;
  final String? trendingPlaylistId;
  final String? trendingPlaylistTitle;
  final List<GenreCategory> genres;
  final List<SongModel> topSongs;
  final String? topSongsPlaylistId;
  final List<SongModel> newVideos;

  bool get isEmpty =>
      newReleases.isEmpty && trending.isEmpty && genres.isEmpty && topSongs.isEmpty;
}

class ChartPlaylist {
  const ChartPlaylist({
    required this.id,
    required this.title,
    this.thumbnailUrl,
  });

  final String id;
  final String title;
  final String? thumbnailUrl;

  PublicPlaylistModel toPublicPlaylist() => PublicPlaylistModel(
    id: id,
    title: title,
    thumbnailUrl: thumbnailUrl,
  );

  factory ChartPlaylist.fromJson(Map<String, dynamic> json) {
    final raw = '${json['playlistId'] ?? json['browseId'] ?? json['id'] ?? ''}';
    return ChartPlaylist(
      id: raw.startsWith('VL') ? raw.substring(2) : raw,
      title: '${json['title'] ?? 'Lista'}',
      thumbnailUrl: PublicPlaylistModel.fromJson(json).thumbnailUrl,
    );
  }
}

class ChartArtist {
  const ChartArtist({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.subscribers,
    this.rank,
    this.trend,
  });

  final String id;
  final String name;
  final String? thumbnailUrl;
  final String? subscribers;
  final int? rank;
  final String? trend;

  factory ChartArtist.fromJson(Map<String, dynamic> json) => ChartArtist(
    id: '${json['browseId'] ?? json['id'] ?? ''}',
    name: '${json['title'] ?? json['name'] ?? 'Artista'}',
    thumbnailUrl: PublicPlaylistModel.fromJson(json).thumbnailUrl,
    subscribers: json['subscribers']?.toString(),
    rank: int.tryParse('${json['rank'] ?? ''}'),
    trend: json['trend'] as String?,
  );
}

class ChartsSnapshot {
  const ChartsSnapshot({
    this.country = 'ZZ',
    this.selectedCountry,
    this.countryOptions = const [],
    this.playlists = const [],
    this.artists = const [],
  });

  final String country;
  final String? selectedCountry;

  /// Tokens opacos que devuelve YouTube Music para el selector de país.
  final List<String> countryOptions;
  final List<ChartPlaylist> playlists;
  final List<ChartArtist> artists;

  bool get isEmpty => playlists.isEmpty && artists.isEmpty;
}

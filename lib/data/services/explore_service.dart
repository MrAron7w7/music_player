import '../models/album_model.dart';
import '../models/explore_models.dart';
import '../models/public_playlist_model.dart';
import '../models/song_model.dart';
import 'yt_service.dart';

/// Fachada tipada sobre las respuestas de Explore, Moods & Genres y Charts.
/// Toda la caché (memoria + disco, TTL y límites) vive en [YtService].
class ExploreService {
  ExploreService(this.yt);

  final YtService yt;

  Future<ExploreBundle> getExploreBundle() async {
    final raw = await yt.getExploreRaw();

    final newReleases = _albums(raw['new_releases']);
    final trendingBlock = raw['trending'];
    final trending = trendingBlock is Map
        ? _songs(trendingBlock['items'])
        : const <SongModel>[];
    final topBlock = raw['top_songs'];
    final topSongs = topBlock is Map
        ? _songs(topBlock['items'])
        : const <SongModel>[];
    final genres = (raw['moods_and_genres'] as List? ?? const [])
        .whereType<Map>()
        .map(
          (entry) => GenreCategory.fromJson(
            Map<String, dynamic>.from(entry),
            group: 'Moods & Genres',
          ),
        )
        .where((genre) => genre.params.isNotEmpty)
        .toList();
    final newVideos = _songs(raw['new_videos']);

    return ExploreBundle(
      newReleases: newReleases,
      trending: trending,
      trendingPlaylistId: trendingBlock is Map
          ? _cleanPlaylistId('${trendingBlock['playlist'] ?? ''}')
          : null,
      genres: genres,
      topSongs: topSongs,
      topSongsPlaylistId: topBlock is Map
          ? _cleanPlaylistId('${topBlock['playlist'] ?? ''}')
          : null,
      newVideos: newVideos,
    );
  }

  Future<List<GenreCategory>> getMoodCategories() async {
    final raw = await yt.getMoodCategoriesRaw();
    final result = <GenreCategory>[];
    final seen = <String>{};
    for (final entry in raw.entries) {
      final group = entry.key;
      final items = entry.value;
      if (items is! List) continue;
      for (final item in items.whereType<Map>()) {
        final genre = GenreCategory.fromJson(
          Map<String, dynamic>.from(item),
          group: group,
        );
        if (genre.params.isEmpty || !seen.add(genre.params)) continue;
        result.add(genre);
      }
    }
    return result;
  }

  Future<List<PublicPlaylistModel>> getGenrePlaylists(String params) async {
    if (params.trim().isEmpty) return const [];
    final raw = await yt.getMoodPlaylistsRaw(params);
    final seen = <String>{};
    final result = <PublicPlaylistModel>[];
    for (final entry in raw) {
      final playlist = PublicPlaylistModel.fromJson(entry);
      if (playlist.id.isEmpty || !seen.add(playlist.id)) continue;
      result.add(playlist);
    }
    return result;
  }

  Future<ChartsSnapshot> getCharts(String country) async {
    final raw = await yt.getChartsRaw(country);
    final playlists = <ChartPlaylist>[];
    final seen = <String>{};
    for (final key in const [
      'videos',
      'daily',
      'weekly',
      'genres',
      'languages',
    ]) {
      final value = raw[key];
      if (value is! List) continue;
      for (final item in value.whereType<Map>()) {
        final playlist = ChartPlaylist.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (playlist.id.isEmpty || !seen.add(playlist.id)) continue;
        playlists.add(playlist);
      }
    }

    final artists = <ChartArtist>[];
    final seenArtists = <String>{};
    for (final item in (raw['artists'] as List? ?? const []).whereType<Map>()) {
      final artist = ChartArtist.fromJson(Map<String, dynamic>.from(item));
      if (artist.id.isEmpty || !seenArtists.add(artist.id)) continue;
      artists.add(artist);
    }
    artists.sort((a, b) => (a.rank ?? 999).compareTo(b.rank ?? 999));

    final countries = raw['countries'];
    final selected = countries is Map ? countries['selected']?.toString() : null;
    final options = countries is Map && countries['options'] is List
        ? (countries['options'] as List).whereType<String>().toList()
        : const <String>[];

    return ChartsSnapshot(
      country: country,
      selectedCountry: selected,
      countryOptions: options,
      playlists: playlists,
      artists: artists,
    );
  }

  List<AlbumModel> _albums(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <AlbumModel>[];
    for (final entry in value.whereType<Map>()) {
      final album = AlbumModel.fromJson(Map<String, dynamic>.from(entry));
      if (album.id.isEmpty || !seen.add(album.id)) continue;
      result.add(album);
    }
    return result;
  }

  List<SongModel> _songs(dynamic value) {
    if (value is! List) return const [];
    final seen = <String>{};
    final result = <SongModel>[];
    for (final entry in value.whereType<Map>()) {
      final song = SongModel.fromJson(Map<String, dynamic>.from(entry));
      if (song.id.isEmpty || !seen.add(song.id)) continue;
      if (song.id.startsWith('MPED') ||
          song.id.startsWith('MPRE') ||
          song.id.startsWith('MPLA')) {
        continue;
      }
      result.add(song);
    }
    return result;
  }

  String? _cleanPlaylistId(String raw) {
    if (raw.isEmpty) return null;
    final id = raw.startsWith('VL') ? raw.substring(2) : raw;
    return id.isEmpty ? null : id;
  }
}

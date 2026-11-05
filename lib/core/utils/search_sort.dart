import '../../data/models/album_model.dart';
import '../../data/models/artist_model.dart';
import '../../data/models/public_playlist_model.dart';
import '../../data/models/search_models.dart';
import '../../data/models/song_model.dart';
import 'text_utils.dart';

int _compareNormalized(String a, String b) =>
    normalize(a).compareTo(normalize(b));

List<SongModel> sortSongs(
  List<SongModel> songs,
  SearchSort sort, {
  Map<String, int> localPlays = const {},
}) {
  final result = List<SongModel>.from(songs);
  switch (sort) {
    case SearchSort.relevance:
      return result;
    case SearchSort.popularity:
      final hasPlays = result.any((song) => (localPlays[song.id] ?? 0) > 0);
      if (!hasPlays) return result;
      result.sort((a, b) {
        final byPlays = (localPlays[b.id] ?? 0).compareTo(localPlays[a.id] ?? 0);
        if (byPlays != 0) return byPlays;
        return _compareNormalized(a.title, b.title);
      });
      return result;
    case SearchSort.durationAsc:
      result.sort((a, b) {
        final left = a.duration;
        final right = b.duration;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return left.compareTo(right);
      });
      return result;
    case SearchSort.durationDesc:
      result.sort((a, b) {
        final left = a.duration;
        final right = b.duration;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
      return result;
    case SearchSort.recent:
      result.sort((a, b) {
        final left = a.year;
        final right = b.year;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
      return result;
    case SearchSort.titleAsc:
      result.sort((a, b) => _compareNormalized(a.title, b.title));
      return result;
  }
}

List<AlbumModel> sortAlbums(List<AlbumModel> albums, SearchSort sort) {
  final result = List<AlbumModel>.from(albums);
  switch (sort) {
    case SearchSort.recent:
      result.sort((a, b) {
        final left = a.year;
        final right = b.year;
        if (left == null && right == null) return 0;
        if (left == null) return 1;
        if (right == null) return -1;
        return right.compareTo(left);
      });
    case SearchSort.titleAsc:
      result.sort((a, b) => _compareNormalized(a.title, b.title));
    case SearchSort.relevance:
    case SearchSort.popularity:
    case SearchSort.durationAsc:
    case SearchSort.durationDesc:
      return result;
  }
  return result;
}

List<ArtistModel> sortArtists(List<ArtistModel> artists, SearchSort sort) {
  final result = List<ArtistModel>.from(artists);
  if (sort == SearchSort.titleAsc) {
    result.sort((a, b) => _compareNormalized(a.name, b.name));
  }
  return result;
}

List<PublicPlaylistModel> sortPublicPlaylists(
  List<PublicPlaylistModel> playlists,
  SearchSort sort,
) {
  final result = List<PublicPlaylistModel>.from(playlists);
  if (sort == SearchSort.titleAsc) {
    result.sort((a, b) => _compareNormalized(a.title, b.title));
  }
  return result;
}

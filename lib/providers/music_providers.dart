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
final searchResultsProvider = FutureProvider.autoDispose<List<SongModel>>((
  ref,
) {
  final q = ref.watch(searchQueryProvider).trim();
  if (q.isEmpty) return Future.value(const []);
  return ref.watch(ytServiceProvider).searchSongs(q);
});
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

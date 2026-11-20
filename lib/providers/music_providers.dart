import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services/yt_service.dart';
import '../data/models/album_model.dart';
import '../data/models/artist_model.dart';
import '../data/repositories/music_repository.dart';
import 'library_providers.dart';

final ytServiceProvider = Provider<YtService>(
  (ref) => throw UnimplementedError('YTMusic no inicializado'),
);
final searchQueryProvider = StateProvider<String>((ref) => '');
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
final songLyricsProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>?, String>(
      (ref, videoId) => ref.watch(ytServiceProvider).getLyricsForSong(videoId),
    );

final artistPageProvider = FutureProvider.autoDispose
    .family<ArtistPageModel, String>(
      (ref, id) => ref.watch(ytServiceProvider).getArtistPage(id),
    );

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';

import '../data/repositories/local_repository.dart';
import '../data/models/song_model.dart';
import '../data/models/playlist_model.dart';
import 'player_providers.dart';

final localRepositoryProvider = Provider<LocalRepository>(
  (ref) => throw UnimplementedError('Hive no inicializado'),
);
final _favoriteBoxChangesProvider = StreamProvider<int>((ref) async* {
  final box = ref.watch(localRepositoryProvider).favorites;
  var revision = 0;
  yield revision;
  await for (final _ in box.watch()) {
    yield ++revision;
  }
});
final favoriteIdsProvider = Provider<Set<String>>((ref) {
  ref.watch(_favoriteBoxChangesProvider);
  final Box box = ref.watch(localRepositoryProvider).favorites;
  return box.keys.whereType<String>().toSet();
});
final favoritesProvider = Provider<List<SongModel>>((ref) {
  ref.watch(_favoriteBoxChangesProvider);
  return ref.watch(localRepositoryProvider).getFavorites();
});
final isFavoriteProvider = Provider.autoDispose.family<bool, String>(
  (ref, songId) => ref.watch(favoriteIdsProvider).contains(songId),
);
final playlistsProvider = Provider<List<PlaylistModel>>(
  (ref) => ref.watch(localRepositoryProvider).getPlaylists(),
);
final historyChangesProvider = StreamProvider<void>(
  (ref) => ref.watch(audioHandlerProvider).historyChanges,
);

final historyProvider = Provider<List<SongModel>>((ref) {
  // El handler escribe el historial al cambiar de canción, incluso cuando el
  // avance ocurre desde la notificación o al terminar una pista. Escuchar sus
  // cambios mantiene la biblioteca sincronizada sin acoplarla al motor.
  ref.watch(historyChangesProvider);
  return ref.watch(localRepositoryProvider).getHistory();
});

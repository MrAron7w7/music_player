import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/repositories/local_repository.dart';
import '../data/models/song_model.dart';
import '../data/models/playlist_model.dart';
import 'player_providers.dart';

final localRepositoryProvider = Provider<LocalRepository>(
  (ref) => throw UnimplementedError('Hive no inicializado'),
);
final favoritesProvider = Provider<List<SongModel>>(
  (ref) => ref.watch(localRepositoryProvider).getFavorites(),
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
  ref.watch(currentSongProvider.select((state) => state.valueOrNull?.id));
  return ref.watch(localRepositoryProvider).getHistory();
});

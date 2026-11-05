import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/home_models.dart';
import '../data/repositories/followed_artists_repository.dart';

final followedArtistsRepositoryProvider = Provider<FollowedArtistsRepository>(
  (ref) => throw UnimplementedError('FollowedArtistsRepository no inicializado'),
);

class FollowedArtistsNotifier extends StateNotifier<List<FollowedArtist>> {
  FollowedArtistsNotifier(this.repository) : super(repository.list());

  final FollowedArtistsRepository repository;

  Future<bool> toggle(FollowedArtist artist) async {
    final following = await repository.toggle(artist);
    state = repository.list();
    return following;
  }

  Future<void> remove(String id) async {
    await repository.remove(id);
    state = repository.list();
  }

  Future<void> clear() async {
    await repository.clear();
    state = const [];
  }

  void refresh() => state = repository.list();
}

final followedArtistsProvider =
    StateNotifierProvider<FollowedArtistsNotifier, List<FollowedArtist>>(
      (ref) => FollowedArtistsNotifier(
        ref.watch(followedArtistsRepositoryProvider),
      ),
    );

final isFollowingArtistProvider = Provider.family<bool, String>((ref, id) {
  if (id.isEmpty) return false;
  return ref.watch(
    followedArtistsProvider.select(
      (artists) => artists.any((artist) => artist.id == id),
    ),
  );
});

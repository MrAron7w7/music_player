import 'package:hive/hive.dart';

import '../models/home_models.dart';

/// Seguimiento local de artistas. No se sincroniza con YouTube Music: el
/// paquete no expone una suscripción de cuenta.
class FollowedArtistsRepository {
  FollowedArtistsRepository(this.box);

  final Box box;

  List<FollowedArtist> list() {
    final result = box.values
        .whereType<Map>()
        .map((entry) => FollowedArtist.fromJson(Map<String, dynamic>.from(entry)))
        .where((artist) => artist.id.isNotEmpty)
        .toList();
    result.sort((a, b) => b.followedAt.compareTo(a.followedAt));
    return result;
  }

  bool isFollowing(String id) => box.containsKey(id);

  FollowedArtist? byId(String id) {
    final raw = box.get(id);
    if (raw is! Map) return null;
    return FollowedArtist.fromJson(Map<String, dynamic>.from(raw));
  }

  Future<bool> toggle(FollowedArtist artist) async {
    if (box.containsKey(artist.id)) {
      await box.delete(artist.id);
      return false;
    }
    await box.put(
      artist.id,
      FollowedArtist(
        id: artist.id,
        name: artist.name,
        thumbnailUrl: artist.thumbnailUrl,
        followedAt: DateTime.now(),
      ).toJson(),
    );
    return true;
  }

  Future<void> remove(String id) => box.delete(id);
  Future<void> clear() => box.clear();

  Stream<void> get changes => box.watch().map((_) {});
}

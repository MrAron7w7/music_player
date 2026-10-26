import 'package:hive/hive.dart';
import 'package:uuid/uuid.dart';

import '../models/song_model.dart';
import '../models/playlist_model.dart';

class LocalRepository {
  LocalRepository(this.favorites, this.playlists, this.history, this.settings);
  final Box favorites, playlists, history, settings;
  final _uuid = const Uuid();
  List<SongModel> getFavorites() => favorites.values
      .whereType<Map>()
      .map((e) => SongModel.fromJson(Map<String, dynamic>.from(e)))
      .toList();
  List<PlaylistModel> getPlaylists() => playlists.values
      .whereType<Map>()
      .map((e) => PlaylistModel.fromJson(Map<String, dynamic>.from(e)))
      .toList();
  List<SongModel> getHistory() => history.values
      .whereType<Map>()
      .map((e) => SongModel.fromJson(Map<String, dynamic>.from(e)))
      .toList()
      .reversed
      .toList();
  Future<void> toggleFavorite(SongModel s) async {
    if (favorites.containsKey(s.id)) {
      await favorites.delete(s.id);
    } else {
      await favorites.put(s.id, s.toJson());
    }
  }

  Future<void> addHistory(SongModel s) async {
    await history.delete(s.id);
    await history.put(s.id, s.toJson());
    while (history.length > 100) {
      await history.deleteAt(0);
    }
  }

  Future<void> removeFavorites(Iterable<String> ids) =>
      favorites.deleteAll(ids);
  Future<void> removeHistory(Iterable<String> ids) => history.deleteAll(ids);

  Future<PlaylistModel> createPlaylist(
    String name, {
    String? description,
    List<SongModel> songs = const [],
  }) async {
    final now = DateTime.now();
    final p = PlaylistModel(
      id: _uuid.v4(),
      name: name,
      description: description,
      songs: songs,
      createdAt: now,
      updatedAt: now,
      coverUrl: songs.firstOrNull?.artworkUrl,
    );
    await playlists.put(p.id, p.toJson());
    return p;
  }

  Future<void> updatePlaylist(
    PlaylistModel playlist, {
    List<SongModel>? songs,
    String? name,
    String? coverUrl,
  }) {
    final updated = PlaylistModel(
      id: playlist.id,
      name: name ?? playlist.name,
      description: playlist.description,
      songs: songs ?? playlist.songs,
      createdAt: playlist.createdAt,
      updatedAt: DateTime.now(),
      coverUrl: coverUrl ?? playlist.coverUrl,
    );
    return savePlaylist(updated);
  }

  Future<void> savePlaylist(PlaylistModel p) => playlists.put(p.id, p.toJson());
  Future<void> deletePlaylist(String id) => playlists.delete(id);
  Future<void> clearHistory() => history.clear();
}

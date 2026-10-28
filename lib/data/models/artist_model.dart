import 'album_model.dart';
import 'song_model.dart';

class ArtistModel {
  const ArtistModel({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    this.subscribers,
    this.description,
  });
  final String id, name;
  final String? thumbnailUrl, subscribers, description;
  factory ArtistModel.fromJson(Map<String, dynamic> j) => ArtistModel(
    id: '${j['browseId'] ?? j['id'] ?? ''}',
    name: '${j['artist'] ?? j['name'] ?? j['title'] ?? 'Artista'}',
    thumbnailUrl: _thumb(j['thumbnails']),
    subscribers: j['subscribers'] as String?,
    description: j['description'] as String?,
  );
  static String? _thumb(dynamic t) => t is List && t.isNotEmpty && t.last is Map
      ? (t.last as Map)['url'] as String?
      : null;
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'thumbnailUrl': thumbnailUrl,
    'subscribers': subscribers,
    'description': description,
  };
}

/// Página de artista: nombre, portada, canciones top y álbumes.
class ArtistPageModel {
  const ArtistPageModel({
    required this.name,
    required this.thumb,
    this.cancionesTop = const <SongModel>[],
    this.albumes = const <AlbumModel>[],
  });

  final String name;
  final String? thumb;
  final List<SongModel> cancionesTop;
  final List<AlbumModel> albumes;
}

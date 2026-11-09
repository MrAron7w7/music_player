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

/// Página de artista: nombre, portada, canciones y álbumes.
class ArtistPageModel {
  const ArtistPageModel({
    required this.name,
    required this.thumb,
    this.cancionesTop = const <SongModel>[],
    this.canciones = const <SongModel>[],
    this.albumes = const <AlbumModel>[],
  });

  final String name;
  final String? thumb;

  /// Éxitos principales que devuelve la cabecera del artista.
  final List<SongModel> cancionesTop;

  /// Catálogo completo del artista. Puede estar vacío en respuestas antiguas
  /// o cuando YouTube no expone la playlist "Todas las canciones".
  final List<SongModel> canciones;

  final List<AlbumModel> albumes;

  /// Lista que debe mostrar la página, priorizando el catálogo completo.
  List<SongModel> get todasLasCanciones =>
      canciones.isNotEmpty ? canciones : cancionesTop;

  bool get tieneContenido =>
      cancionesTop.isNotEmpty || canciones.isNotEmpty || albumes.isNotEmpty;
}

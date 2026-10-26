import 'song_model.dart';

class AlbumModel {
  const AlbumModel({
    required this.id,
    required this.title,
    this.artists = const [],
    this.year,
    this.thumbnailUrl,
    this.songCount,
    this.songs,
  });
  final String id, title;
  final List<String> artists;
  final int? year, songCount;
  final String? thumbnailUrl;
  final List<SongModel>? songs;
  factory AlbumModel.fromJson(Map<String, dynamic> j) => AlbumModel(
    id: '${j['browseId'] ?? j['id'] ?? ''}',
    title: '${j['title'] ?? 'Álbum'}',
    artists: j['artists'] is List
        ? (j['artists'] as List)
              .map((e) => e is Map ? '${e['name']}' : '$e')
              .toList()
        : j['artist'] != null
        ? ['${j['artist']}']
        : const [],
    year: int.tryParse('${j['year'] ?? ''}'),
    thumbnailUrl:
        j['thumbnailUrl'] as String? ?? SongModel.fromJson(j).thumbnailUrl,
    songCount: int.tryParse('${j['songCount'] ?? j['trackCount'] ?? ''}'),
    songs: ((j['songs'] ?? j['tracks']) as List?)
        ?.whereType<Map>()
        .map((e) => SongModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artists': artists,
    'year': year,
    'thumbnailUrl': thumbnailUrl,
    'songCount': songCount,
    'songs': songs?.map((e) => e.toJson()).toList(),
  };
}

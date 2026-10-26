import 'song_model.dart';

class PlaylistModel {
  const PlaylistModel({
    required this.id,
    required this.name,
    this.description,
    this.songs = const [],
    required this.createdAt,
    required this.updatedAt,
    this.coverUrl,
  });
  final String id, name;
  final String? description, coverUrl;
  final List<SongModel> songs;
  final DateTime createdAt, updatedAt;
  factory PlaylistModel.fromJson(Map<String, dynamic> j) => PlaylistModel(
    id: '${j['id']}',
    name: '${j['name']}',
    description: j['description'] as String?,
    songs: (j['songs'] as List? ?? const [])
        .whereType<Map>()
        .map((e) => SongModel.fromJson(Map<String, dynamic>.from(e)))
        .toList(),
    createdAt: DateTime.tryParse('${j['createdAt']}') ?? DateTime.now(),
    updatedAt: DateTime.tryParse('${j['updatedAt']}') ?? DateTime.now(),
    coverUrl: j['coverUrl'] as String?,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'description': description,
    'songs': songs.map((e) => e.toJson()).toList(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'coverUrl': coverUrl ?? songs.firstOrNull?.thumbnailUrl,
  };
}

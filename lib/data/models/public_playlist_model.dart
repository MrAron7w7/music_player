import 'song_model.dart';

/// Playlist pública de YouTube Music. Se mantiene separada de `PlaylistModel`
/// porque su ciclo de vida es remoto y no se guarda en Hive hasta que el
/// usuario decide copiarla a su biblioteca.
class PublicPlaylistModel {
  const PublicPlaylistModel({
    required this.id,
    required this.title,
    this.author,
    this.description,
    this.thumbnailUrl,
    this.itemCount,
    this.year,
    this.durationSeconds,
    this.isOfficial = false,
  });

  final String id;
  final String title;
  final String? author;
  final String? description;
  final String? thumbnailUrl;
  final int? itemCount;
  final String? year;
  final int? durationSeconds;
  final bool isOfficial;

  factory PublicPlaylistModel.fromJson(Map<String, dynamic> json) {
    final rawId = '${json['browseId'] ?? json['playlistId'] ?? json['id'] ?? ''}';
    final id = rawId.startsWith('VL') ? rawId.substring(2) : rawId;

    String? author;
    final rawAuthor = json['author'] ?? json['collaborators'];
    if (rawAuthor is String && rawAuthor.trim().isNotEmpty) {
      author = rawAuthor.trim();
    } else if (rawAuthor is Map) {
      final name = '${rawAuthor['name'] ?? rawAuthor['text'] ?? ''}'.trim();
      if (name.isNotEmpty) author = name;
    } else if (rawAuthor is List) {
      final names = rawAuthor
          .whereType<Map>()
          .map((entry) => '${entry['name'] ?? entry['text'] ?? ''}'.trim())
          .where((name) => name.isNotEmpty)
          .toList();
      if (names.isNotEmpty) author = names.join(', ');
    }

    final rawCount =
        json['itemCount'] ?? json['count'] ?? json['trackCount'] ?? json['songCount'];
    final count = rawCount is int
        ? rawCount
        : int.tryParse('${rawCount ?? ''}'.replaceAll(RegExp(r'[^0-9]'), ''));
    final rawDuration =
        json['durationSeconds'] ??
        json['duration_seconds'] ??
        json['duration'];

    return PublicPlaylistModel(
      id: id,
      title: '${json['title'] ?? json['name'] ?? 'Playlist'}',
      author: author,
      description: json['description'] as String?,
      thumbnailUrl: _thumbnail(json['thumbnails'] ?? json['thumbnail']),
      itemCount: count,
      year: json['year']?.toString(),
      durationSeconds: rawDuration is int
          ? rawDuration
          : _parseDurationSeconds(rawDuration),
      isOfficial: json['isOfficial'] == true,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'author': author,
    'description': description,
    'thumbnailUrl': thumbnailUrl,
    'itemCount': itemCount,
    'year': year,
    'durationSeconds': durationSeconds,
    'isOfficial': isOfficial,
  };

  PublicPlaylistModel copyWith({
    String? id,
    String? title,
    String? author,
    String? description,
    String? thumbnailUrl,
    int? itemCount,
    String? year,
    int? durationSeconds,
    bool? isOfficial,
  }) => PublicPlaylistModel(
    id: id ?? this.id,
    title: title ?? this.title,
    author: author ?? this.author,
    description: description ?? this.description,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    itemCount: itemCount ?? this.itemCount,
    year: year ?? this.year,
    durationSeconds: durationSeconds ?? this.durationSeconds,
    isOfficial: isOfficial ?? this.isOfficial,
  );

  String get durationLabel {
    final seconds = durationSeconds;
    if (seconds == null || seconds <= 0) return '';
    final duration = Duration(seconds: seconds);
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    if (hours > 0) return '$hours h $minutes min';
    return '${duration.inMinutes} min';
  }

  static String? _thumbnail(dynamic value) {
    if (value is String && value.isNotEmpty) return value;
    if (value is Map) return value['url'] as String?;
    if (value is! List || value.isEmpty) return null;
    for (final item in value.reversed) {
      if (item is Map && item['url'] is String) return item['url'] as String;
    }
    return null;
  }

  static int? _parseDurationSeconds(dynamic value) {
    if (value is int) return value;
    if (value is! String || value.trim().isEmpty) return null;
    final matches = RegExp(r'\d+').allMatches(value).toList();
    if (matches.isEmpty) return null;
    final numbers = matches
        .map((match) => int.tryParse(match.group(0)!) ?? 0)
        .toList();
    final lower = value.toLowerCase();
    if (lower.contains('h') || lower.contains('hora')) {
      final hours = numbers.isNotEmpty ? numbers[0] : 0;
      final minutes = numbers.length > 1 ? numbers[1] : 0;
      return hours * 3600 + minutes * 60;
    }
    if (lower.contains('min')) return numbers[0] * 60;
    return numbers[0];
  }
}

class PublicPlaylistPage {
  const PublicPlaylistPage({required this.playlist, required this.songs});

  final PublicPlaylistModel playlist;
  final List<SongModel> songs;

  Map<String, dynamic> toJson() => {
    'playlist': playlist.toJson(),
    'songs': songs.map((song) => song.toJson()).toList(),
  };

  factory PublicPlaylistPage.fromJson(Map<String, dynamic> json) =>
      PublicPlaylistPage(
        playlist: PublicPlaylistModel.fromJson(
          Map<String, dynamic>.from(json['playlist'] as Map? ?? const {}),
        ),
        songs: (json['songs'] as List? ?? const [])
            .whereType<Map>()
            .map((song) => SongModel.fromJson(Map<String, dynamic>.from(song)))
            .where((song) => song.id.isNotEmpty)
            .toList(),
      );

  PublicPlaylistPage copyWith({
    PublicPlaylistModel? playlist,
    List<SongModel>? songs,
  }) => PublicPlaylistPage(
    playlist: playlist ?? this.playlist,
    songs: songs ?? this.songs,
  );
}

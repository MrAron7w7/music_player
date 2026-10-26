import 'package:flutter/foundation.dart';

@immutable
class SongModel {
  const SongModel({
    required this.id,
    required this.title,
    this.artists = const [],
    this.artistIds,
    this.album,
    this.albumId,
    this.duration,
    this.thumbnailUrl,
    this.highResThumbnailUrl,
    this.isExplicit = false,
    this.year,
  });
  final String id;
  final String title;
  final List<String> artists;
  final List<String>? artistIds;
  final String? album;
  final String? albumId;
  final Duration? duration;
  final String? thumbnailUrl;
  final String? highResThumbnailUrl;
  final bool isExplicit;
  final int? year;
  String? get artworkUrl {
    final source = highResThumbnailUrl ?? thumbnailUrl;
    if (source == null || source.isEmpty) {
      return id.isEmpty ? null : 'https://i.ytimg.com/vi/$id/maxresdefault.jpg';
    }
    final uri = Uri.tryParse(source);
    if (uri == null) return source;
    if (uri.host == 'i.ytimg.com' && uri.pathSegments.length >= 3) {
      final path = [...uri.pathSegments]..[2] = 'maxresdefault.jpg';
      return uri.replace(pathSegments: path).toString();
    }
    return source.replaceFirst(
      RegExp(r'=w\d+-h\d+[^&]*'),
      '=w1200-h1200-l90-rj',
    );
  }

  factory SongModel.fromJson(Map<String, dynamic> j) {
    final artistEntries = (j['artists'] as List? ?? const [])
        .whereType<Map>()
        .toList();
    final artists = (j['artists'] as List? ?? const [])
        .map((e) => e is Map ? '${e['name'] ?? ''}' : '$e')
        .where((e) => e.isNotEmpty)
        .toList();
    final rawArtistIds = (j['artistIds'] as List?)
        ?.whereType<String>()
        .where((id) => id.isNotEmpty)
        .toList();
    final providedArtistIds = rawArtistIds ?? const <String>[];
    final artistIds = providedArtistIds.isNotEmpty
        ? providedArtistIds
        : artistEntries
              .map((entry) => entry['id'])
              .whereType<String>()
              .where((id) => id.isNotEmpty)
              .toSet()
              .toList();
    final album = j['album'];
    final durationSeconds = j['durationSeconds'] ?? j['duration_seconds'];

    return SongModel(
      id: j['id'] as String? ?? j['videoId'] as String? ?? '',
      title: j['title'] as String? ?? 'Sin título',
      artists: artists,
      artistIds: artistIds.isEmpty ? null : artistIds,
      album: album is Map ? (album['name'] as String?) : album as String?,
      albumId:
          j['albumId'] as String? ??
          (album is Map ? album['id'] as String? : null),
      duration: durationSeconds is int
          ? Duration(seconds: durationSeconds)
          : _durationFromLength(j['length']),
      thumbnailUrl:
          j['thumbnailUrl'] as String? ??
          _thumb(j['thumbnail']) ??
          _thumb(j['thumbnails']),
      highResThumbnailUrl: j['highResThumbnailUrl'] as String?,
      isExplicit: j['isExplicit'] as bool? ?? false,
      year: j['year'] is int
          ? j['year'] as int
          : int.tryParse('${j['year'] ?? ''}'),
    );
  }

  static Duration? _durationFromLength(dynamic value) {
    if (value is! String || value.trim().isEmpty) return null;
    final parts = value.trim().split(':');
    if (parts.length < 2 || parts.length > 3) return null;
    final numbers = parts.map(int.tryParse).toList();
    if (numbers.any((part) => part == null || part < 0)) return null;
    var seconds = 0;
    for (final part in numbers) {
      seconds = seconds * 60 + part!;
    }
    return Duration(seconds: seconds);
  }

  static String? _thumb(dynamic value) {
    if (value is List && value.isNotEmpty) {
      final items = value.whereType<Map>().toList()
        ..sort((a, b) {
          final aArea =
              (int.tryParse('${a['width']}') ?? 0) *
              (int.tryParse('${a['height']}') ?? 0);
          final bArea =
              (int.tryParse('${b['width']}') ?? 0) *
              (int.tryParse('${b['height']}') ?? 0);
          return bArea.compareTo(aArea);
        });
      if (items.isNotEmpty) return items.first['url'] as String?;
    }
    return null;
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'artists': artists,
    'artistIds': artistIds,
    'album': album,
    'albumId': albumId,
    'durationSeconds': duration?.inSeconds,
    'thumbnailUrl': thumbnailUrl,
    'highResThumbnailUrl': highResThumbnailUrl,
    'isExplicit': isExplicit,
    'year': year,
  };
  SongModel copyWith({
    String? id,
    String? title,
    List<String>? artists,
    List<String>? artistIds,
    String? album,
    String? albumId,
    Duration? duration,
    String? thumbnailUrl,
    String? highResThumbnailUrl,
    bool? isExplicit,
    int? year,
  }) => SongModel(
    id: id ?? this.id,
    title: title ?? this.title,
    artists: artists ?? this.artists,
    artistIds: artistIds ?? this.artistIds,
    album: album ?? this.album,
    albumId: albumId ?? this.albumId,
    duration: duration ?? this.duration,
    thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    highResThumbnailUrl: highResThumbnailUrl ?? this.highResThumbnailUrl,
    isExplicit: isExplicit ?? this.isExplicit,
    year: year ?? this.year,
  );
  @override
  bool operator ==(Object other) => other is SongModel && id == other.id;
  @override
  int get hashCode => id.hashCode;
}

import 'song_model.dart';

/// Mezcla diaria generada localmente y cacheada por fecha.
class DailyMix {
  const DailyMix({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.coverUrls,
    required this.songs,
    required this.generatedAt,
    this.isOffline = false,
    this.seedArtist,
  });

  final String id;
  final String title;
  final String subtitle;
  final List<String> coverUrls;
  final List<SongModel> songs;
  final DateTime generatedAt;
  final bool isOffline;
  final String? seedArtist;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'subtitle': subtitle,
    'coverUrls': coverUrls,
    'songs': songs.map((song) => song.toJson()).toList(),
    'generatedAt': generatedAt.toIso8601String(),
    'isOffline': isOffline,
    'seedArtist': seedArtist,
  };

  factory DailyMix.fromJson(Map<String, dynamic> json) => DailyMix(
    id: '${json['id']}',
    title: '${json['title'] ?? 'Mix'}',
    subtitle: '${json['subtitle'] ?? ''}',
    coverUrls: (json['coverUrls'] as List? ?? const [])
        .whereType<String>()
        .where((url) => url.isNotEmpty)
        .toList(),
    songs: (json['songs'] as List? ?? const [])
        .whereType<Map>()
        .map((song) => SongModel.fromJson(Map<String, dynamic>.from(song)))
        .where((song) => song.id.isNotEmpty)
        .toList(),
    generatedAt:
        DateTime.tryParse('${json['generatedAt']}') ?? DateTime.now(),
    isOffline: json['isOffline'] == true,
    seedArtist: json['seedArtist'] as String?,
  );
}

/// Configuración local de una mezcla por estado de ánimo/actividad.
class MoodMixConfig {
  const MoodMixConfig({
    required this.id,
    required this.title,
    required this.keywords,
    required this.fallbackQuery,
  });

  final String id;
  final String title;
  final List<String> keywords;
  final String fallbackQuery;
}

class MoodMix {
  const MoodMix({
    required this.id,
    required this.title,
    required this.subtitle,
    this.genreParams,
    this.fallbackQuery,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? genreParams;
  final String? fallbackQuery;

  bool get isMapped => genreParams != null && genreParams!.isNotEmpty;
}

const moodMixConfigs = <MoodMixConfig>[
  MoodMixConfig(
    id: 'focus',
    title: 'Enfocado',
    keywords: ['focus', 'enfoque', 'concentracion', 'study', 'estudiar'],
    fallbackQuery: 'focus music',
  ),
  MoodMixConfig(
    id: 'gym',
    title: 'Gym',
    keywords: ['gym', 'workout', 'entrenamiento', 'fitness', 'energia'],
    fallbackQuery: 'workout music',
  ),
  MoodMixConfig(
    id: 'chill',
    title: 'Chill',
    keywords: ['chill', 'relax', 'relajacion', 'calma', 'acustico'],
    fallbackQuery: 'chill music',
  ),
  MoodMixConfig(
    id: 'sleep',
    title: 'Dormir',
    keywords: ['sleep', 'dormir', 'descanso', 'sueno'],
    fallbackQuery: 'sleep music',
  ),
  MoodMixConfig(
    id: 'party',
    title: 'Fiesta',
    keywords: ['party', 'fiesta', 'dance', 'baile'],
    fallbackQuery: 'party music',
  ),
];

class TopArtist {
  const TopArtist({
    required this.name,
    this.id,
    this.imageUrl,
    this.plays = 0,
    this.seconds = 0,
  });

  final String name;
  final String? id;
  final String? imageUrl;
  final int plays;
  final int seconds;

  String get subtitle {
    if (seconds <= 0 && plays <= 0) return 'Artista';
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    if (hours > 0) return '$hours h $minutes min';
    if (minutes > 0) return '$minutes min';
    return plays == 1 ? '1 reproducción' : '$plays reproducciones';
  }
}

class FollowedArtist {
  const FollowedArtist({
    required this.id,
    required this.name,
    this.thumbnailUrl,
    required this.followedAt,
  });

  final String id;
  final String name;
  final String? thumbnailUrl;
  final DateTime followedAt;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'thumbnailUrl': thumbnailUrl,
    'followedAt': followedAt.toIso8601String(),
  };

  factory FollowedArtist.fromJson(Map<String, dynamic> json) => FollowedArtist(
    id: '${json['id']}',
    name: '${json['name'] ?? 'Artista'}',
    thumbnailUrl: json['thumbnailUrl'] as String?,
    followedAt:
        DateTime.tryParse('${json['followedAt']}') ?? DateTime.now(),
  );
}

class BecauseYouListened {
  const BecauseYouListened({
    required this.seedArtistId,
    required this.seedArtistName,
    required this.songs,
    this.isOffline = false,
  });

  final String seedArtistId;
  final String seedArtistName;
  final List<SongModel> songs;
  final bool isOffline;
}

/// Secciones que pueden abrirse con la pantalla genérica “Ver todo”.
enum SeeAllSection {
  dailyMixes,
  continueListening,
  forYou,
  newReleases,
  trending,
  charts,
  genres,
  becauseYouListened,
  rediscover,
  topArtists,
  followedReleases,
  recentAlbums,
  playlists,
  favorites,
  moodMixes,
}

extension SeeAllSectionX on SeeAllSection {
  String get title => switch (this) {
    SeeAllSection.dailyMixes => 'Daily Mix',
    SeeAllSection.continueListening => 'Seguir escuchando',
    SeeAllSection.forYou => 'Hecho para ti',
    SeeAllSection.newReleases => 'Novedades',
    SeeAllSection.trending => 'Tendencias',
    SeeAllSection.charts => 'Charts',
    SeeAllSection.genres => 'Géneros',
    SeeAllSection.becauseYouListened => 'Porque escuchaste',
    SeeAllSection.rediscover => 'Redescubre',
    SeeAllSection.topArtists => 'Top artistas',
    SeeAllSection.followedReleases => 'Nuevo de artistas que sigues',
    SeeAllSection.recentAlbums => 'Álbumes recientes',
    SeeAllSection.playlists => 'Tus playlists',
    SeeAllSection.favorites => 'Tus favoritos',
    SeeAllSection.moodMixes => 'Mezclas para tu momento',
  };

  static SeeAllSection? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    for (final section in SeeAllSection.values) {
      if (section.name == value) return section;
    }
    return null;
  }
}

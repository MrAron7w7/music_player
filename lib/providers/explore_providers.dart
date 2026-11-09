import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/utils/text_utils.dart';
import '../data/models/explore_models.dart';
import '../data/models/home_models.dart';
import '../data/models/public_playlist_model.dart';
import '../data/models/song_model.dart';
import '../data/services/explore_service.dart';
import 'music_providers.dart';

final exploreServiceProvider = Provider<ExploreService>(
  (ref) => ExploreService(ref.watch(ytServiceProvider)),
);

/// Compartido por Inicio y Buscador. No es autoDispose para conservar la
/// caché en memoria y evitar llamadas duplicadas entre pestañas.
final exploreBundleProvider = FutureProvider<ExploreBundle>(
  (ref) => ref.watch(exploreServiceProvider).getExploreBundle(),
);

final trendingProvider = Provider<List<SongModel>>((ref) {
  final bundle = ref.watch(exploreBundleProvider).valueOrNull;
  if (bundle == null) return const [];
  if (bundle.trending.isNotEmpty) return bundle.trending;
  return bundle.topSongs;
});

final exploreGenresProvider = Provider<List<GenreCategory>>(
  (ref) => ref.watch(exploreBundleProvider).valueOrNull?.genres ?? const [],
);

/// Lista completa de Moods & Genres. Se cachea 7 días en el servicio.
final allGenresProvider = FutureProvider<List<GenreCategory>>(
  (ref) => ref.watch(exploreServiceProvider).getMoodCategories(),
);

final genresProvider = Provider<List<GenreCategory>>((ref) {
  final fromExplore = ref.watch(exploreGenresProvider);
  if (fromExplore.isNotEmpty) return fromExplore;
  final fromCategories = ref.watch(allGenresProvider).valueOrNull;
  return fromCategories ?? const [];
});

typedef GenrePlaylistRequest = ({String params, String title});

final genrePlaylistsProvider = FutureProvider.autoDispose
    .family<List<PublicPlaylistModel>, GenrePlaylistRequest>(
      (ref, request) => ref
          .watch(exploreServiceProvider)
          .getGenrePlaylists(request.params, title: request.title),
    );

final chartCountryProvider = StateProvider<String>((ref) => 'ZZ');

final chartsProvider = FutureProvider<ChartsSnapshot>(
  (ref) => ref
      .watch(exploreServiceProvider)
      .getCharts(ref.watch(chartCountryProvider)),
);

final moodMixesProvider = Provider<List<MoodMix>>((ref) {
  final genres = ref.watch(genresProvider);
  final normalized = [
    for (final genre in genres)
      (genre: genre, normalized: normalize(genre.title)),
  ];
  return [
    for (final config in moodMixConfigs)
      () {
        final matches = normalized.where((entry) {
          return config.keywords.any(
            (keyword) => entry.normalized.contains(normalize(keyword)),
          );
        }).toList();
        if (matches.isEmpty) {
          return MoodMix(
            id: config.id,
            title: config.title,
            subtitle: 'Mezcla aproximada',
            fallbackQuery: config.fallbackQuery,
          );
        }
        final genre = matches.first.genre;
        return MoodMix(
          id: config.id,
          title: config.title,
          subtitle: genre.title,
          genreParams: genre.params,
        );
      }(),
  ];
});

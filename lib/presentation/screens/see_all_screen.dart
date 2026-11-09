import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/genre_artwork.dart';
import '../../data/models/album_model.dart';
import '../../data/models/explore_models.dart';
import '../../data/models/home_models.dart';
import '../../data/models/playlist_model.dart';
import '../../data/models/song_model.dart';
import '../../providers/explore_providers.dart';
import '../../providers/home_feed_providers.dart';
import '../../providers/home_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/search_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/home_cards.dart';
import '../widgets/song_tile.dart';

class SeeAllScreen extends ConsumerWidget {
  const SeeAllScreen({super.key, required this.section});

  final SeeAllSection section;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: AppBar(title: Text(section.title)),
    body: _body(context, ref),
  );

  Widget _body(BuildContext context, WidgetRef ref) {
    switch (section) {
      case SeeAllSection.dailyMixes:
        final async = ref.watch(dailyMixesProvider);
        return async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.auto_awesome_rounded,
            title: 'No se pudieron generar tus mixes',
            message: '$error',
            onRetry: () => ref.invalidate(dailyMixesProvider),
          ),
          data: (mixes) => mixes.isEmpty
              ? const EmptyState(
                  icon: Icons.auto_awesome_rounded,
                  title: 'Aún no hay suficientes datos',
                  message:
                      'Escucha algunas canciones para generar tus mezclas.',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: mixes.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) => _MixRow(mix: mixes[index]),
                ),
        );
      case SeeAllSection.continueListening:
        return _SongList(
          songs: ref.watch(continueListeningProvider),
          emptyTitle: 'Tu historial está vacío',
        );
      case SeeAllSection.forYou:
        return _AsyncSongList(
          async: ref.watch(homeRecommendationsProvider),
          onRetry: () => ref.invalidate(homeRecommendationsProvider),
          emptyTitle: 'Aún no hay recomendaciones',
        );
      case SeeAllSection.becauseYouListened:
        final async = ref.watch(becauseYouListenedProvider);
        return async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.person_search_rounded,
            title: 'No se pudo cargar la sección',
            message: '$error',
            onRetry: () => ref.invalidate(becauseYouListenedProvider),
          ),
          data: (result) => result == null
              ? const EmptyState(
                  icon: Icons.person_search_rounded,
                  title: 'Escucha un artista para empezar',
                )
              : _SongList(
                  songs: result.songs,
                  header: result.isOffline ? 'Modo offline' : null,
                  emptyTitle: 'Sin canciones',
                ),
        );
      case SeeAllSection.trending:
        final async = ref.watch(exploreBundleProvider);
        return async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.trending_up_rounded,
            title: 'No se pudieron cargar las tendencias',
            message: '$error',
            onRetry: () => ref.invalidate(exploreBundleProvider),
          ),
          data: (_) => _SongList(
            songs: ref.watch(trendingProvider),
            emptyTitle: 'Sin tendencias por ahora',
          ),
        );
      case SeeAllSection.charts:
        final async = ref.watch(chartsProvider);
        return async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.bar_chart_rounded,
            title: 'No se pudieron cargar los charts',
            message: '$error',
            onRetry: () => ref.invalidate(chartsProvider),
          ),
          data: (charts) => _ChartLists(charts: charts),
        );
      case SeeAllSection.genres:
        final async = ref.watch(allGenresProvider);
        return async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.category_rounded,
            title: 'No se pudieron cargar los géneros',
            message: '$error',
            onRetry: () => ref.invalidate(allGenresProvider),
          ),
          data: (genres) => _GenreList(genres: genres),
        );
      case SeeAllSection.rediscover:
        return _SongList(
          songs: ref.watch(rediscoverProvider),
          emptyTitle: 'Nada que redescubrir todavía',
        );
      case SeeAllSection.topArtists:
        return _TopArtistList(artists: ref.watch(topArtistsProvider));
      case SeeAllSection.followedReleases:
        final async = ref.watch(followedReleasesProvider);
        return async.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => EmptyState(
            icon: Icons.person_add_alt_1_rounded,
            title: 'No se pudieron cargar los lanzamientos',
            message: '$error',
            onRetry: () => ref.invalidate(followedReleasesProvider),
          ),
          data: (albums) => _AlbumGrid(
            albums: albums,
            emptyTitle: 'Sigue artistas para ver sus novedades',
          ),
        );
      case SeeAllSection.recentAlbums:
        final albums = ref.watch(recentAlbumsProvider);
        return albums.isEmpty
            ? const EmptyState(
                icon: Icons.album_rounded,
                title: 'Aún no hay álbumes recientes',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: albums.length,
                itemBuilder: (context, index) {
                  final album = albums[index];
                  return ListTile(
                    leading: AlbumArt(
                      url: album.coverUrl,
                      size: 52,
                      radius: 10,
                    ),
                    title: Text(album.title, maxLines: 1),
                    subtitle: Text(album.artist, maxLines: 1),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => context.push('/album/${album.id}'),
                  );
                },
              );
      case SeeAllSection.playlists:
        final playlists = ref.watch(playlistsProvider);
        return playlists.isEmpty
            ? const EmptyState(
                icon: Icons.queue_music_rounded,
                title: 'Todavía no tienes playlists',
              )
            : ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: playlists.length,
                itemBuilder: (context, index) {
                  final playlist = playlists[index];
                  return _PlaylistRow(playlist: playlist);
                },
              );
      case SeeAllSection.favorites:
        return _SongList(
          songs: ref.watch(favoritesProvider),
          emptyTitle: 'Todavía no tienes favoritos',
        );
      case SeeAllSection.moodMixes:
        final moods = ref.watch(moodMixesProvider);
        if (moods.isEmpty) {
          return const EmptyState(
            icon: Icons.auto_awesome_rounded,
            title: 'Sin mezclas por ahora',
          );
        }
        return LayoutBuilder(
          builder: (context, constraints) {
            final columns = (constraints.maxWidth / 170).floor().clamp(2, 4);
            final cardWidth =
                (constraints.maxWidth - 32 - (columns - 1) * 10) / columns;
            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final mood in moods)
                      HomeMoodCard(
                        title: mood.title,
                        subtitle: mood.subtitle,
                        width: cardWidth,
                        colors: genreArtworkFor(mood.title).colors,
                        icon: genreArtworkFor(mood.title).icon,
                        imageUrl: genreArtworkFor(mood.title).imageUrl,
                        onTap: () => _openMood(context, ref, mood),
                      ),
                  ],
                ),
              ],
            );
          },
        );
    }
  }

  void _openMood(BuildContext context, WidgetRef ref, MoodMix mood) {
    if (mood.isMapped) {
      context.push(
        '/genre/${Uri.encodeComponent(mood.genreParams!)}',
        extra: mood.title,
      );
      return;
    }
    ref.read(searchQueryProvider.notifier).state = mood.fallbackQuery ?? '';
    ref.read(selectedTabProvider.notifier).state = 1;
    context.go('/');
  }
}

class _SongList extends StatelessWidget {
  const _SongList({required this.songs, required this.emptyTitle, this.header});

  final List<SongModel> songs;
  final String emptyTitle;
  final String? header;

  @override
  Widget build(BuildContext context) {
    if (songs.isEmpty) {
      return EmptyState(icon: Icons.music_off_rounded, title: emptyTitle);
    }
    return ListView.builder(
      padding: const EdgeInsets.only(top: 8, bottom: 100),
      itemCount: songs.length + (header == null ? 0 : 1),
      itemBuilder: (context, index) {
        if (header != null && index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Text(
              header!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          );
        }
        final songIndex = index - (header == null ? 0 : 1);
        return SongTile(
          songs[songIndex],
          playQueue: songs,
          startIndex: songIndex,
        );
      },
    );
  }
}

class _AsyncSongList extends StatelessWidget {
  const _AsyncSongList({
    required this.async,
    required this.onRetry,
    required this.emptyTitle,
  });

  final AsyncValue<List<SongModel>> async;
  final VoidCallback onRetry;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) => async.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) => EmptyState(
      icon: Icons.cloud_off_rounded,
      title: 'No se pudo cargar la sección',
      message: '$error',
      onRetry: onRetry,
    ),
    data: (songs) => _SongList(songs: songs, emptyTitle: emptyTitle),
  );
}

class _AlbumGrid extends StatelessWidget {
  const _AlbumGrid({required this.albums, required this.emptyTitle});

  final List<AlbumModel> albums;
  final String emptyTitle;

  @override
  Widget build(BuildContext context) {
    if (albums.isEmpty) {
      return EmptyState(icon: Icons.album_rounded, title: emptyTitle);
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 170).floor().clamp(2, 5);
        final cellWidth =
            (constraints.maxWidth - 32 - (columns - 1) * 14) / columns;
        return GridView.builder(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 14,
            crossAxisSpacing: 14,
            childAspectRatio: .72,
          ),
          itemCount: albums.length,
          itemBuilder: (context, index) {
            final album = albums[index];
            return HomeAlbumCard(
              title: album.title,
              subtitle: album.artists.join(', '),
              imageUrl: album.thumbnailUrl,
              width: cellWidth,
              onTap: () => context.push('/album/${album.id}'),
            );
          },
        );
      },
    );
  }
}

class _MixRow extends ConsumerWidget {
  const _MixRow({required this.mix});

  final DailyMix mix;

  @override
  Widget build(BuildContext context, WidgetRef ref) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    leading: MixArtwork(urls: mix.coverUrls, size: 68, radius: 12),
    title: Text(mix.title, maxLines: 1, overflow: TextOverflow.ellipsis),
    subtitle: Text(mix.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: IconButton(
      tooltip: 'Reproducir',
      icon: const Icon(Icons.play_circle_fill_rounded),
      onPressed: () =>
          ref.read(audioHandlerProvider).playSongs(mix.songs, shuffle: false),
    ),
    onTap: () => context.push('/mix/${mix.id}'),
  );
}

class _TopArtistList extends StatelessWidget {
  const _TopArtistList({required this.artists});

  final List<TopArtist> artists;

  @override
  Widget build(BuildContext context) {
    if (artists.isEmpty) {
      return const EmptyState(
        icon: Icons.people_alt_rounded,
        title: 'Aún no hay estadísticas de artistas',
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: artists.length,
      itemBuilder: (context, index) {
        final artist = artists[index];
        return ListTile(
          leading: AlbumArt(url: artist.imageUrl, size: 52, radius: 26),
          title: Text(artist.name, maxLines: 1),
          subtitle: Text(artist.subtitle),
          trailing: index < 3
              ? Text(
                  '#${index + 1}',
                  style: Theme.of(context).textTheme.titleMedium,
                )
              : null,
          onTap: artist.id == null || artist.id!.isEmpty
              ? null
              : () => context.push('/artist/${artist.id}'),
        );
      },
    );
  }
}

class _GenreList extends StatelessWidget {
  const _GenreList({required this.genres});

  final List<GenreCategory> genres;

  @override
  Widget build(BuildContext context) {
    if (genres.isEmpty) {
      return const EmptyState(
        icon: Icons.category_rounded,
        title: 'Sin géneros disponibles',
      );
    }
    final groups = <String, List<GenreCategory>>{};
    for (final genre in genres) {
      groups.putIfAbsent(genre.group ?? 'Géneros', () => []).add(genre);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        for (final entry in groups.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 8),
            child: Text(
              entry.key,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final columns = (constraints.maxWidth / 170).floor().clamp(
                  2,
                  4,
                );
                final cardWidth =
                    (constraints.maxWidth - (columns - 1) * 10) / columns;
                return Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final genre in entry.value)
                      HomeMoodCard(
                        title: genre.title,
                        subtitle: genre.group,
                        width: cardWidth,
                        colors: genreArtworkFor(genre.title).colors,
                        icon: genreArtworkFor(genre.title).icon,
                        imageUrl: genreArtworkFor(genre.title).imageUrl,
                        onTap: () => context.push(
                          '/genre/${Uri.encodeComponent(genre.params)}',
                          extra: genre.title,
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _ChartLists extends StatelessWidget {
  const _ChartLists({required this.charts});

  final ChartsSnapshot charts;

  @override
  Widget build(BuildContext context) {
    if (charts.isEmpty) {
      return const EmptyState(
        icon: Icons.bar_chart_rounded,
        title: 'Sin charts disponibles',
      );
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        if (charts.selectedCountry != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Text(
              charts.selectedCountry!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        for (final playlist in charts.playlists)
          ListTile(
            leading: AlbumArt(url: playlist.thumbnailUrl, size: 52),
            title: Text(playlist.title, maxLines: 1),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => context.push('/public-playlist/${playlist.id}'),
          ),
        if (charts.artists.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 4),
            child: Text(
              'Artistas en tendencia',
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        for (final artist in charts.artists)
          ListTile(
            leading: AlbumArt(url: artist.thumbnailUrl, size: 48, radius: 24),
            title: Text(artist.name),
            subtitle: artist.subscribers == null
                ? null
                : Text(artist.subscribers!),
            onTap: () => context.push('/artist/${artist.id}'),
          ),
      ],
    );
  }
}

class _PlaylistRow extends StatelessWidget {
  const _PlaylistRow({required this.playlist});

  final PlaylistModel playlist;

  @override
  Widget build(BuildContext context) => ListTile(
    leading: AlbumArt(url: playlist.coverUrl, size: 52, radius: 10),
    title: Text(playlist.name, maxLines: 1),
    subtitle: Text('${playlist.songs.length} canciones'),
    trailing: const Icon(Icons.chevron_right_rounded),
    onTap: () => context.push('/playlist/${playlist.id}'),
  );
}

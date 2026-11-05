import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/notification_permissions.dart';
import '../../data/models/album_model.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/explore_providers.dart';
import '../../providers/followed_artists_providers.dart';
import '../../providers/home_feed_providers.dart';
import '../../providers/home_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/network_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/search_providers.dart';
import '../../providers/settings_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/home_cards.dart';
import '../widgets/profile_avatar.dart';
import '../widgets/section_header.dart';
import '../widgets/song_tile.dart';

/// Entrada suave de una sección de Home. La animación corre una sola vez al
/// montar la sección; los cambios de datos posteriores no la reinician.
Widget _reveal(Widget child, {int delay = 0}) => child
    .animate(delay: Duration(milliseconds: delay))
    .fadeIn(
      duration: const Duration(milliseconds: 360),
      curve: Curves.easeOutCubic,
    )
    .slideY(
      begin: .05,
      end: 0,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );

Future<void> _playSongs(
  BuildContext context,
  WidgetRef ref,
  List<SongModel> songs,
  int index,
) async {
  ref
      .read(audioHandlerProvider)
      .playSongs(songs, startIndex: index, shuffle: false);
  if (context.mounted) context.push('/now-playing');
  unawaited(requestPlaybackNotificationPermission(context: context));
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(effectiveOfflineProvider);
    return Scaffold(
      body: RefreshIndicator.adaptive(
        onRefresh: () async {
          // Cada sección es independiente: invalidar una no rompe las demás.
          ref.invalidate(homeRecommendationsProvider);
          ref.invalidate(dailyMixesProvider);
          ref.invalidate(exploreBundleProvider);
          ref.invalidate(chartsProvider);
          ref.invalidate(becauseYouListenedProvider);
          ref.invalidate(followedReleasesProvider);
          ref.invalidate(allGenresProvider);
          final artist = ref.read(currentArtistInfoProvider);
          if (artist != null) {
            ref.invalidate(artistSpotlightProvider(artist.id));
          }
          await Future<void>.delayed(const Duration(milliseconds: 350));
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverList.list(
              children: [
                _reveal(const _GreetingHeader()),
                if (offline) const _OfflineBanner(),
                _reveal(const _RecentChips(), delay: 20),
                _reveal(const _ContinueListeningSection(), delay: 40),
                _reveal(const _DailyMixesSection(), delay: 60),
                if (!offline) _reveal(const _NewReleasesSection(), delay: 80),
                if (!offline) _reveal(const _TrendingSection(), delay: 100),
                if (!offline) _reveal(const _GenresSection(), delay: 120),
                _reveal(const _BecauseYouListenedSection(), delay: 140),
                if (!offline) _reveal(const _ForYouSection(), delay: 160),
                _reveal(const _RediscoverSection(), delay: 180),
                _reveal(const _TopArtistsSection(), delay: 200),
                if (!offline)
                  _reveal(const _FollowedReleasesSection(), delay: 220),
                if (!offline) _reveal(const _SpotlightSection(), delay: 240),
                if (!offline) _reveal(const _RecentAlbumsSection(), delay: 260),
                _reveal(const _PlaylistsSection(), delay: 280),
                _reveal(const _FavoritesSection(), delay: 300),
                if (!offline) _reveal(const _MoodMixesSection(), delay: 320),
                const _EmptyHomeSection(),
                const SizedBox(height: AppConstants.floatingNavInset),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Saludo de bienvenida. Sin watches: nunca se reconstruye por cambios de datos.
class _GreetingHeader extends ConsumerWidget {
  const _GreetingHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hour = DateTime.now().hour;
    final greeting = hour < 12
        ? 'Buenos días'
        : hour < 19
        ? 'Buenas tardes'
        : 'Buenas noches';
    final subtitle = hour < 12
        ? 'Empieza el día con tu música.'
        : hour < 19
        ? 'Tu banda sonora para esta tarde.'
        : 'Relájate con lo que más te gusta.';
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 14, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  greeting,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.9,
                    height: 1.1,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          ProfileAvatar(
            size: 46,
            onTap: () => ref.read(selectedTabProvider.notifier).state = 3,
          ),
        ],
      ),
    );
  }
}

/// Banner de modo offline.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final manual = ref.watch(manualOfflineProvider);
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 10, 22, 2),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer.withValues(alpha: .55),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_rounded,
              color: theme.colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    manual ? 'Modo offline activo' : 'Sin conexión',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    'Se muestra y reproduce música disponible en tu biblioteca.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onTertiaryContainer.withValues(
                        alpha: .8,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (manual)
              IconButton(
                tooltip: 'Desactivar modo offline',
                onPressed: () =>
                    ref.read(offlineModeProvider.notifier).state = false,
                icon: Icon(
                  Icons.close_rounded,
                  color: theme.colorScheme.onTertiaryContainer,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Accesos rápidos a lo último reproducido.
class _RecentChips extends ConsumerWidget {
  const _RecentChips();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(effectiveOfflineProvider);
    final downloadedIds = ref.watch(downloadedSongIdsProvider);
    final recent = ref.watch(recentChipsProvider);
    final visible = offline
        ? recent.where((song) => downloadedIds.contains(song.id)).toList()
        : recent;
    if (visible.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 22),
        itemCount: visible.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final song = visible[index];
          return ActionChip(
            avatar: const Icon(Icons.play_arrow_rounded, size: 18),
            label: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            onPressed: () => _playSongs(context, ref, visible, index),
          );
        },
      ),
    );
  }
}

/// Seguir escuchando: historial (filtrado por descargas si está offline).
class _ContinueListeningSection extends ConsumerWidget {
  const _ContinueListeningSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(effectiveOfflineProvider);
    final downloadedIds = ref.watch(downloadedSongIdsProvider);
    final history = ref.watch(continueListeningProvider);
    final recent = offline
        ? history.where((song) => downloadedIds.contains(song.id)).toList()
        : history;
    if (recent.isEmpty) return const SizedBox.shrink();
    final currentId = ref.watch(
      currentSongProvider.select((state) => state.valueOrNull?.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Seguir escuchando',
          subtitle: 'Lo último que sonó en tu biblioteca',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/continueListening'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        _SongRow(
          songs: recent.take(10).toList(),
          hero: true,
          heroExceptId: currentId,
          onPlay: (songs, index) => _playSongs(context, ref, songs, index),
        ),
      ],
    );
  }
}

/// Mezclas diarias generadas localmente y cacheadas una vez al día.
class _DailyMixesSection extends ConsumerWidget {
  const _DailyMixesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(dailyMixesProvider);
    return async.when(
      loading: () => const _CardsSkeleton(
        title: 'Daily Mix',
        subtitle: 'Preparando mezclas para hoy…',
      ),
      error: (error, _) => Column(
        children: [
          SectionHeader(
            'Daily Mix',
            subtitle: 'Mezclas pensadas para hoy',
            padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
          ),
          HomeListError(
            message: 'No se pudieron generar tus mezclas.',
            onRetry: () => ref.invalidate(dailyMixesProvider),
          ),
        ],
      ),
      data: (mixes) {
        if (mixes.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionHeader(
              'Daily Mix',
              subtitle: 'Tus favoritos, novedades y descubrimientos',
              action: 'Ver todo',
              onTap: () => context.push('/see-all/dailyMixes'),
              padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
            ),
            SizedBox(
              height: 226,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.symmetric(horizontal: 22),
                itemCount: mixes.length,
                separatorBuilder: (_, _) => const SizedBox(width: 16),
                itemBuilder: (context, index) {
                  final mix = mixes[index];
                  return HomeMixCard(
                    title: mix.title,
                    subtitle: mix.subtitle,
                    urls: mix.coverUrls,
                    onTap: () => context.push('/mix/${mix.id}'),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}

class _NewReleasesSection extends ConsumerWidget {
  const _NewReleasesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(exploreBundleProvider);
    final albums = async.valueOrNull?.newReleases ?? const <AlbumModel>[];
    if (async.isLoading && albums.isEmpty) {
      return const _CardsSkeleton(
        title: 'Novedades',
        subtitle: 'Cargando lanzamientos…',
      );
    }
    if (albums.isEmpty) {
      if (async.hasError) {
        return Column(
          children: [
            const SectionHeader(
              'Novedades',
              subtitle: 'Lanzamientos recientes',
              padding: EdgeInsets.fromLTRB(22, 28, 22, 12),
            ),
            HomeListError(
              message: 'No se pudieron cargar las novedades.',
              onRetry: () => ref.invalidate(exploreBundleProvider),
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Novedades',
          subtitle: 'Lanzamientos recientes para ti',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/newReleases'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: albums.take(12).length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final album = albums[index];
              return HomeAlbumCard(
                title: album.title,
                subtitle: album.artists.join(', '),
                imageUrl: album.thumbnailUrl,
                onTap: () => context.push('/album/${album.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _TrendingSection extends ConsumerWidget {
  const _TrendingSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(exploreBundleProvider);
    final songs = ref.watch(trendingProvider);
    if (async.isLoading && songs.isEmpty) {
      return const _CardsSkeleton(
        title: 'Tendencias',
        subtitle: 'Cargando lo más escuchado…',
      );
    }
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Tendencias',
          subtitle: 'Lo que suena ahora mismo',
          action: 'Ver todo',
          trailing: IconButton(
            tooltip: 'Charts',
            onPressed: () => context.push('/charts'),
            icon: const Icon(Icons.bar_chart_rounded),
          ),
          onTap: () => context.push('/see-all/trending'),
          padding: const EdgeInsets.fromLTRB(22, 28, 10, 12),
        ),
        _SongRow(
          songs: songs.take(12).toList(),
          onPlay: (songs, index) => _playSongs(context, ref, songs, index),
        ),
      ],
    );
  }
}

class _GenresSection extends ConsumerWidget {
  const _GenresSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final genres = ref.watch(genresProvider);
    if (genres.isEmpty) return const SizedBox.shrink();
    const colors = [
      [Color(0xFF5B4B8A), Color(0xFF9B7EDE)],
      [Color(0xFF1F6F78), Color(0xFF4FB3BF)],
      [Color(0xFF8A3B4B), Color(0xFFE07A8A)],
      [Color(0xFF6B4F1D), Color(0xFFD9A441)],
      [Color(0xFF1E4D6B), Color(0xFF5A9BC4)],
      [Color(0xFF4A3B6B), Color(0xFF9B87C4)],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Géneros',
          subtitle: 'Explora por estado de ánimo y estilo',
          action: 'Ver todos',
          onTap: () => context.push('/see-all/genres'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: genres.take(12).length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final genre = genres[index];
              return HomeMoodCard(
                title: genre.title,
                subtitle: genre.group,
                icon: Icons.category_rounded,
                colors: colors[index % colors.length],
                onTap: () => context.push(
                  '/genre/${Uri.encodeComponent(genre.params)}',
                  extra: genre.title,
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _BecauseYouListenedSection extends ConsumerWidget {
  const _BecauseYouListenedSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(becauseYouListenedProvider);
    final result = async.valueOrNull;
    if (async.isLoading && result == null) {
      return const _CardsSkeleton(
        title: 'Porque escuchaste…',
        subtitle: 'Buscando música parecida…',
      );
    }
    if (result == null || result.songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Porque escuchaste a ${result.seedArtistName}',
          subtitle: result.isOffline
              ? 'Desde tu biblioteca, sin conexión'
              : 'Canciones parecidas a tu historial',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/becauseYouListened'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        _SongRow(
          songs: result.songs,
          onPlay: (songs, index) => _playSongs(context, ref, songs, index),
        ),
      ],
    );
  }
}

/// Hecho para ti: recomendaciones remotas con tarjeta de error y reintentar.
class _ForYouSection extends ConsumerWidget {
  const _ForYouSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final recommendations = ref.watch(homeRecommendationsProvider);
    final forYou = recommendations.valueOrNull ?? const <SongModel>[];
    final forYouError = recommendations.hasError ? recommendations.error : null;

    if (forYou.isEmpty) {
      if (recommendations.isLoading) {
        return const _CardsSkeleton(
          title: 'Hecho para ti',
          subtitle: 'Preparando recomendaciones según tus gustos…',
        );
      }
      if (forYouError != null) {
        return Column(
          children: [
            const SectionHeader(
              'Hecho para ti',
              subtitle: 'Basado en tu historial y tus gustos',
              padding: EdgeInsets.fromLTRB(22, 28, 22, 12),
            ),
            HomeListError(
              message: 'No se pudieron cargar las recomendaciones.',
              onRetry: () => ref.invalidate(homeRecommendationsProvider),
            ),
          ],
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Hecho para ti',
          subtitle: 'Basado en tu historial y tus gustos',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/forYou'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        _SongRow(
          songs: forYou,
          onPlay: (songs, index) => _playSongs(context, ref, songs, index),
        ),
      ],
    );
  }
}

class _RediscoverSection extends ConsumerWidget {
  const _RediscoverSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final songs = ref.watch(rediscoverProvider);
    if (songs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Redescubre',
          subtitle: 'Canciones que hace tiempo que no escuchas',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/rediscover'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        _SongRow(
          songs: songs,
          onPlay: (songs, index) => _playSongs(context, ref, songs, index),
        ),
      ],
    );
  }
}

class _TopArtistsSection extends ConsumerWidget {
  const _TopArtistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artists = ref.watch(topArtistsProvider);
    if (artists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Top artistas',
          subtitle: 'Los que más has escuchado',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/topArtists'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        SizedBox(
          height: 188,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: artists.take(10).length,
            separatorBuilder: (_, _) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              final artist = artists[index];
              return HomeAlbumCard(
                title: artist.name,
                subtitle: artist.subtitle,
                imageUrl: artist.imageUrl,
                circular: true,
                width: 132,
                onTap: artist.id == null || artist.id!.isEmpty
                    ? () {}
                    : () => context.push('/artist/${artist.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _FollowedReleasesSection extends ConsumerWidget {
  const _FollowedReleasesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final followed = ref.watch(followedArtistsProvider);
    if (followed.isEmpty) return const SizedBox.shrink();
    final async = ref.watch(followedReleasesProvider);
    final albums = async.valueOrNull ?? const <AlbumModel>[];
    if (async.isLoading && albums.isEmpty) {
      return const _CardsSkeleton(
        title: 'Nuevo de artistas que sigues',
        subtitle: 'Buscando sus últimos lanzamientos…',
      );
    }
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Nuevo de artistas que sigues',
          subtitle: 'Lo último de ${followed.length} artistas',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/followedReleases'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: albums.take(12).length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final album = albums[index];
              return HomeAlbumCard(
                title: album.title,
                subtitle: album.artists.join(', '),
                imageUrl: album.thumbnailUrl,
                onTap: () => context.push('/album/${album.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Spotlight del artista de la canción actual.
class _SpotlightSection extends ConsumerWidget {
  const _SpotlightSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistInfo = ref.watch(currentArtistInfoProvider);
    if (artistInfo == null) return const SizedBox.shrink();
    final spotlightValue = ref.watch(artistSpotlightProvider(artistInfo.id));
    final spotlight = spotlightValue.valueOrNull;
    if (spotlight == null) return const SizedBox.shrink();
    final forYou =
        ref.watch(homeRecommendationsProvider).valueOrNull ??
        const <SongModel>[];
    final forYouIds = forYou.map((song) => song.id).toSet();
    final spotlightSongs = spotlight.songs
        .where((song) => !forYouIds.contains(song.id))
        .toList();
    if (spotlightSongs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Más de ${spotlight.artistName}',
          subtitle: 'Canciones y artistas parecidos a lo que escuchas',
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
        ),
        _SongRow(
          songs: spotlightSongs,
          onPlay: (songs, index) => _playSongs(context, ref, songs, index),
        ),
      ],
    );
  }
}

/// Álbumes recientes del historial.
class _RecentAlbumsSection extends ConsumerWidget {
  const _RecentAlbumsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final albums = ref.watch(homeRecentAlbumsProvider);
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Álbumes recientes',
          subtitle: 'Vuelve a escuchar los discos que te gustan',
          action: 'Ver todo',
          onTap: () => context.push('/see-all/recentAlbums'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: albums.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final album = albums[index];
              return _MediaCard(
                title: album.title,
                subtitle: album.artist,
                imageUrl: album.coverUrl,
                onTap: () => context.push('/album/${album.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _PlaylistsSection extends ConsumerWidget {
  const _PlaylistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    if (playlists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Tus playlists',
          subtitle: 'Colecciones hechas a tu manera',
          action: 'Ver todas',
          onTap: () => context.push('/see-all/playlists'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        SizedBox(
          height: 208,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: playlists.length,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) {
              final playlist = playlists[index];
              return _MediaCard(
                title: playlist.name,
                subtitle: '${playlist.songs.length} canciones',
                imageUrl: playlist.coverUrl,
                onTap: () => context.push('/playlist/${playlist.id}'),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Tus favoritos (filtrado por descargas si está offline).
class _FavoritesSection extends ConsumerWidget {
  const _FavoritesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(effectiveOfflineProvider);
    final downloadedIds = ref.watch(downloadedSongIdsProvider);
    final favorites = ref.watch(favoritesProvider);
    final favoritesShown = offline
        ? favorites.where((song) => downloadedIds.contains(song.id)).toList()
        : favorites;
    if (favoritesShown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Tus favoritos',
          subtitle: 'Las canciones que siempre quieres oír',
          action: 'Ver todos',
          onTap: () => context.push('/see-all/favorites'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        ...favoritesShown
            .take(5)
            .toList()
            .asMap()
            .entries
            .map(
              (entry) => SongTile(
                entry.value,
                playQueue: favoritesShown,
                startIndex: entry.key,
              ),
            ),
      ],
    );
  }
}

class _MoodMixesSection extends ConsumerWidget {
  const _MoodMixesSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final moods = ref.watch(moodMixesProvider);
    if (moods.isEmpty) return const SizedBox.shrink();
    const colors = [
      [Color(0xFF3B5B8A), Color(0xFF7EA0DE)],
      [Color(0xFF8A3B4B), Color(0xFFE07A8A)],
      [Color(0xFF1F6F78), Color(0xFF4FB3BF)],
      [Color(0xFF4A3B6B), Color(0xFF9B87C4)],
      [Color(0xFF6B4F1D), Color(0xFFD9A441)],
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Mezclas para tu momento',
          subtitle: 'Enfocado, gym, chill, dormir y fiesta',
          action: 'Ver todas',
          onTap: () => context.push('/see-all/moodMixes'),
          padding: const EdgeInsets.fromLTRB(22, 28, 14, 12),
        ),
        SizedBox(
          height: 82,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: moods.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              final mood = moods[index];
              return HomeMoodCard(
                title: mood.title,
                subtitle: mood.subtitle,
                icon: Icons.auto_awesome_rounded,
                colors: colors[index % colors.length],
                onTap: () {
                  if (mood.isMapped) {
                    context.push(
                      '/genre/${Uri.encodeComponent(mood.genreParams!)}',
                      extra: mood.title,
                    );
                  } else {
                    ref.read(searchQueryProvider.notifier).state =
                        mood.fallbackQuery ?? '';
                    ref.read(selectedTabProvider.notifier).state = 1;
                    context.go('/');
                  }
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Pantalla vacía cuando no hay historial ni favoritos.
class _EmptyHomeSection extends ConsumerWidget {
  const _EmptyHomeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(effectiveOfflineProvider);
    final downloadedIds = ref.watch(downloadedSongIdsProvider);
    final history = ref.watch(historyProvider);
    final favorites = ref.watch(favoritesProvider);
    final recent = offline
        ? history.where((song) => downloadedIds.contains(song.id)).toList()
        : history;
    final favoritesShown = offline
        ? favorites.where((song) => downloadedIds.contains(song.id)).toList()
        : favorites;
    if (recent.isNotEmpty || favoritesShown.isNotEmpty) {
      return const SizedBox.shrink();
    }
    return const Padding(
      padding: EdgeInsets.fromLTRB(22, 30, 22, 0),
      child: _EmptyHomeCard(),
    );
  }
}

class _SongRow extends StatelessWidget {
  const _SongRow({
    required this.songs,
    required this.onPlay,
    this.hero = false,
    this.heroExceptId,
  });

  final List<SongModel> songs;
  final void Function(List<SongModel> songs, int index) onPlay;
  final bool hero;
  final String? heroExceptId;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 222,
    child: ListView.separated(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 22),
      itemCount: songs.length,
      separatorBuilder: (_, _) => const SizedBox(width: 16),
      itemBuilder: (context, index) {
        final song = songs[index];
        return _SongCard(
          song: song,
          hero: hero && song.id != heroExceptId,
          onTap: () => onPlay(songs, index),
        );
      },
    ),
  );
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.song, required this.onTap, this.hero = false});

  final SongModel song;
  final VoidCallback onTap;
  final bool hero;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const artSize = 158.0;
    final art = AlbumArt(
      url: song.artworkUrl,
      fallbackUrl: song.thumbnailUrl,
      size: artSize,
      radius: 18,
    );
    return SizedBox(
      width: artSize,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                if (hero) Hero(tag: 'art-${song.id}', child: art) else art,
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Center(
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.black.withValues(alpha: .55),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: .35),
                          ),
                        ),
                        child: const Icon(
                          Icons.play_arrow_rounded,
                          size: 22,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song.artists.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaCard extends StatelessWidget {
  const _MediaCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.imageUrl,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const artSize = 150.0;
    return SizedBox(
      width: artSize,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AlbumArt(url: imageUrl, size: artSize, radius: 18),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyHomeCard extends StatelessWidget {
  const _EmptyHomeCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: .16),
            theme.colorScheme.surfaceContainerHigh,
          ],
        ),
        border: Border.all(color: accent.withValues(alpha: .18)),
      ),
      child: Row(
        children: [
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: accent.withValues(alpha: .16),
            ),
            child: Icon(Icons.graphic_eq_rounded, size: 28, color: accent),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Tu viaje musical empieza aquí',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Busca una canción para empezar. Tus favoritos y tu historial aparecerán en esta pantalla.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardsSkeleton extends StatelessWidget {
  const _CardsSkeleton({
    this.title = 'Hecho para ti',
    this.subtitle = 'Preparando recomendaciones según tus gustos…',
  });

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title,
          subtitle: subtitle,
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
        ),
        SizedBox(
          height: 200,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 22),
            itemCount: 3,
            separatorBuilder: (_, _) => const SizedBox(width: 16),
            itemBuilder: (context, index) => Shimmer.fromColors(
              baseColor: colors.surfaceContainerHigh,
              highlightColor: colors.surfaceContainerHighest,
              child: SizedBox(
                width: 158,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 158,
                      height: 158,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Container(
                      width: 118,
                      height: 11,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: 82,
                      height: 9,
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

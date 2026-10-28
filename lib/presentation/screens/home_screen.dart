import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';

import '../../core/utils/notification_permissions.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/home_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/navigation_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/settings_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';

Future<void> _playSongs(
  BuildContext context,
  WidgetRef ref,
  List<SongModel> songs,
  int index,
) async {
  ref.read(audioHandlerProvider).playSongs(
    songs,
    startIndex: index,
    shuffle: false,
  );
  if (context.mounted) context.push('/now-playing');
  unawaited(requestPlaybackNotificationPermission(context: context));
}

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineModeProvider);
    final theme = Theme.of(context);
    return Scaffold(
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            floating: true,
            titleSpacing: 22,
            title: Text(
              'Simple Music',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
                letterSpacing: -.6,
              ),
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 20),
                child: CircleAvatar(
                  radius: 19,
                  backgroundColor: theme.colorScheme.primary.withValues(
                    alpha: .12,
                  ),
                  child: Icon(
                    DateTime.now().hour >= 19
                        ? Icons.nightlight_round
                        : Icons.headphones_rounded,
                    color: theme.colorScheme.primary,
                    size: 20,
                  ),
                ),
              ),
            ],
          ),
          SliverList.list(
            children: [
              const _GreetingHeader(),
              if (offline) const _OfflineBanner(),
              const _ContinueListeningSection(),
              const _ForYouSection(),
              const _SpotlightSection(),
              const _RecentAlbumsSection(),
              const _PlaylistsSection(),
              const _FavoritesSection(),
              const _EmptyHomeSection(),
              const SizedBox(height: 28),
            ],
          ),
        ],
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
      padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
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
    );
  }
}

/// Banner de modo offline. Solo observa `offlineModeProvider`.
class _OfflineBanner extends ConsumerWidget {
  const _OfflineBanner();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineModeProvider);
    if (!offline) return const SizedBox.shrink();
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
                    'Modo offline activo',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: theme.colorScheme.onTertiaryContainer,
                    ),
                  ),
                  Text(
                    'Solo se muestra y reproduce música descargada.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onTertiaryContainer
                          .withValues(alpha: .8),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Seguir escuchando: historial (filtrado por descargas si está offline).
/// Solo se reconstruye cuando cambian historial, descargas o modo offline.
class _ContinueListeningSection extends ConsumerWidget {
  const _ContinueListeningSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineModeProvider);
    final downloadedIds = (ref.watch(downloadsProvider).valueOrNull ?? const [])
        .map((entry) => entry.song.id)
        .toSet();
    final history = ref.watch(historyProvider);
    final recent = offline
        ? history.where((song) => downloadedIds.contains(song.id)).toList()
        : history;
    if (recent.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Seguir escuchando',
          subtitle: 'Lo último que sonó en tu biblioteca',
        ),
        _SongRow(
          songs: recent.take(10).toList(),
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
    final offline = ref.watch(offlineModeProvider);
    final active = ref.watch(selectedTabProvider) == 0;
    if (offline || !active) return const SizedBox.shrink();
    final recommendations = ref.watch(homeRecommendationsProvider);
    final forYou = recommendations.valueOrNull ?? const <SongModel>[];
    final forYouError = recommendations.hasError ? recommendations.error : null;

    if (forYou.isEmpty) {
      if (recommendations.isLoading) return const _CardsSkeleton();
      if (forYouError != null) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'No se pudieron cargar las recomendaciones',
            message: '$forYouError',
            onRetry: () => ref.invalidate(homeRecommendationsProvider),
            retryLabel: 'Reintentar',
          ),
        );
      }
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Hecho para ti',
          subtitle: 'Basado en tu historial y tus gustos',
        ),
        _SongRow(
          songs: forYou,
          onPlay: (songs, index) => _playSongs(context, ref, songs, index),
          showBadge: true,
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
    final offline = ref.watch(offlineModeProvider);
    final active = ref.watch(selectedTabProvider) == 0;
    if (offline || !active) return const SizedBox.shrink();
    final spotlightValue = ref.watch(artistSpotlightProvider);
    final spotlight = spotlightValue.valueOrNull;
    final spotlightError = spotlightValue.hasError ? spotlightValue.error : null;

    if (spotlightError != null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
        child: EmptyState(
          icon: Icons.error_outline_rounded,
          title: 'No se pudo cargar el spotlight del artista',
          message: '$spotlightError',
          onRetry: () => ref.invalidate(artistSpotlightProvider),
          retryLabel: 'Reintentar',
        ),
      );
    }
    if (spotlight == null) return const SizedBox.shrink();
    final forYou = ref.watch(homeRecommendationsProvider).valueOrNull ??
        const <SongModel>[];
    final forYouIds = forYou.map((song) => song.id).toSet();
    final spotlightSongs = spotlight.songs
        .where((song) => !forYouIds.contains(song.id))
        .toList();
    if (spotlightSongs.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionTitle(
          'Más de ${spotlight.artistName}',
          subtitle:
              'Canciones y artistas parecidos a lo que estás escuchando',
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
    final offline = ref.watch(offlineModeProvider);
    final active = ref.watch(selectedTabProvider) == 0;
    if (offline || !active) return const SizedBox.shrink();
    final albums = ref.watch(homeRecentAlbumsProvider);
    if (albums.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Álbumes recientes',
          subtitle: 'Vuelve a escuchar los discos que te gustan',
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

/// Tus playlists.
class _PlaylistsSection extends ConsumerWidget {
  const _PlaylistsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final playlists = ref.watch(playlistsProvider);
    if (playlists.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Tus playlists',
          subtitle: 'Colecciones hechas a tu manera',
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
    final offline = ref.watch(offlineModeProvider);
    final downloadedIds = (ref.watch(downloadsProvider).valueOrNull ?? const [])
        .map((entry) => entry.song.id)
        .toSet();
    final favorites = ref.watch(favoritesProvider);
    final favoritesShown = offline
        ? favorites.where((song) => downloadedIds.contains(song.id)).toList()
        : favorites;
    if (favoritesShown.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Tus favoritos',
          subtitle: 'Las canciones que siempre quieres oír',
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

/// Pantalla vacía cuando no hay historial ni favoritos.
class _EmptyHomeSection extends ConsumerWidget {
  const _EmptyHomeSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offline = ref.watch(offlineModeProvider);
    final downloadedIds = (ref.watch(downloadsProvider).valueOrNull ?? const [])
        .map((entry) => entry.song.id)
        .toSet();
    final history = ref.watch(historyProvider);
    final favorites = ref.watch(favoritesProvider);
    final recent = offline
        ? history.where((song) => downloadedIds.contains(song.id)).toList()
        : history;
    final favoritesShown = offline
        ? favorites.where((song) => downloadedIds.contains(song.id)).toList()
        : favorites;
    if (recent.isNotEmpty || favoritesShown.isNotEmpty) return const SizedBox.shrink();
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
    this.showBadge = false,
  });

  final List<SongModel> songs;
  final void Function(List<SongModel> songs, int index) onPlay;
  final bool showBadge;

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
              badge: showBadge ? 'PARA TI' : null,
              onTap: () => onPlay(songs, index),
            );
          },
        ),
      );
}

class _SongCard extends StatelessWidget {
  const _SongCard({required this.song, required this.onTap, this.badge});

  final SongModel song;
  final VoidCallback onTap;
  final String? badge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const artSize = 158.0;
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
                AlbumArt(
                  url: song.artworkUrl,
                  fallbackUrl: song.thumbnailUrl,
                  size: artSize,
                  radius: 18,
                ),
                Positioned(
                  right: 10,
                  bottom: 10,
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
                if (badge != null)
                  Positioned(
                    left: 10,
                    top: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: .55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        badge!,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 8.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: .8,
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

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.title, {required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
  const _CardsSkeleton();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle(
          'Hecho para ti',
          subtitle: 'Preparando recomendaciones según tus gustos…',
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

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
import '../../providers/player_providers.dart';
import '../../providers/settings_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/song_tile.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Buenos días';
    if (hour < 19) return 'Buenas tardes';
    return 'Buenas noches';
  }

  String _subtitle() {
    final hour = DateTime.now().hour;
    if (hour < 12) return 'Empieza el día con tu música.';
    if (hour < 19) return 'Tu banda sonora para esta tarde.';
    return 'Relájate con lo que más te gusta.';
  }

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs,
    int index,
  ) async {
    final playback = ref
        .read(audioHandlerProvider)
        .playSongs(songs, startIndex: index, shuffle: false);
    unawaited(requestPlaybackNotificationPermission(context: context));
    await ref.read(localRepositoryProvider).addHistory(songs[index]);
    ref.invalidate(historyProvider);
    if (context.mounted) context.push('/now-playing');
    await playback;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
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
    final playlists = ref.watch(playlistsProvider);
    final recommendations = offline
        ? const AsyncValue<List<SongModel>>.data(<SongModel>[])
        : ref.watch(homeRecommendationsProvider);
    final forYou = recommendations.valueOrNull ?? const <SongModel>[];
    final spotlight = offline
        ? null
        : ref.watch(artistSpotlightProvider).valueOrNull;
    final forYouIds = forYou.map((song) => song.id).toSet();
    final spotlightSongs = spotlight == null
        ? const <SongModel>[]
        : spotlight.songs
              .where((song) => !forYouIds.contains(song.id))
              .toList();
    final albums = offline ? null : ref.watch(homeRecentAlbumsProvider);
    final hour = DateTime.now().hour;

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
                    hour >= 19
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
              Padding(
                padding: const EdgeInsets.fromLTRB(22, 8, 22, 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _greeting(),
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.9,
                        height: 1.1,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _subtitle(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (offline)
                Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 2),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.tertiaryContainer.withValues(
                        alpha: .55,
                      ),
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
                ),
              if (recent.isNotEmpty) ...[
                const _SectionTitle(
                  'Seguir escuchando',
                  subtitle: 'Lo último que sonó en tu biblioteca',
                ),
                _SongRow(
                  songs: recent.take(10).toList(),
                  onPlay: (songs, index) => _play(context, ref, songs, index),
                ),
              ],
              if (forYou.isEmpty &&
                  recommendations.isLoading &&
                  (recent.isNotEmpty || favorites.isNotEmpty))
                const _CardsSkeleton()
              else if (forYou.isNotEmpty) ...[
                const _SectionTitle(
                  'Hecho para ti',
                  subtitle: 'Basado en tu historial y tus gustos',
                ),
                _SongRow(
                  songs: forYou,
                  onPlay: (songs, index) => _play(context, ref, songs, index),
                  showBadge: true,
                ),
              ],
              if (spotlight != null && spotlightSongs.isNotEmpty) ...[
                _SectionTitle(
                  'Más de ${spotlight.artistName}',
                  subtitle: 'Canciones y artistas parecidos a lo que estás escuchando',
                ),
                _SongRow(
                  songs: spotlightSongs,
                  onPlay: (songs, index) => _play(context, ref, songs, index),
                ),
              ],
              if (albums != null && albums.isNotEmpty) ...[
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
              if (playlists.isNotEmpty) ...[
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
              if (favoritesShown.isNotEmpty) ...[
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
              if (recent.isEmpty && favoritesShown.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(22, 30, 22, 0),
                  child: _EmptyHomeCard(),
                ),
              const SizedBox(height: 28),
            ],
          ),
        ],
      ),
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

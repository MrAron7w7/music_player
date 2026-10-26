import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/extensions.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/settings_providers.dart';

String _countLabel(int count, String singular, String plural) =>
    count == 1 ? '1 $singular' : '$count $plural';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final favorites = ref.watch(favoritesProvider);
    final playlists = ref.watch(playlistsProvider);
    final history = ref.watch(historyProvider);
    final downloads = ref.watch(downloadsProvider).valueOrNull ?? const [];
    final offline = ref.watch(offlineModeProvider);
    final downloadedIds = downloads.map((entry) => entry.song.id).toSet();
    final visibleFavorites = offline
        ? favorites.where((song) => downloadedIds.contains(song.id)).toList()
        : favorites;
    final visibleHistory = offline
        ? history.where((song) => downloadedIds.contains(song.id)).toList()
        : history;
    final playlistSongCount = playlists.fold<int>(
      0,
      (total, playlist) => total + playlist.songs.length,
    );
    final downloadDuration = downloads.fold<Duration>(
      Duration.zero,
      (total, entry) => total + (entry.song.duration ?? Duration.zero),
    );
    final favoriteDuration = visibleFavorites.fold<Duration>(
      Duration.zero,
      (total, song) => total + (song.duration ?? Duration.zero),
    );
    final historyDuration = visibleHistory.fold<Duration>(
      Duration.zero,
      (total, song) => total + (song.duration ?? Duration.zero),
    );

    final favoriteCover = visibleFavorites.firstOrNull?.artworkUrl;
    final playlistCover =
        playlists.firstOrNull?.coverUrl ??
        playlists.firstOrNull?.songs.firstOrNull?.artworkUrl;
    final historyCover = visibleHistory.firstOrNull?.artworkUrl;
    final downloadCover = downloads.firstOrNull?.song.artworkUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Tu biblioteca',
          style: theme.textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            letterSpacing: -.8,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Estadísticas',
            onPressed: () => context.push('/stats'),
            icon: const Icon(Icons.insights_rounded),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          if (offline)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: colors.tertiaryContainer.withValues(alpha: .55),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off_rounded,
                        size: 20,
                        color: colors.onTertiaryContainer,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Modo offline: solo se muestran canciones descargadas.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.onTertiaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.sizeOf(context).width >= 720 ? 3 : 2,
                crossAxisSpacing: 13,
                mainAxisSpacing: 13,
                childAspectRatio: .88,
              ),
              delegate: SliverChildListDelegate([
                _LibrarySectionCard(
                  title: 'Favoritos',
                  subtitle: offline
                      ? 'Tus favoritos disponibles sin conexión'
                      : 'Las canciones que más te gustan',
                  countLabel: _countLabel(
                    visibleFavorites.length,
                    'canción',
                    'canciones',
                  ),
                  detailLabel: favoriteDuration.hoursMinutes,
                  icon: Icons.favorite_rounded,
                  gradient: const [Color(0xFFE84393), Color(0xFF8E2DE2)],
                  coverUrl: favoriteCover,
                  onTap: () => context.push('/library/favorites'),
                ),
                _LibrarySectionCard(
                  title: 'Playlists',
                  subtitle: 'Colecciones hechas a tu medida',
                  countLabel: _countLabel(
                    playlists.length,
                    'playlist',
                    'playlists',
                  ),
                  detailLabel: _countLabel(
                    playlistSongCount,
                    'canción',
                    'canciones',
                  ),
                  icon: Icons.queue_music_rounded,
                  gradient: const [Color(0xFF2563EB), Color(0xFF7C3AED)],
                  coverUrl: playlistCover,
                  onTap: () => context.push('/library/playlists'),
                ),
                _LibrarySectionCard(
                  title: 'Historial',
                  subtitle: offline
                      ? 'Lo que has escuchado sin conexión'
                      : 'Vuelve a lo que estabas escuchando',
                  countLabel: _countLabel(
                    visibleHistory.length,
                    'canción',
                    'canciones',
                  ),
                  detailLabel: historyDuration.hoursMinutes,
                  icon: Icons.history_rounded,
                  gradient: const [Color(0xFFF2994A), Color(0xFFEB5757)],
                  coverUrl: historyCover,
                  onTap: () => context.push('/library/history'),
                ),
                _LibrarySectionCard(
                  title: 'Descargas',
                  subtitle: downloads.isEmpty
                      ? 'Guarda música para escucharla sin conexión'
                      : 'Tu música disponible en cualquier lugar',
                  countLabel: _countLabel(
                    downloads.length,
                    'canción',
                    'canciones',
                  ),
                  detailLabel: downloads.isEmpty
                      ? 'Sin conexión'
                      : downloadDuration.hoursMinutes,
                  icon: Icons.download_done_rounded,
                  gradient: const [Color(0xFF0F766E), Color(0xFF0EA5A4)],
                  coverUrl: downloadCover,
                  onTap: () => context.push('/downloads'),
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _LibrarySectionCard extends StatelessWidget {
  const _LibrarySectionCard({
    required this.title,
    required this.subtitle,
    required this.countLabel,
    required this.detailLabel,
    required this.icon,
    required this.gradient,
    required this.onTap,
    this.coverUrl,
  });

  final String title;
  final String subtitle;
  final String countLabel;
  final String detailLabel;
  final IconData icon;
  final List<Color> gradient;
  final String? coverUrl;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradient,
            ),
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverUrl != null)
                CachedNetworkImage(
                  imageUrl: coverUrl!,
                  fit: BoxFit.cover,
                  memCacheWidth: 420,
                  memCacheHeight: 560,
                  fadeInDuration: const Duration(milliseconds: 180),
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      gradient.first.withValues(alpha: .70),
                      gradient.last.withValues(alpha: .94),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: -34,
                top: -34,
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: .08),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(17),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .17),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: .14),
                            ),
                          ),
                          child: Icon(icon, color: Colors.white, size: 22),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: .20),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            detailLabel,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        height: 1.05,
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.7,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      countLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .86),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .64),
                        fontSize: 10.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

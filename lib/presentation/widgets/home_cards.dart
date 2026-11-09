import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/song_model.dart';
import '../../providers/player_providers.dart';
import 'album_art.dart';

const homeCardWidth = 148.0;

class HomeArtwork extends StatelessWidget {
  const HomeArtwork({
    super.key,
    this.url,
    this.size = homeCardWidth,
    this.radius = 16,
    this.circular = false,
  });

  final String? url;
  final double size;
  final double radius;
  final bool circular;

  @override
  Widget build(BuildContext context) =>
      AlbumArt(url: url, size: size, radius: circular ? size / 2 : radius);
}

class HomeSongCard extends ConsumerWidget {
  const HomeSongCard({
    super.key,
    required this.song,
    required this.queue,
    required this.index,
    this.width = homeCardWidth,
    this.onTap,
  });

  final SongModel song;
  final List<SongModel> queue;
  final int index;
  final double width;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    void play() {
      ref
          .read(audioHandlerProvider)
          .playSongs(queue, startIndex: index, shuffle: false);
    }

    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap ?? play,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              children: [
                HomeArtwork(url: song.artworkUrl, size: width),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: theme.colorScheme.primary,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: play,
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.play_arrow_rounded,
                          size: 20,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              song.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              song.artists.isEmpty
                  ? 'Artista desconocido'
                  : song.artists.join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeAlbumCard extends StatelessWidget {
  const HomeAlbumCard({
    super.key,
    required this.title,
    this.subtitle,
    this.imageUrl,
    required this.onTap,
    this.width = homeCardWidth,
    this.radius = 16,
    this.circular = false,
  });

  final String title;
  final String? subtitle;
  final String? imageUrl;
  final VoidCallback onTap;
  final double width;
  final double radius;
  final bool circular;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            HomeArtwork(
              url: imageUrl,
              size: width,
              radius: radius,
              circular: circular,
            ),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                height: 1.2,
              ),
            ),
            if (subtitle != null && subtitle!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant.withValues(
                    alpha: .8,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Portada compuesta de hasta 4 canciones para las mezclas diarias.
class MixArtwork extends StatelessWidget {
  const MixArtwork({
    super.key,
    required this.urls,
    this.size = homeCardWidth,
    this.radius = 16,
  });

  final List<String> urls;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget fallback() => Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.auto_awesome_rounded,
        color: theme.colorScheme.primary,
        size: size * .3,
      ),
    );

    Widget content;
    if (urls.isEmpty) {
      content = fallback();
    } else if (urls.length == 1) {
      content = AlbumArt(url: urls.first, size: size, radius: 0);
    } else {
      final half = size / 2;
      content = Column(
        children: [
          Row(
            children: [
              AlbumArt(url: urls[0], size: half, radius: 0),
              AlbumArt(
                url: urls.length > 1 ? urls[1] : null,
                size: half,
                radius: 0,
              ),
            ],
          ),
          Row(
            children: [
              AlbumArt(
                url: urls.length > 2 ? urls[2] : urls[0],
                size: half,
                radius: 0,
              ),
              AlbumArt(
                url: urls.length > 3 ? urls[3] : urls[1],
                size: half,
                radius: 0,
              ),
            ],
          ),
        ],
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: SizedBox(width: size, height: size, child: content),
    );
  }
}

class HomeMixCard extends StatelessWidget {
  const HomeMixCard({
    super.key,
    required this.title,
    required this.subtitle,
    required this.urls,
    required this.onTap,
    this.width = homeCardWidth,
  });

  final String title;
  final String subtitle;
  final List<String> urls;
  final VoidCallback onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            MixArtwork(urls: urls, size: width),
            const SizedBox(height: 8),
            Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .8),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class HomeMoodCard extends StatelessWidget {
  const HomeMoodCard({
    super.key,
    required this.title,
    this.subtitle,
    this.icon = Icons.auto_awesome_rounded,
    required this.onTap,
    required this.colors,
    required this.imageUrl,
    this.width = 158,
    this.height = 96,
  });

  final String title;
  final String? subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final List<Color> colors;
  final String imageUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: width,
    height: height,
    child: Material(
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: colors,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
          ),
          CachedNetworkImage(
            imageUrl: imageUrl,
            fit: BoxFit.cover,
            fadeInDuration: const Duration(milliseconds: 220),
            memCacheWidth: 600,
            placeholder: (_, _) => const SizedBox.shrink(),
            errorWidget: (_, _, _) => const SizedBox.shrink(),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [.18, 1],
                colors: [
                  Colors.black.withValues(alpha: .05),
                  Colors.black.withValues(alpha: .74),
                ],
              ),
            ),
          ),
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 11, 12, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.black.withValues(alpha: .32),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: .28),
                        ),
                      ),
                      child: Icon(icon, color: Colors.white, size: 17),
                    ),
                    const Spacer(),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        height: 1.1,
                      ),
                    ),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .82),
                          fontSize: 11,
                          height: 1.2,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class HomeListError extends StatelessWidget {
  const HomeListError({super.key, required this.message, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
    child: Row(
      children: [
        Icon(
          Icons.cloud_off_rounded,
          size: 18,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Reintentar')),
      ],
    ),
  );
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/player_providers.dart';
import 'album_art.dart';

final Set<String> _prefetchedArtworkIds = <String>{};

void _prefetchUpcomingArtwork(
  BuildContext context,
  List<MediaItem> queue,
  int currentIndex,
) {
  final start = currentIndex.clamp(0, queue.length);
  for (
    var index = start + 1;
    index < queue.length && index <= start + 2;
    index++
  ) {
    final item = queue[index];
    final uri = item.artUri;
    if (uri == null || !_prefetchedArtworkIds.add(item.id)) continue;
    if (!context.mounted) return;
    unawaited(
      precacheImage(
        CachedNetworkImageProvider(
          uri.toString(),
          maxWidth: 512,
          maxHeight: 512,
        ),
        context,
      ).catchError((_) {
        _prefetchedArtworkIds.remove(item.id);
      }),
    );
  }
  while (_prefetchedArtworkIds.length > 100) {
    _prefetchedArtworkIds.remove(_prefetchedArtworkIds.first);
  }
}

class MiniPlayer extends ConsumerWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen(queueProvider, (_, state) {
      final queue = state.valueOrNull;
      if (queue != null) {
        _prefetchUpcomingArtwork(
          context,
          queue,
          ref.read(playbackStateProvider).valueOrNull?.queueIndex ?? 0,
        );
      }
    });
    ref.listen(
      playbackStateProvider.select((state) => state.valueOrNull?.queueIndex),
      (_, queueIndex) {
        final queue = ref.read(queueProvider).valueOrNull;
        if (queue != null) {
          _prefetchUpcomingArtwork(context, queue, queueIndex ?? 0);
        }
      },
    );
    final song = ref.watch(currentSongProvider).valueOrNull;
    final theme = Theme.of(context);
    final accent =
        ref.watch(albumArtColorProvider).valueOrNull ??
        theme.colorScheme.primary;
    final playing = ref.watch(isPlayingProvider).valueOrNull ?? false;
    final error = ref.watch(playbackErrorProvider);
    final processingState = ref.watch(
      playbackStateProvider.select(
        (state) => state.valueOrNull?.processingState,
      ),
    );
    final loading =
        ref.read(audioHandlerProvider).isResolvingStream ||
        processingState == AudioProcessingState.loading ||
        processingState == AudioProcessingState.buffering;

    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: song == null
          ? const SizedBox(
              width: double.infinity,
              key: ValueKey('empty-player'),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  color: Color.lerp(
                    theme.colorScheme.surfaceContainerHigh,
                    accent,
                    theme.brightness == Brightness.dark ? .12 : .07,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: .22)),
                ),
                child: Material(
                  color: Colors.transparent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniPlayerProgress(
                        fallbackDuration: song.duration,
                        accent: accent,
                      ),
                      InkWell(
                        onTap: () => context.push('/now-playing'),
                        child: SizedBox(
                          height: 70,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 10, right: 6),
                            child: Row(
                              children: [
                                Hero(
                                  tag: 'art-${song.id}',
                                  child: AlbumArt(
                                    url: song.artworkUrl,
                                    fallbackUrl: song.thumbnailUrl,
                                    size: 48,
                                    radius: 11,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        song.title,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        error ??
                                            (loading
                                                ? 'Cargando audio…'
                                                : song.artists.join(', ')),
                                        maxLines: error != null ? 2 : 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .bodySmall
                                            ?.copyWith(
                                              color: error != null
                                                  ? Theme.of(context)
                                                        .colorScheme
                                                        .error
                                                  : Theme.of(context)
                                                        .colorScheme
                                                        .onSurfaceVariant,
                                              fontWeight: error != null
                                                  ? FontWeight.w600
                                                  : null,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (error != null)
                                  IconButton(
                                    tooltip: 'Reintentar',
                                    onPressed: () => ref
                                        .read(audioHandlerProvider)
                                        .retryCurrent(),
                                    icon: Icon(
                                      Icons.refresh_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .error,
                                    ),
                                  )
                                else if (loading)
                                  const SizedBox(
                                    width: 44,
                                    height: 44,
                                    child: Padding(
                                      padding: EdgeInsets.all(14),
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  )
                                else
                                  IconButton(
                                    tooltip: playing ? 'Pausar' : 'Reproducir',
                                    onPressed: () {
                                      HapticFeedback.selectionClick();
                                      if (playing) {
                                        ref.read(audioHandlerProvider).pause();
                                      } else {
                                        ref.read(audioHandlerProvider).play();
                                      }
                                    },
                                    icon: Icon(
                                      playing
                                          ? Icons.pause_rounded
                                          : Icons.play_arrow_rounded,
                                    ),
                                  ),
                                IconButton(
                                  tooltip: 'Siguiente',
                                  onPressed:
                                      loading ||
                                          !ref
                                              .read(audioHandlerProvider)
                                              .hasNext
                                      ? null
                                      : () {
                                          HapticFeedback.selectionClick();
                                          ref
                                              .read(audioHandlerProvider)
                                              .skipToNext();
                                        },
                                  icon: const Icon(Icons.skip_next_rounded),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
    );
  }
}

class _MiniPlayerProgress extends ConsumerWidget {
  const _MiniPlayerProgress({
    required this.fallbackDuration,
    required this.accent,
  });

  final Duration? fallbackDuration;
  final Color accent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;
    final duration =
        ref.watch(durationProvider).valueOrNull ?? fallbackDuration;
    final progress = duration == null || duration.inMilliseconds == 0
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    return LinearProgressIndicator(
      value: progress,
      minHeight: 2,
      valueColor: AlwaysStoppedAnimation<Color>(accent),
      backgroundColor: Theme.of(context).colorScheme.onSurface
          .withValues(alpha: .08),
      borderRadius: BorderRadius.zero,
    );
  }
}

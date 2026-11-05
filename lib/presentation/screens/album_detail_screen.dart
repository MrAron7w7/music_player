import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/notification_permissions.dart';
import '../../data/models/album_model.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/network_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_shimmer.dart';
import '../widgets/song_tile.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.albumId});
  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumDetailsProvider(albumId));
    final offline = ref.watch(effectiveOfflineProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Álbum')),
      body: album.when(
        loading: () => const LoadingShimmer(),
        error: (error, _) {
          final local = offline ? _localAlbum(ref) : null;
          if (local != null) {
            return _content(context, ref, local, offline: true);
          }
          return Center(
            child: EmptyState(
              icon: offline ? Icons.cloud_off_rounded : Icons.album_rounded,
              title: offline ? 'Sin conexión' : 'No se pudo cargar el álbum',
              message: offline
                  ? 'No encontramos este álbum en tus descargas, favoritos ni historial.'
                  : '$error',
              onRetry: offline
                  ? null
                  : () => ref.invalidate(albumDetailsProvider(albumId)),
            ),
          );
        },
        data: (value) {
          if (value == null) {
            final local = offline ? _localAlbum(ref) : null;
            if (local != null) {
              return _content(context, ref, local, offline: true);
            }
            return Center(
              child: EmptyState(
                icon: Icons.album_rounded,
                title: 'Álbum no disponible',
                message: offline
                    ? 'No está en tu biblioteca local. Conéctate para verlo completo.'
                    : 'YouTube Music no devolvió información para este álbum.',
                onRetry: offline
                    ? null
                    : () => ref.invalidate(albumDetailsProvider(albumId)),
              ),
            );
          }
          return _content(context, ref, value, offline: offline);
        },
      ),
    );
  }

  AlbumModel? _localAlbum(WidgetRef ref) {
    final pool = <SongModel>[
      ...ref.watch(downloadedSongsProvider),
      ...ref.watch(favoritesProvider),
      ...ref.watch(historyProvider),
    ];
    final seen = <String>{};
    final songs = <SongModel>[];
    for (final song in pool) {
      if (song.id.isEmpty || !seen.add(song.id)) continue;
      if (song.albumId != albumId) continue;
      songs.add(song);
    }
    if (songs.isEmpty) return null;
    songs.sort((a, b) => a.title.compareTo(b.title));
    final first = songs.first;
    return AlbumModel(
      id: albumId,
      title: first.album?.trim().isNotEmpty == true ? first.album! : 'Álbum',
      artists: first.artists,
      year: first.year,
      thumbnailUrl: first.artworkUrl,
      songs: songs,
      songCount: songs.length,
    );
  }

  Widget _content(
    BuildContext context,
    WidgetRef ref,
    AlbumModel value, {
    bool offline = false,
  }) {
    final songs = value.songs ?? const <SongModel>[];
    final downloadedIds = ref.watch(downloadedSongIdsProvider);
    final downloadedCount = songs
        .where((song) => downloadedIds.contains(song.id))
        .length;
    // Solo se reconstruye cuando cambia el progreso de las canciones de
    // este álbum, no en cada tick de descarga (cada 100 ms).
    final downloading = ref.watch(
      downloadProgressProvider.select((progress) {
        final map = progress.valueOrNull;
        if (map == null) return false;
        return songs.any((song) => map.containsKey(song.id));
      }),
    );
    return ListView(
      children: [
        Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            children: [
              AlbumArt(url: value.thumbnailUrl, size: 240, radius: 22),
              const SizedBox(height: 18),
              Text(
                value.title,
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              Text(
                value.artists.join(', '),
                style: Theme.of(context).textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
              if (songs.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  '$downloadedCount de ${songs.length} descargadas',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              if (offline) ...[
                const SizedBox(height: 6),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 16),
                    const SizedBox(width: 6),
                    Text(
                      'Sin conexión · desde tu biblioteca',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: songs.isEmpty
                        ? null
                        : () async {
                            unawaited(
                              requestPlaybackNotificationPermission(
                                context: context,
                              ),
                            );
                            await ref
                                .read(audioHandlerProvider)
                                .playSongs(
                                  songs,
                                  startIndex: 0,
                                  shuffle: false,
                                );
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Reproducir'),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Reproducir en aleatorio',
                    onPressed: songs.isEmpty
                        ? null
                        : () async {
                            await ref
                                .read(audioHandlerProvider)
                                .playSongs(songs, startIndex: 0, shuffle: true);
                            if (context.mounted) {
                              context.push('/now-playing');
                              unawaited(
                                requestPlaybackNotificationPermission(
                                  context: context,
                                ),
                              );
                            }
                          },
                    icon: const Icon(Icons.shuffle_rounded),
                  ),
                  IconButton.filledTonal(
                    tooltip: 'Descargar álbum',
                    onPressed: songs.isEmpty || downloading
                        ? null
                        : () async {
                            final result = await ref
                                .read(downloadServiceProvider)
                                .downloadMany(
                                  songs,
                                  quality: ref
                                      .read(musicRepositoryProvider)
                                      .quality,
                                );
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    result.completed == result.total
                                        ? 'Álbum descargado'
                                        : '${result.completed} descargadas · ${result.failed} fallidas',
                                  ),
                                ),
                              );
                            }
                          },
                    icon: downloading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.download_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
        ...songs.asMap().entries.map(
          (entry) => SongTile(
            entry.value,
            playQueue: songs,
            startIndex: entry.key,
            key: ValueKey(entry.value.id),
          ),
        ),
        const SizedBox(height: 40),
      ],
    );
  }
}

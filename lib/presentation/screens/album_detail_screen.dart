import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/downloads_providers.dart';
import '../../core/utils/notification_permissions.dart';
import '../widgets/album_art.dart';
import '../widgets/song_tile.dart';
import '../widgets/loading_shimmer.dart';

class AlbumDetailScreen extends ConsumerWidget {
  const AlbumDetailScreen({super.key, required this.albumId});
  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final album = ref.watch(albumDetailsProvider(albumId));
    return Scaffold(
      appBar: AppBar(title: const Text('Álbum')),
      body: album.when(
        loading: () => const LoadingShimmer(),
        error: (error, _) => Center(child: Text('No se pudo cargar: $error')),
        data: (value) {
          if (value == null) {
            return const Center(child: Text('Álbum no disponible'));
          }
          final songs = value.songs ?? const [];
          final downloadedIds =
              ref
                  .watch(downloadsProvider)
                  .valueOrNull
                  ?.map((entry) => entry.song.id)
                  .toSet() ??
              const <String>{};
          final downloadedCount = songs
              .where((song) => downloadedIds.contains(song.id))
              .length;
          final progress = ref.watch(downloadProgressProvider).valueOrNull;
          final downloading =
              progress != null &&
              songs.any((song) => progress.containsKey(song.id));
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
                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
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
                        const SizedBox(width: 10),
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
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

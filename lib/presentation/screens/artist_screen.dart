import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/notification_permissions.dart';
import '../../data/models/album_model.dart';
import '../../data/models/song_model.dart';
import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_shimmer.dart';
import '../widgets/song_tile.dart';

/// Página pública de un artista: portada, nombre, canciones top y álbumes.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({super.key, required this.artistId});
  final String artistId;

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs, {
    bool shuffle = false,
    int startIndex = 0,
  }) async {
    await ref.read(audioHandlerProvider).playSongs(
      songs,
      startIndex: startIndex,
      shuffle: shuffle,
    );
    if (!context.mounted) return;
    context.push('/now-playing');
    unawaited(requestPlaybackNotificationPermission(context: context));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artist = ref.watch(artistPageProvider(artistId));
    return Scaffold(
      body: artist.when(
        loading: () => const LoadingShimmer(),
        error: (error, _) => Center(
          child: EmptyState(
            icon: Icons.error_outline_rounded,
            title: 'No se pudo cargar el artista',
            message: '$error',
            onRetry: () => ref.invalidate(artistPageProvider(artistId)),
            retryLabel: 'Reintentar',
          ),
        ),
        data: (value) {
          if (value.cancionesTop.isEmpty && value.albumes.isEmpty) {
            return const Center(
              child: EmptyState(
                icon: Icons.person_off_rounded,
                title: 'Sin contenido disponible',
                message: 'Este artista no tiene canciones ni álbumes.',
              ),
            );
          }
          return CustomScrollView(
            slivers: [
              SliverAppBar(
                expandedHeight: 320,
                floating: false,
                pinned: true,
                flexibleSpace: FlexibleSpaceBar(
                  background: value.thumb != null
                      ? AlbumArt(
                          url: value.thumb,
                          size: double.infinity,
                          radius: 0,
                        )
                      : Container(
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                ),
              ),
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(22, 10, 22, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        value.name,
                        style: Theme.of(context)
                            .textTheme
                            .headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          FilledButton.icon(
                            onPressed: value.cancionesTop.isEmpty
                                ? null
                                : () => _play(context, ref, value.cancionesTop),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Reproducir'),
                          ),
                          const SizedBox(width: 10),
                          IconButton.filledTonal(
                            onPressed: value.cancionesTop.isEmpty
                                ? null
                                : () => _play(
                                      context,
                                      ref,
                                      value.cancionesTop,
                                      shuffle: true,
                                    ),
                            icon: const Icon(Icons.shuffle_rounded),
                            tooltip: 'Reproducir en aleatorio',
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (value.cancionesTop.isNotEmpty)
                _cancionesTopSection(context, ref, value.cancionesTop),
              if (value.albumes.isNotEmpty)
                _albumesSection(context, value.albumes),
              const SliverToBoxAdapter(
                child: SizedBox(height: 28),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _cancionesTopSection(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs,
  ) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Text(
              'Canciones más populares',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          ...songs.asMap().entries.map(
            (entry) => SongTile(
              entry.value,
              playQueue: songs,
              startIndex: entry.key,
              key: ValueKey(entry.value.id),
              onTap: () => _play(context, ref, songs, startIndex: entry.key),
            ),
          ),
        ],
      ),
    );
  }

  Widget _albumesSection(BuildContext context, List<AlbumModel> albumes) {
    return SliverToBoxAdapter(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Text(
              'Álbumes',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
          SizedBox(
            height: 208,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 22),
              itemCount: albumes.length,
              separatorBuilder: (_, _) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final album = albumes[index];
                return SizedBox(
                  width: 150,
                  child: InkWell(
                    onTap: () => context.push('/album/${album.id}'),
                    borderRadius: BorderRadius.circular(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AlbumArt(url: album.thumbnailUrl, size: 150, radius: 18),
                        const SizedBox(height: 10),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          album.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                              ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

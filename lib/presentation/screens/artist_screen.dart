import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/notification_permissions.dart';
import '../../data/models/album_model.dart';
import '../../data/models/artist_model.dart';
import '../../data/models/home_models.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/followed_artists_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/network_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/search_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/loading_shimmer.dart';
import '../widgets/song_tile.dart';

/// Página pública de un artista: portada, nombre, canciones y álbumes.
class ArtistScreen extends ConsumerWidget {
  const ArtistScreen({
    super.key,
    required this.artistId,
    this.fromSearch = false,
  });

  final String artistId;

  /// Cuando se abre desde el buscador, una página sin contenido se cierra y
  /// oculta el artista de los resultados en lugar de mostrar un estado vacío.
  final bool fromSearch;

  Future<void> _play(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs, {
    bool shuffle = false,
    int startIndex = 0,
  }) async {
    await ref
        .read(audioHandlerProvider)
        .playSongs(songs, startIndex: startIndex, shuffle: shuffle);
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
        error: (error, _) {
          final local = ref.watch(effectiveOfflineProvider)
              ? _localArtistPage(ref)
              : null;
          if (local != null) {
            return _localFallback(context, ref, local);
          }
          return Center(
            child: EmptyState(
              icon: Icons.error_outline_rounded,
              title: 'No se pudo cargar el artista',
              message: 'No pudimos cargar este artista. Revisa tu conexión e inténtalo de nuevo.',
              onRetry: () => ref.invalidate(artistPageProvider(artistId)),
              retryLabel: 'Reintentar',
            ),
          );
        },
        data: (value) {
          final songs = value.todasLasCanciones;
          if (!value.tieneContenido) {
            if (fromSearch) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (!context.mounted) return;
                ref
                    .read(hiddenArtistIdsProvider.notifier)
                    .update((ids) => {...ids, artistId});
                final messenger = ScaffoldMessenger.maybeOf(context);
                if (context.canPop()) context.pop();
                messenger?.showSnackBar(
                  SnackBar(
                    content: Text(
                      '${value.name} no tiene canciones disponibles.',
                    ),
                  ),
                );
              });
              return const Center(child: CircularProgressIndicator());
            }
            return Center(
              child: EmptyState(
                icon: Icons.person_off_rounded,
                title: 'Sin contenido disponible',
                message: 'Este artista no tiene canciones ni álbumes.',
                onRetry: () {
                  if (context.canPop()) context.pop();
                },
                retryLabel: 'Volver',
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
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            AlbumArt(
                              url: value.thumb,
                              size: double.infinity,
                              radius: 0,
                            ),
                            const DecoratedBox(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [Colors.transparent, Colors.black54],
                                  stops: [.55, 1],
                                ),
                              ),
                            ),
                          ],
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
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilledButton.icon(
                            onPressed: songs.isEmpty
                                ? null
                                : () => _play(context, ref, songs),
                            icon: const Icon(Icons.play_arrow_rounded),
                            label: const Text('Reproducir'),
                          ),
                          IconButton.filledTonal(
                            onPressed: songs.isEmpty
                                ? null
                                : () =>
                                      _play(context, ref, songs, shuffle: true),
                            icon: const Icon(Icons.shuffle_rounded),
                            tooltip: 'Reproducir en aleatorio',
                          ),
                          _followButton(context, ref, value),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (songs.isNotEmpty)
                _songsSection(
                  context,
                  ref,
                  songs,
                  all: value.canciones.isNotEmpty,
                ),
              if (value.albumes.isNotEmpty)
                _albumesSection(context, value.albumes),
              const SliverToBoxAdapter(child: SizedBox(height: 28)),
            ],
          );
        },
      ),
    );
  }

  Widget _songsSection(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs, {
    required bool all,
  }) {
    return SliverList.builder(
      itemCount: songs.length + 1,
      itemBuilder: (context, index) {
        if (index == 0) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Text(
              all ? 'Canciones' : 'Canciones más populares',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          );
        }
        final songIndex = index - 1;
        final song = songs[songIndex];
        return SongTile(
          song,
          playQueue: songs,
          startIndex: songIndex,
          key: ValueKey(song.id),
          onTap: () => _play(context, ref, songs, startIndex: songIndex),
        );
      },
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
                        AlbumArt(
                          url: album.thumbnailUrl,
                          size: 150,
                          radius: 18,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          album.artists.join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.bodySmall
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

  Widget _followButton(
    BuildContext context,
    WidgetRef ref,
    ArtistPageModel value,
  ) {
    final following = ref.watch(isFollowingArtistProvider(artistId));
    return OutlinedButton.icon(
      onPressed: () async {
        final nowFollowing = await ref
            .read(followedArtistsProvider.notifier)
            .toggle(
              FollowedArtist(
                id: artistId,
                name: value.name,
                thumbnailUrl: value.thumb,
                followedAt: DateTime.now(),
              ),
            );
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              nowFollowing
                  ? 'Ahora sigues a ${value.name}'
                  : 'Has dejado de seguir a ${value.name}',
            ),
          ),
        );
      },
      icon: Icon(
        following ? Icons.check_rounded : Icons.person_add_alt_1_rounded,
      ),
      label: Text(following ? 'Siguiendo' : 'Seguir'),
    );
  }

  ArtistPageModel? _localArtistPage(WidgetRef ref) {
    final pool = <SongModel>[
      ...ref.watch(downloadedSongsProvider),
      ...ref.watch(favoritesProvider),
      ...ref.watch(historyProvider),
    ];
    final seen = <String>{};
    final songs = <SongModel>[];
    for (final song in pool) {
      if (song.id.isEmpty || !seen.add(song.id)) continue;
      if (!(song.artistIds ?? const <String>[]).contains(artistId)) continue;
      songs.add(song);
    }
    if (songs.isEmpty) return null;
    songs.sort((a, b) => a.title.compareTo(b.title));
    final albumsById = <String, AlbumModel>{};
    for (final song in songs) {
      final albumId = song.albumId;
      if (albumId == null || albumId.isEmpty) continue;
      albumsById.putIfAbsent(
        albumId,
        () => AlbumModel(
          id: albumId,
          title: song.album?.trim().isNotEmpty == true ? song.album! : 'Álbum',
          artists: song.artists,
          thumbnailUrl: song.artworkUrl,
          songs: [song],
        ),
      );
    }
    return ArtistPageModel(
      name: songs.first.artists.firstOrNull ?? 'Artista',
      thumb: songs.first.artworkUrl,
      cancionesTop: songs.take(25).toList(),
      canciones: songs,
      albumes: albumsById.values.toList(),
    );
  }

  Widget _localFallback(
    BuildContext context,
    WidgetRef ref,
    ArtistPageModel value,
  ) {
    return CustomScrollView(
      slivers: [
        SliverAppBar(pinned: true, title: Text(value.name)),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(22, 14, 22, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value.name,
                  style: Theme.of(context).textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.cloud_off_rounded, size: 16),
                    const SizedBox(width: 6),
                    const Expanded(
                      child: Text(
                        'Sin conexión: mostrando canciones de tu biblioteca.',
                      ),
                    ),
                    _followButton(context, ref, value),
                  ],
                ),
              ],
            ),
          ),
        ),
        if (value.todasLasCanciones.isNotEmpty)
          _songsSection(
            context,
            ref,
            value.todasLasCanciones,
            all: value.canciones.isNotEmpty,
          ),
        if (value.albumes.isNotEmpty) _albumesSection(context, value.albumes),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}

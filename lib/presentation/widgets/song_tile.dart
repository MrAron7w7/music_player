import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/extensions.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/notification_permissions.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import 'album_art.dart';

class SongTile extends ConsumerWidget {
  const SongTile(
    this.song, {
    super.key,
    this.onTap,
    this.onLongPress,
    this.playQueue,
    this.startIndex = 0,
    this.selectionMode = false,
    this.selected = false,
    this.onSelect,
    this.trailingExtra,
  });
  final SongModel song;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final List<SongModel>? playQueue;
  final int startIndex;
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onSelect;
  final Widget? trailingExtra;

  Future<void> _addToPlaylist(BuildContext context, WidgetRef ref) async {
    final lists = ref.read(playlistsProvider);
    if (lists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crea una playlist desde Biblioteca primero.'),
        ),
      );
      return;
    }
    final selected = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Añadir a playlist')),
            ...lists.map(
              (p) => ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(p.name),
                subtitle: Text('${p.songs.length} canciones'),
                onTap: () => Navigator.pop(ctx, p.id),
              ),
            ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    final playlist = lists.firstWhere((entry) => entry.id == selected);
    final songs = [...playlist.songs.where((item) => item.id != song.id), song];
    await ref
        .read(localRepositoryProvider)
        .updatePlaylist(playlist, songs: songs);
    ref.invalidate(playlistsProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Añadida a ${playlist.name}')));
    }
  }

  Future<void> _toggleFavorite(WidgetRef ref) async {
    await ref.read(localRepositoryProvider).toggleFavorite(song);
    ref.invalidate(favoritesProvider);
  }

  Future<void> _download(BuildContext context, WidgetRef ref) async {
    final service = ref.read(downloadServiceProvider);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Descargando “${song.title}”…')));
    try {
      await service.download(
        song,
        quality: ref.read(musicRepositoryProvider).quality,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Descarga completada')));
      }
    } catch (error) {
      if (error.toString() == 'Descarga cancelada.') return;
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.toString())));
      }
    }
  }

  Future<void> _play(BuildContext context, WidgetRef ref) async {
    final playback = ref
        .read(audioHandlerProvider)
        .playSongs(
          playQueue ?? [song],
          startIndex: playQueue == null ? 0 : startIndex,
          shuffle: false,
        );
    // La navegación no espera a Hive ni a resolver el stream: la portada y la
    // metadata aparecen de inmediato y el audio termina de cargar en paralelo.
    if (context.mounted) context.push('/now-playing');
    unawaited(requestPlaybackNotificationPermission(context: context));
    try {
      await playback;
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'No se pudo iniciar esta canción. Inténtalo de nuevo.',
            ),
          ),
        );
      }
    }
  }

  void _showSongSheet(BuildContext context, WidgetRef ref, bool isFavorite) {
    final service = ref.read(downloadServiceProvider);
    final progress = ref.read(downloadProgressProvider).valueOrNull?[song.id];
    final downloading = progress != null && progress < 1;
    final downloaded = service.isDownloaded(song.id);
    showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      builder: (ctx) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: AlbumArt(
                url: song.artworkUrl,
                fallbackUrl: song.thumbnailUrl,
                size: 46,
              ),
              title: Text(song.title),
              subtitle: Text(song.artists.join(', ')),
            ),
            ListTile(
              leading: const Icon(Icons.play_arrow_rounded),
              title: const Text('Reproducir ahora'),
              onTap: () {
                Navigator.pop(ctx);
                _play(context, ref);
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_play_rounded),
              title: const Text('Reproducir siguiente'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(audioHandlerProvider).playSongNext(song);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Se reproducirá a continuación'),
                    ),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: const Text('Agregar al final de la cola'),
              onTap: () async {
                Navigator.pop(ctx);
                await ref.read(audioHandlerProvider).addSongToQueue(song);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Añadida a la cola')),
                  );
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.playlist_add_rounded),
              title: const Text('Añadir a playlist'),
              onTap: () {
                Navigator.pop(ctx);
                _addToPlaylist(context, ref);
              },
            ),
            ListTile(
              leading: Icon(
                isFavorite
                    ? Icons.favorite_rounded
                    : Icons.favorite_border_rounded,
              ),
              title: Text(
                isFavorite ? 'Quitar de favoritos' : 'Añadir a favoritos',
              ),
              onTap: () {
                Navigator.pop(ctx);
                _toggleFavorite(ref);
              },
            ),
            ListTile(
              leading: Icon(
                downloading
                    ? Icons.close_rounded
                    : downloaded
                    ? Icons.delete_outline_rounded
                    : Icons.download_rounded,
              ),
              title: Text(
                downloading
                    ? 'Cancelar descarga'
                    : downloaded
                    ? 'Eliminar descarga'
                    : 'Descargar',
              ),
              onTap: () {
                Navigator.pop(ctx);
                if (downloading) {
                  unawaited(service.delete(song.id));
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Descarga cancelada')),
                    );
                  }
                } else if (downloaded) {
                  unawaited(service.delete(song.id));
                } else {
                  _download(context, ref);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isFavorite = ref.watch(isFavoriteProvider(song.id));
    final downloaded = ref.watch(isDownloadedProvider(song.id));
    final progress = ref.watch(downloadProgressForProvider(song.id));
    final downloading = progress != null && progress < 1;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: selected
            ? Theme.of(context).colorScheme.primary.withValues(alpha: .12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onLongPress: selectionMode
              ? onSelect
              : onLongPress ?? () => _showSongSheet(context, ref, isFavorite),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 3,
            ),
            leading: AlbumArt(
              url: song.artworkUrl,
              fallbackUrl: song.thumbnailUrl,
            ),
            title: Text(
              song.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              artistsText(song.artists),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: selectionMode
                ? Checkbox(
                    value: selected,
                    onChanged: (_) => onSelect?.call(),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  )
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (downloading)
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 2.2,
                          ),
                        )
                      else if (downloaded)
                        Icon(
                          Icons.download_done_rounded,
                          size: 18,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      IconButton(
                        tooltip: isFavorite
                            ? 'Quitar de favoritos'
                            : 'Añadir a favoritos',
                        onPressed: () => _toggleFavorite(ref),
                        icon: AnimatedSwitcher(
                          duration: const Duration(milliseconds: 180),
                          transitionBuilder: (child, animation) =>
                              ScaleTransition(scale: animation, child: child),
                          child: Icon(
                            isFavorite
                                ? Icons.favorite_rounded
                                : Icons.favorite_border_rounded,
                            key: ValueKey(isFavorite),
                            color: isFavorite
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant,
                            size: 21,
                          ),
                        ),
                      ),
                      if (song.duration != null)
                        Text(
                          song.duration!.mmss,
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      if (trailingExtra != null) trailingExtra!,
                      PopupMenuButton<String>(
                        onSelected: (value) {
                          switch (value) {
                            case 'favorite':
                              _toggleFavorite(ref);
                            case 'playlist':
                              _addToPlaylist(context, ref);
                            case 'play':
                              _play(context, ref);
                            case 'next':
                              ref.read(audioHandlerProvider).playSongNext(song);
                            case 'queue':
                              ref
                                  .read(audioHandlerProvider)
                                  .addSongToQueue(song);
                            case 'download':
                              _download(context, ref);
                            case 'cancel-download':
                              unawaited(
                                ref
                                    .read(downloadServiceProvider)
                                    .delete(song.id),
                              );
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Descarga cancelada'),
                                  ),
                                );
                              }
                            case 'remove-download':
                              unawaited(
                                ref
                                    .read(downloadServiceProvider)
                                    .delete(song.id),
                              );
                          }
                        },
                        itemBuilder: (_) => [
                          const PopupMenuItem(
                            value: 'play',
                            child: Text('Reproducir ahora'),
                          ),
                          const PopupMenuItem(
                            value: 'next',
                            child: Text('Reproducir siguiente'),
                          ),
                          const PopupMenuItem(
                            value: 'queue',
                            child: Text('Agregar al final de la cola'),
                          ),
                          const PopupMenuItem(
                            value: 'playlist',
                            child: Text('Añadir a playlist'),
                          ),
                          PopupMenuItem(
                            value: 'favorite',
                            child: Text(
                              isFavorite
                                  ? 'Quitar de favoritos'
                                  : 'Añadir a favoritos',
                            ),
                          ),
                          PopupMenuItem(
                            value: downloading
                                ? 'cancel-download'
                                : downloaded
                                ? 'remove-download'
                                : 'download',
                            child: Text(
                              downloading
                                  ? 'Cancelar descarga'
                                  : downloaded
                                  ? 'Eliminar descarga'
                                  : 'Descargar',
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
            onTap: selectionMode
                ? onSelect
                : onTap ?? () => _play(context, ref),
          ),
        ),
      ),
    );
  }
}

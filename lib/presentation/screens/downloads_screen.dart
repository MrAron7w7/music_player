import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/extensions.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/notification_permissions.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  Future<void> _playAll(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> songs, {
    required bool shuffle,
  }) async {
    if (songs.isEmpty) return;
    final index = shuffle ? math.Random().nextInt(songs.length) : 0;
    final playback = ref
        .read(audioHandlerProvider)
        .playSongs(songs, startIndex: index, shuffle: shuffle);
    if (context.mounted) context.push('/now-playing');
    unawaited(requestPlaybackNotificationPermission(context: context));
    await playback;
  }

  Future<void> _clearAll(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Borrar todas las descargas'),
        content: const Text(
          'Se eliminarán los archivos descargados. Podrás volver a descargarlos cuando quieras.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Borrar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadServiceProvider).deleteAll();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final downloads = ref.watch(downloadsProvider).valueOrNull ?? const [];
    final songs = downloads.map((entry) => entry.song).toList();
    final currentSong = ref.watch(currentSongProvider).valueOrNull;
    final heroEntry =
        downloads
            .where((entry) => entry.song.id == currentSong?.id)
            .firstOrNull ??
        downloads.firstOrNull;
    final totalDuration = songs.fold<Duration>(
      Duration.zero,
      (total, song) => total + (song.duration ?? Duration.zero),
    );
    final totalBytes = downloads.fold<int>(
      0,
      (total, entry) => total + entry.bytes,
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Descargas',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: [
          PopupMenuButton<String>(
            enabled: downloads.isNotEmpty,
            onSelected: (value) {
              if (value == 'clear') _clearAll(context, ref);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'clear',
                child: Text('Borrar todas las descargas'),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: downloads.isEmpty
          ? const EmptyState(
              icon: Icons.download_done_rounded,
              title: 'Todavía no hay descargas',
              message: 'Descarga canciones, álbumes o playlists para escucharlas sin conexión.',
            )
          : CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                    child: Column(
                      children: [
                        Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(30),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: .24),
                                blurRadius: 38,
                                spreadRadius: -6,
                                offset: const Offset(0, 20),
                              ),
                            ],
                          ),
                          child: AlbumArt(
                            url: heroEntry?.song.artworkUrl,
                            fallbackUrl: heroEntry?.song.thumbnailUrl,
                            size: 238,
                            radius: 30,
                          ),
                        ),
                        const SizedBox(height: 20),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colors.primary.withValues(alpha: .12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.offline_pin_rounded,
                                size: 14,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Disponible sin conexión',
                                style: TextStyle(
                                  color: colors.primary,
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Descargas',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -1,
                            height: 1.05,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          songs.length == 1
                              ? '1 canción · ${totalDuration.hoursMinutes}'
                              : '${songs.length} canciones · ${totalDuration.hoursMinutes}',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${formatBytes(totalBytes)} en tu dispositivo',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colors.onSurfaceVariant.withValues(
                              alpha: .72,
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: () => _playAll(
                                  context,
                                  ref,
                                  songs,
                                  shuffle: false,
                                ),
                                icon: const Icon(Icons.play_arrow_rounded),
                                label: const Text('Reproducir'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: () => _playAll(
                                  context,
                                  ref,
                                  songs,
                                  shuffle: true,
                                ),
                                icon: const Icon(Icons.shuffle_rounded),
                                label: const Text('Aleatorio'),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
                    child: Row(
                      children: [
                        Text(
                          'Todas las descargas',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                            letterSpacing: -.3,
                          ),
                        ),
                        const Spacer(),
                        Text(
                          '${songs.length}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: colors.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SliverList.builder(
                  itemCount: songs.length,
                  itemBuilder: (context, index) {
                    final song = songs[index];
                    return SongTile(song, playQueue: songs, startIndex: index);
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            ),
    );
  }
}

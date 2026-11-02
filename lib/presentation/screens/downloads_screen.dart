import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants/app_constants.dart';
import '../../core/utils/extensions.dart';
import '../../core/utils/helpers.dart';
import '../../core/utils/notification_permissions.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';
import '../../providers/settings_providers.dart';

/// Ordena una copia de las canciones según el criterio elegido por el
/// usuario, sin modificar el orden de inserción original.
List<SongModel> _sortDownloadsSongs(List<SongModel> sortedSongs, String order) {
  final result = List<SongModel>.from(sortedSongs);
  switch (order) {
    case 'title':
      result.sort(
        (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
      );
    case 'artist':
      result.sort((a, b) {
        final aa = a.artists.isNotEmpty ? a.artists.first.toLowerCase() : '';
        final bb = b.artists.isNotEmpty ? b.artists.first.toLowerCase() : '';
        return aa.compareTo(bb);
      });
    case 'duration':
      result.sort((a, b) =>
          (a.duration ?? Duration.zero).compareTo(b.duration ?? Duration.zero));
    case 'default':
    default:
      break;
  }
  return result;
}

String _sortDownloadsLabel(String order) => switch (order) {
      'default' => 'Por defecto (recientes)',
      'title' => 'Título A-Z',
      'artist' => 'Artista',
      'duration' => 'Duración',
      _ => 'Por defecto (recientes)',
    };

/// Consulta de búsqueda para filtrar las descargas por título o artista.
final downloadsSearchQueryProvider = StateProvider<String>((ref) => '');

void _showSortDownloadsSheet(BuildContext context, WidgetRef ref) {
  final current = ref.read(sortOrderProvider('downloads'));
  showModalBottomSheet<String>(
    context: context,
    useSafeArea: true,
    builder: (sheetContext) => Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const ListTile(title: Text('Ordenar canciones')),
        ...const <String>['default', 'title', 'artist', 'duration'].map(
          (value) => ListTile(
            leading: Icon(
              Icons.check_rounded,
              color: value == current
                  ? Theme.of(sheetContext).colorScheme.primary
                  : null,
              size: 20,
            ),
            title: Text(_sortDownloadsLabel(value)),
            onTap: () => Navigator.pop(sheetContext, value),
          ),
        ),
      ],
    ),
  ).then((selected) {
    if (selected == null) return;
    ref.read(localRepositoryProvider).settings.put(
          AppConstants.sortDownloadsKey,
          selected,
        );
    ref.read(sortOrderProvider('downloads').notifier).state = selected;
  });
}

class DownloadsScreen extends ConsumerWidget {
  const DownloadsScreen({super.key});

  Future<void> _playAll(
    BuildContext context,
    WidgetRef ref,
    List<SongModel> sortedSongs, {
    required bool shuffle,
  }) async {
    if (sortedSongs.isEmpty) return;
    final index = shuffle ? math.Random().nextInt(sortedSongs.length) : 0;
    final playback = ref
        .read(audioHandlerProvider)
        .playSongs(sortedSongs, startIndex: index, shuffle: shuffle);
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
    final allSongs = downloads.map((entry) => entry.song).toList();
    final searchQuery = ref.watch(downloadsSearchQueryProvider).trim();
    final rawSongs = searchQuery.isEmpty
        ? allSongs
        : allSongs.where((song) {
            final q = searchQuery.toLowerCase();
            return song.title.toLowerCase().contains(q) ||
                song.artists.join(' ').toLowerCase().contains(q);
          }).toList();
    final sortOrder = ref.watch(sortOrderProvider('downloads'));
    final sortedSongs = _sortDownloadsSongs(rawSongs, sortOrder);
    final currentSong = ref.watch(currentSongProvider).valueOrNull;
    final heroEntry =
        downloads
            .where((entry) => entry.song.id == currentSong?.id)
            .firstOrNull ??
        downloads.firstOrNull;
    final totalDuration = sortedSongs.fold<Duration>(
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
          IconButton(
            tooltip: 'Ordenar',
            onPressed: () => _showSortDownloadsSheet(context, ref),
            icon: const Icon(Icons.sort_rounded),
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
                          sortedSongs.length == 1
                              ? '1 canción · ${totalDuration.hoursMinutes}'
                              : '${sortedSongs.length} canciones · ${totalDuration.hoursMinutes}',
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
                                  sortedSongs,
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
                                  sortedSongs,
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
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 6),
                    child: TextField(
                      onChanged: (value) =>
                          ref.read(downloadsSearchQueryProvider.notifier).state =
                              value,
                      decoration: InputDecoration(
                        hintText: 'Buscar descargas',
                        hintStyle: TextStyle(
                          color: colors.onSurfaceVariant.withValues(alpha: .6),
                        ),
                        prefixIcon: const Icon(Icons.search_rounded, size: 20),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                tooltip: 'Limpiar búsqueda',
                                icon: const Icon(Icons.close_rounded, size: 20),
                                onPressed: () =>
                                    ref
                                        .read(downloadsSearchQueryProvider
                                            .notifier)
                                        .state = '',
                              )
                            : null,
                        filled: true,
                        fillColor: colors.surfaceContainerHighest,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: colors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
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
                          '${sortedSongs.length}',
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
                  itemCount: sortedSongs.length,
                  itemBuilder: (context, index) {
                    final song = sortedSongs[index];
                    return SongTile(song, playQueue: sortedSongs, startIndex: index);
                  },
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 30)),
              ],
            ),
    );
  }
}

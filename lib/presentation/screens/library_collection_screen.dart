import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/extensions.dart';
import '../../core/utils/notification_permissions.dart';
import '../../data/models/playlist_model.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/settings_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';

enum LibraryCollection { favorites, history }

class LibraryCollectionScreen extends ConsumerStatefulWidget {
  const LibraryCollectionScreen({super.key, required this.collection});

  final LibraryCollection collection;

  @override
  ConsumerState<LibraryCollectionScreen> createState() =>
      _LibraryCollectionScreenState();
}

class _LibraryCollectionScreenState
    extends ConsumerState<LibraryCollectionScreen> {
  final Set<String> _selected = <String>{};
  bool _selecting = false;
  bool _downloading = false;

  String get _title => switch (widget.collection) {
    LibraryCollection.favorites => 'Favoritos',
    LibraryCollection.history => 'Historial',
  };

  IconData get _icon => switch (widget.collection) {
    LibraryCollection.favorites => Icons.favorite_rounded,
    LibraryCollection.history => Icons.history_rounded,
  };

  List<Color> get _gradient => switch (widget.collection) {
    LibraryCollection.favorites => const [Color(0xFFE84393), Color(0xFF8E2DE2)],
    LibraryCollection.history => const [Color(0xFFF2994A), Color(0xFFEB5757)],
  };

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  void _toggleSelection(SongModel song) {
    setState(() {
      _selecting = true;
      if (_selected.contains(song.id)) {
        _selected.remove(song.id);
      } else {
        _selected.add(song.id);
      }
      if (_selected.isEmpty) _selecting = false;
    });
  }

  Future<void> _playAll(List<SongModel> songs, {required bool shuffle}) async {
    if (songs.isEmpty) return;
    final index = shuffle ? math.Random().nextInt(songs.length) : 0;
    final playback = ref
        .read(audioHandlerProvider)
        .playSongs(songs, startIndex: index, shuffle: shuffle);
    unawaited(requestPlaybackNotificationPermission(context: context));
    await ref.read(localRepositoryProvider).addHistory(songs[index]);
    ref.invalidate(historyProvider);
    if (mounted) context.push('/now-playing');
    await playback;
  }

  Future<void> _addSelectedToPlaylist(List<SongModel> selectedSongs) async {
    final lists = ref.read(playlistsProvider);
    if (lists.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Crea una playlist primero.')),
      );
      return;
    }
    final target = await showModalBottomSheet<PlaylistModel>(
      context: context,
      useSafeArea: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ListTile(title: Text('Añadir a playlist')),
            ...lists.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                subtitle: Text('${playlist.songs.length} canciones'),
                onTap: () => Navigator.pop(sheetContext, playlist),
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final ids = selectedSongs.map((song) => song.id).toSet();
    final merged = [
      ...target.songs.where((song) => !ids.contains(song.id)),
      ...selectedSongs,
    ];
    await ref
        .read(localRepositoryProvider)
        .updatePlaylist(target, songs: merged);
    ref.invalidate(playlistsProvider);
    if (mounted) {
      _clearSelection();
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Añadidas a ${target.name}')));
    }
  }

  Future<void> _downloadSelected(List<SongModel> selectedSongs) async {
    if (selectedSongs.isEmpty || _downloading) return;
    setState(() => _downloading = true);
    try {
      final result = await ref
          .read(downloadServiceProvider)
          .downloadMany(
            selectedSongs,
            quality: ref.read(musicRepositoryProvider).quality,
          );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${result.completed} descargadas · ${result.failed} fallidas',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _deleteSelected(List<SongModel> selectedSongs) async {
    final ids = selectedSongs.map((song) => song.id).toSet();
    final repository = ref.read(localRepositoryProvider);
    if (widget.collection == LibraryCollection.favorites) {
      await repository.removeFavorites(ids);
      ref.invalidate(favoritesProvider);
    } else {
      await repository.removeHistory(ids);
      ref.invalidate(historyProvider);
    }
    if (mounted) _clearSelection();
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Vaciar historial'),
        content: const Text(
          'Se eliminarán todas las canciones del historial. Tus favoritos y playlists no cambiarán.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Vaciar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(localRepositoryProvider).clearHistory();
    ref.invalidate(historyProvider);
  }

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesProvider);
    final history = ref.watch(historyProvider);
    final source = widget.collection == LibraryCollection.favorites
        ? favorites
        : history;
    final downloads = ref.watch(downloadsProvider).valueOrNull ?? const [];
    final offline = ref.watch(offlineModeProvider);
    final downloadedIds = downloads.map((entry) => entry.song.id).toSet();
    final visibleSongs = offline
        ? source.where((song) => downloadedIds.contains(song.id)).toList()
        : source;
    final selectedSongs = visibleSongs
        .where((song) => _selected.contains(song.id))
        .toList();
    final totalDuration = visibleSongs.fold<Duration>(
      Duration.zero,
      (total, song) => total + (song.duration ?? Duration.zero),
    );
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _clearSelection,
              )
            : null,
        title: Text(
          _selecting ? '${_selected.length} seleccionadas' : _title,
          style: const TextStyle(fontWeight: FontWeight.w800),
        ),
        actions: _selecting
            ? [
                IconButton(
                  tooltip: 'Seleccionar todo',
                  onPressed: () => setState(() {
                    if (_selected.length == visibleSongs.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(visibleSongs.map((song) => song.id));
                    }
                  }),
                  icon: const Icon(Icons.select_all_rounded),
                ),
              ]
            : [
                if (widget.collection == LibraryCollection.history)
                  PopupMenuButton<String>(
                    onSelected: (value) {
                      if (value == 'clear') _clearHistory();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'clear',
                        child: Text('Vaciar historial'),
                      ),
                    ],
                  ),
                IconButton(
                  tooltip: 'Seleccionar canciones',
                  onPressed: visibleSongs.isEmpty
                      ? null
                      : () => setState(() => _selecting = true),
                  icon: const Icon(Icons.checklist_rounded),
                ),
                const SizedBox(width: 4),
              ],
      ),
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: _CollectionHeader(
              title: _title,
              subtitle: widget.collection == LibraryCollection.favorites
                  ? 'Las canciones que guardaste con el corazón.'
                  : 'Tu recorrido musical, de lo más reciente a lo más antiguo.',
              count: visibleSongs.length,
              duration: totalDuration,
              coverUrl: visibleSongs.firstOrNull?.artworkUrl,
              icon: _icon,
              gradient: _gradient,
              enabled: visibleSongs.isNotEmpty,
              onPlay: () => _playAll(visibleSongs, shuffle: false),
              onShuffle: () => _playAll(visibleSongs, shuffle: true),
            ),
          ),
          if (offline)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
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
          if (visibleSongs.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyState(
                icon: _icon,
                title: widget.collection == LibraryCollection.favorites
                    ? offline
                          ? 'Sin favoritos descargados'
                          : 'Aún no hay favoritos'
                    : offline
                    ? 'Sin historial descargado'
                    : 'Tu historial está vacío',
                message: widget.collection == LibraryCollection.favorites
                    ? offline
                          ? 'Descarga tus favoritos o desactiva el modo offline para verlos todos.'
                          : 'Guarda canciones con el corazón para encontrarlas aquí.'
                    : offline
                    ? 'Las canciones descargadas que escuches aparecerán aquí.'
                    : 'Las canciones que reproduzcas quedarán guardadas aquí.',
              ),
            )
          else ...[
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 6),
                child: Row(
                  children: [
                    Text(
                      'Canciones',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -.3,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${visibleSongs.length}',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            SliverList.builder(
              itemCount: visibleSongs.length,
              itemBuilder: (context, index) {
                final song = visibleSongs[index];
                return SongTile(
                  song,
                  playQueue: visibleSongs,
                  startIndex: index,
                  selectionMode: _selecting,
                  selected: _selected.contains(song.id),
                  onSelect: () => _toggleSelection(song),
                  onLongPress: _selecting ? null : () => _toggleSelection(song),
                );
              },
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
          ],
        ],
      ),
      bottomNavigationBar: _selecting
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 12, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _addSelectedToPlaylist(selectedSongs),
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: const Text('A playlist'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _downloading
                            ? null
                            : () => _downloadSelected(selectedSongs),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Descargar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: widget.collection == LibraryCollection.favorites
                          ? 'Quitar de favoritos'
                          : 'Quitar del historial',
                      onPressed: () => _deleteSelected(selectedSongs),
                      icon: const Icon(Icons.remove_circle_outline_rounded),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }
}

class _CollectionHeader extends StatelessWidget {
  const _CollectionHeader({
    required this.title,
    required this.subtitle,
    required this.count,
    required this.duration,
    required this.coverUrl,
    required this.icon,
    required this.gradient,
    required this.enabled,
    required this.onPlay,
    required this.onShuffle,
  });

  final String title;
  final String subtitle;
  final int count;
  final Duration duration;
  final String? coverUrl;
  final IconData icon;
  final List<Color> gradient;
  final bool enabled;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(20, 8, 20, 18),
      padding: const EdgeInsets.fromLTRB(18, 24, 18, 18),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colors.primary.withValues(alpha: .15),
            colors.surfaceContainerLow,
          ],
        ),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: colors.primary.withValues(alpha: .11)),
      ),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .24),
                  blurRadius: 34,
                  spreadRadius: -6,
                  offset: const Offset(0, 18),
                ),
              ],
            ),
            child: coverUrl == null
                ? Container(
                    width: 210,
                    height: 210,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: gradient,
                      ),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Icon(
                      icon,
                      color: Colors.white.withValues(alpha: .92),
                      size: 78,
                    ),
                  )
                : AlbumArt(url: coverUrl, size: 210, radius: 28),
          ),
          const SizedBox(height: 18),
          Text(
            title,
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
              height: 1.05,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            count == 1
                ? '1 canción · ${duration.hoursMinutes}'
                : '$count canciones · ${duration.hoursMinutes}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant.withValues(alpha: .78),
              height: 1.35,
            ),
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? onPlay : null,
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.play_arrow_rounded, size: 19),
                  label: const Text(
                    'Reproducir',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: enabled ? onShuffle : null,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  icon: const Icon(Icons.shuffle_rounded, size: 19),
                  label: const Text(
                    'Aleatorio',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

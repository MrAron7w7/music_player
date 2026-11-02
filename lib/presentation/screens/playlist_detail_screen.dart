import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/notification_permissions.dart';
import '../../data/models/playlist_model.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/song_tile.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final String playlistId;

  @override
  ConsumerState<PlaylistDetailScreen> createState() =>
      _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  final Set<String> _selected = <String>{};
  bool _selecting = false;
  bool _downloading = false;
  String _searchQuery = '';

  PlaylistModel? get _playlist => ref
      .watch(playlistsProvider)
      .where((entry) => entry.id == widget.playlistId)
      .firstOrNull;

  Future<void> _rename(PlaylistModel playlist) async {
    final controller = TextEditingController(text: playlist.name);
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Renombrar playlist'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(hintText: 'Nombre de la playlist'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty || !mounted) return;
    await ref
        .read(localRepositoryProvider)
        .updatePlaylist(playlist, name: name);
    ref.invalidate(playlistsProvider);
  }

  Future<void> _persistSongs(
    PlaylistModel playlist,
    List<SongModel> songs,
  ) async {
    await ref
        .read(localRepositoryProvider)
        .updatePlaylist(playlist, songs: songs);
    ref.invalidate(playlistsProvider);
  }

  Future<void> _reorder(
    PlaylistModel playlist,
    int oldIndex,
    int newIndex,
  ) async {
    if (newIndex > oldIndex) newIndex--;
    final songs = List<SongModel>.of(playlist.songs);
    final moved = songs.removeAt(oldIndex);
    songs.insert(newIndex, moved);
    await _persistSongs(playlist, songs);
  }

  Future<void> _changeCover(PlaylistModel playlist) async {
    final urls = <String>{
      for (final song in playlist.songs)
        if (song.artworkUrl != null) song.artworkUrl!,
    }.toList();
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(
            title: Text('Portada de la playlist'),
            subtitle: Text('Elige una canción o usa una URL'),
          ),
          if (urls.isNotEmpty)
            SizedBox(
              height: 250,
              child: GridView.builder(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: urls.length,
                itemBuilder: (context, index) => GestureDetector(
                  onTap: () async {
                    Navigator.pop(sheetContext);
                    await _saveCover(playlist, urls[index]);
                  },
                  child: AlbumArt(url: urls[index], radius: 12),
                ),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.link_rounded),
            title: const Text('Usar URL personalizada'),
            onTap: () async {
              Navigator.pop(sheetContext);
              final controller = TextEditingController();
              final url = await showDialog<String>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('URL de la portada'),
                  content: TextField(
                    controller: controller,
                    autofocus: true,
                    keyboardType: TextInputType.url,
                    decoration: const InputDecoration(hintText: 'https://…'),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () =>
                          Navigator.pop(dialogContext, controller.text.trim()),
                      child: const Text('Usar'),
                    ),
                  ],
                ),
              );
              controller.dispose();
              if (url != null && url.isNotEmpty) {
                await _saveCover(playlist, url);
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.restart_alt_rounded),
            title: const Text('Usar la primera canción'),
            onTap: () async {
              Navigator.pop(sheetContext);
              await _saveCover(
                playlist,
                playlist.songs.firstOrNull?.artworkUrl,
              );
            },
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  Future<void> _saveCover(PlaylistModel playlist, String? url) async {
    await ref
        .read(localRepositoryProvider)
        .savePlaylist(
          PlaylistModel(
            id: playlist.id,
            name: playlist.name,
            description: playlist.description,
            songs: playlist.songs,
            createdAt: playlist.createdAt,
            updatedAt: DateTime.now(),
            coverUrl: url,
          ),
        );
    ref.invalidate(playlistsProvider);
  }

  Future<void> _downloadPlaylist(PlaylistModel playlist) async {
    if (playlist.songs.isEmpty || _downloading) return;
    setState(() => _downloading = true);
    final service = ref.read(downloadServiceProvider);
    try {
      final result = await service.downloadMany(
        playlist.songs,
        quality: ref.read(musicRepositoryProvider).quality,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result.completed == result.total
                  ? 'Playlist descargada'
                  : '${result.completed} descargadas · ${result.failed} fallidas',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  Future<void> _addSelectedToPlaylist(PlaylistModel current) async {
    final targets = ref
        .read(playlistsProvider)
        .where((entry) => entry.id != current.id)
        .toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Crea otra playlist para mover canciones.'),
        ),
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
            ...targets.map(
              (playlist) => ListTile(
                leading: const Icon(Icons.queue_music_rounded),
                title: Text(playlist.name),
                onTap: () => Navigator.pop(sheetContext, playlist),
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null) return;
    final songs = current.songs.where((song) => _selected.contains(song.id));
    final merged = [
      ...target.songs.where((song) => !_selected.contains(song.id)),
      ...songs,
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

  Future<void> _downloadSelected(PlaylistModel playlist) async {
    final songs = playlist.songs
        .where((song) => _selected.contains(song.id))
        .toList();
    if (songs.isEmpty) return;
    final service = ref.read(downloadServiceProvider);
    setState(() => _downloading = true);
    try {
      final result = await service.downloadMany(
        songs,
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

  void _clearSelection() {
    setState(() {
      _selected.clear();
      _selecting = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final playlist = _playlist;
    if (playlist == null) {
      return const Scaffold(
        body: Center(child: Text('Playlist no encontrada')),
      );
    }
    final downloaded = ref.watch(downloadsProvider).valueOrNull ?? const [];
    final downloadedIds = downloaded.map((entry) => entry.song.id).toSet();
    final downloadedCount = playlist.songs
        .where((song) => downloadedIds.contains(song.id))
        .length;
    final colors = Theme.of(context).colorScheme;
    final searchQuery = _searchQuery.trim();
    final displaySongs = searchQuery.isEmpty
        ? playlist.songs
        : playlist.songs.where((song) {
            final q = searchQuery.toLowerCase();
            return song.title.toLowerCase().contains(q) ||
                song.artists.join(' ').toLowerCase().contains(q);
          }).toList();

    return Scaffold(
      appBar: AppBar(
        leading: _selecting
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: _clearSelection,
              )
            : null,
        title: Text(
          _selecting ? '${_selected.length} seleccionadas' : playlist.name,
        ),
        actions: _selecting
            ? [
                IconButton(
                  tooltip: 'Seleccionar todo',
                  onPressed: () => setState(() {
                    if (_selected.length == playlist.songs.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(playlist.songs.map((song) => song.id));
                    }
                  }),
                  icon: const Icon(Icons.select_all_rounded),
                ),
              ]
            : [
                IconButton(
                  tooltip: 'Descargar playlist',
                  onPressed: _downloading
                      ? null
                      : () => _downloadPlaylist(playlist),
                  icon: _downloading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.download_rounded),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'rename':
                        _rename(playlist);
                      case 'cover':
                        _changeCover(playlist);
                      case 'download':
                        _downloadPlaylist(playlist);
                      case 'delete':
                        _confirmDelete(playlist);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text('Renombrar playlist'),
                    ),
                    PopupMenuItem(
                      value: 'cover',
                      child: Text('Cambiar portada'),
                    ),
                    PopupMenuItem(
                      value: 'download',
                      child: Text('Descargar playlist'),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text('Eliminar playlist'),
                    ),
                  ],
                ),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
            child: Column(
              children: [
                AlbumArt(url: playlist.coverUrl, size: 190, radius: 24),
                const SizedBox(height: 16),
                Text(
                  playlist.name,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -.5,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${playlist.songs.length} canciones · $downloadedCount descargadas',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: colors.onSurfaceVariant),
                ),
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: playlist.songs.isEmpty
                          ? null
                          : () => _playAll(playlist, shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Reproducir'),
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      onPressed: playlist.songs.isEmpty
                          ? null
                          : () => _playAll(playlist, shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Aleatorio'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Buscar en la playlist',
                prefixIcon: const Icon(Icons.search_rounded, size: 20),
                suffixIcon: searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.close_rounded, size: 20),
                        onPressed: () => setState(() => _searchQuery = ''),
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
                  borderSide: BorderSide(color: colors.primary, width: 1.5),
                ),
              ),
            ),
          ),
          Expanded(
            child: displaySongs.isEmpty
                ? const Center(child: Text('No se encontraron canciones'))
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: displaySongs.length,
                    // ignore: deprecated_member_use
                    onReorder: searchQuery.isNotEmpty
                        ? null
                        : (oldIndex, newIndex) {
                            if (_selecting) return;
                            final oldSong = displaySongs[oldIndex];
                            final oldIdx = playlist.songs.indexWhere(
                              (s) => s.id == oldSong.id,
                            );
                            final newSong = displaySongs[newIndex];
                            final newIdx = playlist.songs.indexWhere(
                              (s) => s.id == newSong.id,
                            );
                            if (oldIdx >= 0 && newIdx >= 0) {
                              _reorder(playlist, oldIdx, newIdx);
                            }
                          },
                    itemBuilder: (context, index) {
                      final song = displaySongs[index];
                      final selected = _selected.contains(song.id);
                      final tile = SongTile(
                        song,
                        playQueue: playlist.songs,
                        startIndex: index,
                        selectionMode: _selecting,
                        selected: selected,
                        onSelect: () => setState(() {
                          _selecting = true;
                          if (selected) {
                            _selected.remove(song.id);
                          } else {
                            _selected.add(song.id);
                          }
                          if (_selected.isEmpty) _selecting = false;
                        }),
                        onLongPress: _selecting
                            ? null
                            : () => setState(() {
                                _selecting = true;
                                _selected.add(song.id);
                              }),
                        trailingExtra: _selecting
                            ? null
                            : ReorderableDragStartListener(
                                index: index,
                                child: const Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 2),
                                  child: Icon(
                                    Icons.drag_handle_rounded,
                                    size: 20,
                                  ),
                                ),
                              ),
                      );
                      return Dismissible(
                        key: ValueKey(song.id),
                        direction: searchQuery.isNotEmpty
                            ? DismissDirection.none
                            : (_selecting
                                  ? DismissDirection.none
                                  : DismissDirection.endToStart),
                        background: Container(
                          alignment: Alignment.centerRight,
                          padding: const EdgeInsets.only(right: 24),
                          color: colors.error,
                          child: Icon(
                            Icons.delete_outline,
                            color: colors.onError,
                          ),
                        ),
                        onDismissed: (_) {
                          final removed = displaySongs[index];
                          final songs = List<SongModel>.of(playlist.songs)
                            ..removeWhere((s) => s.id == removed.id);
                          _persistSongs(playlist, songs);
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Quitada “${removed.title}” de la playlist',
                              ),
                              action: SnackBarAction(
                                label: 'Deshacer',
                                onPressed: () async {
                                  final updated = List<SongModel>.of(songs)
                                    ..insert(index, removed);
                                  await _persistSongs(playlist, updated);
                                },
                              ),
                            ),
                          );
                        },
                        child: tile,
                      );
                    },
                  ),
          ),
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
                        onPressed: () => _addSelectedToPlaylist(playlist),
                        icon: const Icon(Icons.playlist_add_rounded),
                        label: const Text('A playlist'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _downloading
                            ? null
                            : () => _downloadSelected(playlist),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('Descargar'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.filledTonal(
                      tooltip: 'Quitar de la playlist',
                      onPressed: () async {
                        final songs = playlist.songs
                            .where((song) => !_selected.contains(song.id))
                            .toList();
                        await _persistSongs(playlist, songs);
                        if (mounted) _clearSelection();
                      },
                      icon: const Icon(Icons.delete_outline_rounded),
                    ),
                  ],
                ),
              ),
            )
          : null,
    );
  }

  Future<void> _playAll(PlaylistModel playlist, {required bool shuffle}) async {
    if (!mounted) return;
    unawaited(requestPlaybackNotificationPermission(context: context));
    await ref
        .read(audioHandlerProvider)
        .playSongs(playlist.songs, startIndex: 0, shuffle: shuffle);
    if (!mounted) return;
    context.push('/now-playing');
  }

  Future<void> _confirmDelete(PlaylistModel playlist) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Eliminar playlist'),
        content: Text('¿Eliminar “${playlist.name}”?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(localRepositoryProvider).deletePlaylist(playlist.id);
    ref.invalidate(playlistsProvider);
    if (mounted) Navigator.of(context).pop();
  }
}

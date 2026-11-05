import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/public_playlist_model.dart';
import '../../data/models/song_model.dart';
import '../../data/repositories/music_repository.dart' show AudioQuality;
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/player_providers.dart';
import '../../providers/search_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/song_tile.dart';

class PublicPlaylistScreen extends ConsumerStatefulWidget {
  const PublicPlaylistScreen({super.key, required this.playlistId});

  final String playlistId;

  @override
  ConsumerState<PublicPlaylistScreen> createState() =>
      _PublicPlaylistScreenState();
}

class _PublicPlaylistScreenState extends ConsumerState<PublicPlaylistScreen> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(publicPlaylistProvider(widget.playlistId));
    final theme = Theme.of(context);
    return Scaffold(
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => SafeArea(
          child: Stack(
            children: [
              EmptyState(
                icon: Icons.playlist_remove_rounded,
                title: 'No se pudo abrir la playlist',
                message: '$error',
                onRetry: () =>
                    ref.invalidate(publicPlaylistProvider(widget.playlistId)),
              ),
              const Positioned(
                left: 4,
                top: 4,
                child: BackButton(),
              ),
            ],
          ),
        ),
        data: (page) => _buildContent(context, page, theme),
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    PublicPlaylistPage page,
    ThemeData theme,
  ) {
    final songs = page.songs;
    final filtered = _query.trim().isEmpty
        ? songs
        : ref
              .watch(localSearchServiceProvider)
              .searchInSongs(songs, _query);
    final totalDuration = songs.fold<Duration>(
      Duration.zero,
      (total, song) => total + (song.duration ?? Duration.zero),
    );
    final subtitle = [
      if (page.playlist.author != null && page.playlist.author!.isNotEmpty)
        page.playlist.author!,
      '${songs.length} canciones',
      if (totalDuration > Duration.zero) _durationLabel(totalDuration),
    ].join(' · ');

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          expandedHeight: 260,
          leading: const BackButton(),
          actions: [
            IconButton(
              tooltip: 'Recargar',
              onPressed: () =>
                  ref.invalidate(publicPlaylistProvider(widget.playlistId)),
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
          flexibleSpace: FlexibleSpaceBar(
            background: _HeaderBackground(
              imageUrl: page.playlist.thumbnailUrl,
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  page.playlist.title,
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                if (page.playlist.description != null &&
                    page.playlist.description!.trim().isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    page.playlist.description!,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(
                        alpha: .85,
                      ),
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => ref
                                .read(audioHandlerProvider)
                                .playSongs(songs, shuffle: false),
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: const Text('Reproducir'),
                    ),
                    OutlinedButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => ref
                                .read(audioHandlerProvider)
                                .playSongs(songs, shuffle: true),
                      icon: const Icon(Icons.shuffle_rounded),
                      label: const Text('Aleatorio'),
                    ),
                    OutlinedButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => _downloadSongs(context, songs),
                      icon: const Icon(Icons.download_rounded),
                      label: const Text('Descargar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => _addToQueue(songs),
                      icon: const Icon(Icons.queue_music_rounded),
                      label: const Text('A la cola'),
                    ),
                    OutlinedButton.icon(
                      onPressed: songs.isEmpty
                          ? null
                          : () => _saveToLibrary(context, page),
                      icon: const Icon(Icons.library_add_rounded),
                      label: const Text('Guardar'),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                if (songs.isNotEmpty)
                  TextField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: InputDecoration(
                      hintText: 'Buscar en esta playlist',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _query.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Limpiar',
                              onPressed: () {
                                _searchController.clear();
                                setState(() => _query = '');
                              },
                              icon: const Icon(Icons.close_rounded),
                            ),
                      isDense: true,
                    ),
                  ),
                if (_query.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${filtered.length} de ${songs.length} canciones',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (songs.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.music_off_rounded,
              title: 'Playlist vacía o no disponible',
              message:
                  'YouTube Music puede haber limitado esta lista. Prueba con otra.',
              onRetry: () =>
                  ref.invalidate(publicPlaylistProvider(widget.playlistId)),
            ),
          )
        else if (filtered.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Sin coincidencias',
              message: 'Ninguna canción de esta playlist coincide con “$_query”.',
            ),
          )
        else
          SliverList.builder(
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              final song = filtered[index];
              return SongTile(
                song,
                playQueue: filtered,
                startIndex: index,
              );
            },
          ),
        const SliverToBoxAdapter(child: SizedBox(height: 110)),
      ],
    );
  }

  Future<void> _addToQueue(List<SongModel> songs) async {
    await ref.read(audioHandlerProvider).addSongsToQueue(songs);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${songs.length} canciones añadidas a la cola')),
    );
  }

  Future<void> _downloadSongs(BuildContext context, List<SongModel> songs) async {
    final quality = await _pickQuality(context);
    if (quality == null || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final service = ref.read(downloadServiceProvider);
    messenger.showSnackBar(
      SnackBar(content: Text('Descargando ${songs.length} canciones…')),
    );
    final result = await service.downloadMany(
      songs,
      quality: quality,
      onProgress: (completed, failed) {
        if (!context.mounted) return;
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              'Descargadas $completed${failed > 0 ? ' · $failed fallidas' : ''}',
            ),
            duration: const Duration(milliseconds: 900),
          ),
        );
      },
    );
    if (!context.mounted) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          result.failed == 0
              ? '${result.completed} canciones descargadas'
              : '${result.completed} descargadas, ${result.failed} fallidas',
        ),
      ),
    );
  }

  Future<void> _saveToLibrary(
    BuildContext context,
    PublicPlaylistPage page,
  ) async {
    final repository = ref.read(localRepositoryProvider);
    final playlists = ref.read(playlistsProvider);
    final existing = playlists.where(
      (playlist) =>
          playlist.name.trim().toLowerCase() ==
          page.playlist.title.trim().toLowerCase(),
    );
    var mode = 'create';
    if (existing.isNotEmpty) {
      final choice = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Ya existe una playlist con ese nombre'),
          content: const Text(
            'Puedes crear una copia nueva o añadir estas canciones a la existente.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'append'),
              child: const Text('Añadir a la existente'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'create'),
              child: const Text('Crear nueva'),
            ),
          ],
        ),
      );
      if (choice == null) return;
      mode = choice;
    }

    if (mode == 'append') {
      final target = existing.first;
      final existingIds = target.songs.map((song) => song.id).toSet();
      final additions = page.songs
          .where((song) => !existingIds.contains(song.id))
          .toList();
      await repository.updatePlaylist(
        target,
        songs: [...target.songs, ...additions],
      );
      ref.invalidate(playlistsProvider);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${additions.length} canciones añadidas a ${target.name}'),
        ),
      );
      return;
    }

    final created = await repository.createPlaylist(
      page.playlist.title,
      description: page.playlist.author == null
          ? null
          : 'Playlist pública de ${page.playlist.author}',
      songs: page.songs,
    );
    ref.invalidate(playlistsProvider);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('“${created.name}” guardada en tu biblioteca'),
        action: SnackBarAction(
          label: 'Ver',
          onPressed: () => context.push('/playlist/${created.id}'),
        ),
      ),
    );
  }
}

Future<AudioQuality?> _pickQuality(BuildContext context) => showModalBottomSheet<
  AudioQuality
>(
  context: context,
  builder: (sheetContext) => SafeArea(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            'Calidad de descarga',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        for (final quality in AudioQuality.values)
          ListTile(
            leading: Icon(
              quality == AudioQuality.high
                  ? Icons.hd_rounded
                  : Icons.audio_file_rounded,
            ),
            title: Text(
              switch (quality) {
                AudioQuality.high => 'Alta',
                AudioQuality.medium => 'Media',
                AudioQuality.low => 'Baja',
              },
            ),
            onTap: () => Navigator.pop(sheetContext, quality),
          ),
      ],
    ),
  ),
);

String _durationLabel(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  if (hours > 0) return '$hours h $minutes min';
  return '$minutes min';
}

class _HeaderBackground extends StatelessWidget {
  const _HeaderBackground({this.imageUrl});

  final String? imageUrl;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (imageUrl != null)
          Image.network(
            imageUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                colors.surface.withValues(alpha: .35),
                colors.surface,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// Evita el warning de import no usado cuando el archivo se compila aislado.
class PlaylistHeaderPreview extends StatelessWidget {
  const PlaylistHeaderPreview({super.key, required this.playlist});

  final PublicPlaylistModel playlist;

  @override
  Widget build(BuildContext context) => AlbumArt(
    url: playlist.thumbnailUrl,
    size: 120,
    radius: 18,
  );
}

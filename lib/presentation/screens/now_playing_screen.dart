import 'dart:math' as math;
import 'dart:ui';

import 'package:audio_service/audio_service.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/utils/helpers.dart';
import '../../data/models/song_model.dart';
import '../../providers/downloads_providers.dart';
import '../../providers/library_providers.dart';
import '../../providers/music_providers.dart';
import '../../providers/player_providers.dart';
import '../widgets/album_art.dart';
import '../widgets/empty_state.dart';
import '../widgets/lyrics_sheet.dart';
import '../widgets/player_controls.dart';
import '../widgets/player_seek_bar.dart';

/// Reproductor a pantalla completa inspirado en Apple Music: portada grande,
/// fondo con blur y tinte de la portada, controles claros y gestos.
class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  bool _lyricsOpen = false;
  double _dragOffset = 0;

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    final next = _dragOffset + details.delta.dy;
    if (next <= 0) {
      setState(() => _dragOffset = 0);
      return;
    }
    setState(() => _dragOffset = math.min(next, 240));
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (_dragOffset > 130 || velocity > 700) {
      Navigator.maybePop(context);
      return;
    }
    setState(() => _dragOffset = 0);
  }

  Future<void> _showLyrics(SongModel song) async {
    HapticFeedback.selectionClick();
    setState(() => _lyricsOpen = true);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withValues(alpha: .55),
      showDragHandle: false,
      builder: (_) => LyricsSheet(
        songId: song.id,
        title: song.title,
        artist: song.artists.join(', '),
        artworkUrl: song.artworkUrl,
        fallbackArtworkUrl: song.thumbnailUrl,
      ),
    );
    if (mounted) setState(() => _lyricsOpen = false);
  }

  Future<void> _addToPlaylist(SongModel song) async {
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
      builder: (sheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ListTile(title: Text('Añadir a playlist')),
          ...lists.map(
            (playlist) => ListTile(
              leading: const Icon(Icons.queue_music_rounded),
              title: Text(playlist.name),
              onTap: () => Navigator.pop(sheetContext, playlist.id),
            ),
          ),
        ],
      ),
    );
    if (selected == null || !mounted) return;
    final playlist = lists.firstWhere((entry) => entry.id == selected);
    final songs = [...playlist.songs.where((item) => item.id != song.id), song];
    await ref
        .read(localRepositoryProvider)
        .updatePlaylist(playlist, songs: songs);
    ref.invalidate(playlistsProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text('Añadida a ${playlist.name}')));
  }

  Future<void> _showQueue() async {
    final handler = ref.read(audioHandlerProvider);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: .74,
        minChildSize: .42,
        maxChildSize: .94,
        builder: (context, controller) => Consumer(
          builder: (context, ref, _) {
            final songs = ref.watch(queueSongsProvider);
            final currentIndex =
                ref.watch(queueIndexProvider) ?? handler.currentIndex;
            final colors = Theme.of(context).colorScheme;
            final canClear = songs.isNotEmpty;

            Future<void> saveAsPlaylist() async {
              final textController = TextEditingController(text: 'Mi cola');
              final name = await showDialog<String>(
                context: sheetContext,
                builder: (dialogContext) => AlertDialog(
                  title: const Text('Guardar cola como playlist'),
                  content: TextField(
                    controller: textController,
                    autofocus: true,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'Nombre de la playlist',
                    ),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(dialogContext),
                      child: const Text('Cancelar'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(
                        dialogContext,
                        textController.text.trim(),
                      ),
                      child: const Text('Guardar'),
                    ),
                  ],
                ),
              );
              textController.dispose();
              if (name == null || name.isEmpty) return;
              await ref
                  .read(localRepositoryProvider)
                  .createPlaylist(name, songs: List.of(handler.queueSongs));
              ref.invalidate(playlistsProvider);
              if (sheetContext.mounted) {
                ScaffoldMessenger.of(sheetContext).showSnackBar(
                  SnackBar(content: Text('Cola guardada en “$name”')),
                );
              }
            }

            Future<void> clearUpcoming() async {
              final action = await showModalBottomSheet<String>(
                context: sheetContext,
                useSafeArea: true,
                builder: (dialogContext) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const ListTile(title: Text('Limpiar cola')),
                      ListTile(
                        leading: const Icon(Icons.playlist_remove_rounded),
                        title: const Text('Quitar las canciones siguientes'),
                        subtitle: const Text(
                          'La canción actual seguirá sonando',
                        ),
                        onTap: () => Navigator.pop(dialogContext, 'upcoming'),
                      ),
                      ListTile(
                        leading: const Icon(Icons.clear_all_rounded),
                        title: const Text('Vaciar toda la cola'),
                        subtitle: const Text(
                          'Detiene la reproducción y oculta el reproductor',
                        ),
                        onTap: () => Navigator.pop(dialogContext, 'all'),
                      ),
                    ],
                  ),
                ),
              );
              if (action == 'upcoming') {
                await handler.clearUpcomingQueue();
              } else if (action == 'all') {
                await handler.clearQueue();
              }
            }

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: .12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          Icons.queue_music_rounded,
                          color: colors.primary,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cola de reproducción',
                              style: Theme.of(context).textTheme.titleLarge
                                  ?.copyWith(
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: -.4,
                                  ),
                            ),
                            Text(
                              songs.length == 1
                                  ? '1 canción'
                                  : '${songs.length} canciones',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: colors.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Guardar como playlist',
                        onPressed: songs.isEmpty ? null : saveAsPlaylist,
                        icon: const Icon(Icons.playlist_add_rounded),
                      ),
                      IconButton(
                        tooltip: 'Limpiar cola',
                        onPressed: canClear ? clearUpcoming : null,
                        icon: const Icon(Icons.clear_all_rounded),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: songs.isEmpty
                      ? const EmptyState(
                          icon: Icons.queue_music_rounded,
                          title: 'La cola está vacía',
                          message: 'Añade canciones con “Reproducir siguiente” o “Agregar al final”.',
                        )
                      : ReorderableListView.builder(
                          scrollController: controller,
                          buildDefaultDragHandles: false,
                          padding: const EdgeInsets.only(top: 6, bottom: 20),
                          itemCount: songs.length,
                          // ignore: deprecated_member_use
                          onReorder: (oldIndex, newIndex) =>
                              handler.moveSongInQueue(oldIndex, newIndex),
                          itemBuilder: (context, index) {
                            final song = songs[index];
                            final active = currentIndex == index;
                            return ListTile(
                              key: ValueKey('${song.id}-$index'),
                              contentPadding: const EdgeInsets.only(
                                left: 16,
                                right: 4,
                              ),
                              leading: AlbumArt(
                                url: song.artworkUrl,
                                fallbackUrl: song.thumbnailUrl,
                                size: 48,
                                radius: 10,
                              ),
                              title: Text(
                                song.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  color: active ? colors.primary : null,
                                ),
                              ),
                              subtitle: Text(
                                active
                                    ? 'Sonando ahora'
                                    : song.artists.join(', '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: active
                                    ? TextStyle(
                                        color: colors.primary,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                      )
                                    : null,
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (active)
                                    Icon(
                                      Icons.graphic_eq_rounded,
                                      color: colors.primary,
                                      size: 20,
                                    ),
                                  PopupMenuButton<String>(
                                    tooltip: 'Opciones',
                                    onSelected: (value) {
                                      if (value == 'play') {
                                        handler.skipToQueueItem(index);
                                      } else if (value == 'remove') {
                                        handler.removeSongFromQueue(index);
                                      }
                                    },
                                    itemBuilder: (_) => const [
                                      PopupMenuItem(
                                        value: 'play',
                                        child: Text('Reproducir ahora'),
                                      ),
                                      PopupMenuItem(
                                        value: 'remove',
                                        child: Text('Quitar de la cola'),
                                      ),
                                    ],
                                  ),
                                  ReorderableDragStartListener(
                                    index: index,
                                    child: const Padding(
                                      padding: EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 14,
                                      ),
                                      child: Icon(
                                        Icons.drag_handle_rounded,
                                        size: 22,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                HapticFeedback.selectionClick();
                                handler.skipToQueueItem(index);
                              },
                            );
                          },
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _toggleFavorite(SongModel song) async {
    await ref.read(localRepositoryProvider).toggleFavorite(song);
    ref.invalidate(favoritesProvider);
    HapticFeedback.selectionClick();
  }

  Future<void> _downloadCurrent(SongModel song) async {
    final service = ref.read(downloadServiceProvider);
    final progress = ref.read(downloadProgressProvider).valueOrNull?[song.id];
    final messenger = ScaffoldMessenger.of(context);

    if (progress != null && progress < 1) {
      await service.delete(song.id);
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Descarga cancelada')),
      );
      return;
    }
    if (service.isDownloaded(song.id)) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Esta canción ya está disponible sin conexión.'),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(content: Text('Descargando “${song.title}”…')),
    );
    try {
      await service.download(
        song,
        quality: ref.read(musicRepositoryProvider).quality,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Descarga completada')),
      );
    } catch (error) {
      if (!mounted || error.toString() == 'Descarga cancelada.') return;
      messenger.showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  Future<void> _showMore(SongModel song) async {
    final service = ref.read(downloadServiceProvider);
    final downloads =
        ref.read(downloadsProvider).valueOrNull ?? service.entries;
    final downloaded = downloads.any((entry) => entry.song.id == song.id);
    final progress = ref.read(downloadProgressProvider).valueOrNull?[song.id];
    final downloading = progress != null && progress < 1;

    final action = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Wrap(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 2, 20, 14),
                child: Row(
                  children: [
                    AlbumArt(
                      url: song.artworkUrl,
                      fallbackUrl: song.thumbnailUrl,
                      size: 54,
                      radius: 14,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            song.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            song.artists.join(', '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: colors.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (song.albumId != null)
                ListTile(
                  leading: const Icon(Icons.album_rounded),
                  title: const Text('Ver álbum'),
                  subtitle: song.album == null ? null : Text(song.album!),
                  onTap: () => Navigator.pop(sheetContext, 'album'),
                ),
              ListTile(
                leading: const Icon(Icons.playlist_add_rounded),
                title: const Text('Añadir a playlist'),
                onTap: () => Navigator.pop(sheetContext, 'playlist'),
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
                subtitle: Text(
                  downloading
                      ? '${(progress * 100).round()}% completado'
                      : downloaded
                      ? 'Disponible sin conexión'
                      : 'Guardar para escuchar sin conexión',
                ),
                onTap: () => Navigator.pop(
                  sheetContext,
                  downloading || !downloaded ? 'download' : 'delete-download',
                ),
              ),
              const SizedBox(height: 10),
            ],
          ),
        );
      },
    );
    if (!mounted || action == null) return;

    switch (action) {
      case 'album':
        if (song.albumId != null) context.push('/album/${song.albumId}');
      case 'playlist':
        await _addToPlaylist(song);
      case 'download':
        await _downloadCurrent(song);
      case 'delete-download':
        await service.delete(song.id);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Descarga eliminada')));
        }
    }
  }

  Future<void> _showAudioOutput(String? bluetoothName) async {
    final bluetooth = bluetoothName != null;
    final displayName = bluetooth
        ? (bluetoothName.trim().isEmpty ? 'Bluetooth' : bluetoothName.trim())
        : 'Este dispositivo';
    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final colors = Theme.of(sheetContext).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Salida de audio',
                  style: Theme.of(sheetContext).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: colors.primary.withValues(alpha: .10),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        bluetooth
                            ? Icons.bluetooth_audio_rounded
                            : Icons.speaker_rounded,
                        color: colors.primary,
                        size: 28,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bluetooth
                                  ? 'Conectado por Bluetooth'
                                  : 'Altavoz o auriculares del dispositivo',
                              style: TextStyle(
                                color: colors.onSurfaceVariant,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (bluetooth)
                        Icon(Icons.check_circle_rounded, color: colors.primary),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final song = ref.watch(currentSongProvider).valueOrNull;
    if (song == null) {
      return const Scaffold(
        body: EmptyState(
          icon: Icons.music_note_rounded,
          title: 'No hay música en reproducción',
        ),
      );
    }

    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final accent =
        ref.watch(albumArtColorProvider).valueOrNull ?? colors.primary;
    final favorites = ref.watch(favoritesProvider);
    final isFavorite = favorites.any((item) => item.id == song.id);
    final downloads = ref.watch(downloadsProvider).valueOrNull;
    final downloadEntry = downloads
        ?.where((entry) => entry.song.id == song.id)
        .firstOrNull;
    final downloadProgress = ref
        .watch(downloadProgressProvider)
        .valueOrNull?[song.id];
    final isDownloading = downloadProgress != null && downloadProgress < 1;
    final bluetooth = ref.watch(bluetoothAudioDeviceProvider);
    final processingState = ref.watch(
      playbackStateProvider.select(
        (state) => state.valueOrNull?.processingState,
      ),
    );
    final playbackErrorMessage = ref.watch(
      playbackStateProvider.select((state) => state.valueOrNull?.errorMessage),
    );
    final immersiveBase = Color.lerp(const Color(0xFF080A0E), accent, .20)!;
    final qualityName =
        downloadEntry?.quality ??
        ref.read(musicRepositoryProvider).quality.name;
    final bitrate = switch (qualityName) {
      'low' => 64,
      'medium' => 128,
      _ => 160,
    };
    final estimatedBytes =
        downloadEntry?.bytes ??
        ((song.duration?.inSeconds ?? 0) * bitrate * 1000 / 8).round();
    final qualityLabel = [
      'WEBM',
      '$bitrate kbps',
      if (estimatedBytes > 0) formatBytes(estimatedBytes),
    ].join(' • ');
    final isError = processingState == AudioProcessingState.error;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        systemNavigationBarColor: immersiveBase,
      ),
      child: Transform.translate(
        offset: Offset(0, _dragOffset),
        child: Scaffold(
          backgroundColor: immersiveBase,
          body: Stack(
            fit: StackFit.expand,
            children: [
              if (song.artworkUrl != null)
                RepaintBoundary(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                    child: CachedNetworkImage(
                      imageUrl: song.thumbnailUrl ?? song.artworkUrl!,
                      fit: BoxFit.cover,
                      memCacheWidth: 320,
                      memCacheHeight: 480,
                      errorWidget: (context, url, error) =>
                          ColoredBox(color: immersiveBase),
                    ),
                  ),
                ),
              AnimatedContainer(
                duration: const Duration(milliseconds: 650),
                curve: Curves.easeInOutCubic,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: .34),
                      Colors.black.withValues(alpha: .50),
                      immersiveBase.withValues(alpha: .97),
                    ],
                    stops: const [0, .52, 1],
                  ),
                ),
              ),
              SafeArea(
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 2, 10, 0),
                      child: Row(
                        children: [
                          IconButton(
                            tooltip: 'Minimizar',
                            onPressed: () => Navigator.maybePop(context),
                            icon: const Icon(
                              Icons.keyboard_arrow_down_rounded,
                              size: 34,
                              color: Colors.white,
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  'REPRODUCIENDO AHORA',
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    letterSpacing: 1.8,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white.withValues(alpha: .56),
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  song.album ?? 'Simple Music',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: Colors.white.withValues(alpha: .78),
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 48),
                        ],
                      ),
                    ),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final artSize = math
                              .min(
                                constraints.maxWidth - 52,
                                constraints.maxHeight * .48,
                              )
                              .clamp(210.0, 390.0)
                              .toDouble();
                          return SingleChildScrollView(
                            physics: const BouncingScrollPhysics(),
                            padding: const EdgeInsets.fromLTRB(24, 8, 24, 28),
                            child: Column(
                              children: [
                                GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onVerticalDragUpdate: _onVerticalDragUpdate,
                                  onVerticalDragEnd: _onVerticalDragEnd,
                                  onHorizontalDragEnd: (details) {
                                    final velocity =
                                        details.primaryVelocity ?? 0;
                                    if (velocity < -260) {
                                      ref
                                          .read(audioHandlerProvider)
                                          .skipToNext();
                                    } else if (velocity > 260) {
                                      ref
                                          .read(audioHandlerProvider)
                                          .skipToPrevious();
                                    }
                                  },
                                  child: AnimatedSwitcher(
                                    duration: const Duration(milliseconds: 300),
                                    switchInCurve: Curves.easeOutCubic,
                                    switchOutCurve: Curves.easeInCubic,
                                    transitionBuilder: (child, animation) =>
                                        FadeTransition(
                                          opacity: animation,
                                          child: ScaleTransition(
                                            scale: Tween<double>(
                                              begin: .96,
                                              end: 1,
                                            ).animate(animation),
                                            child: child,
                                          ),
                                        ),
                                    child: Hero(
                                      key: ValueKey(song.id),
                                      tag: 'art-${song.id}',
                                      child: Container(
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            30,
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withValues(
                                                alpha: .55,
                                              ),
                                              blurRadius: 54,
                                              spreadRadius: -6,
                                              offset: const Offset(0, 30),
                                            ),
                                          ],
                                        ),
                                        child: AlbumArt(
                                          url: song.artworkUrl,
                                          fallbackUrl: song.thumbnailUrl,
                                          size: artSize,
                                          radius: 30,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 24),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(
                                      child: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 260,
                                        ),
                                        transitionBuilder: (child, animation) =>
                                            FadeTransition(
                                              opacity: animation,
                                              child: SlideTransition(
                                                position: Tween<Offset>(
                                                  begin: const Offset(0, .12),
                                                  end: Offset.zero,
                                                ).animate(animation),
                                                child: child,
                                              ),
                                            ),
                                        child: Column(
                                          key: ValueKey('info-${song.id}'),
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              song.title,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme
                                                  .textTheme
                                                  .headlineSmall
                                                  ?.copyWith(
                                                    color: Colors.white,
                                                    fontSize: 28,
                                                    height: 1.12,
                                                    fontWeight: FontWeight.w800,
                                                    letterSpacing: -1,
                                                  ),
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              song.artists.join(', '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleMedium
                                                  ?.copyWith(
                                                    color: Colors.white
                                                        .withValues(alpha: .70),
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: isFavorite
                                          ? 'Quitar de favoritos'
                                          : 'Añadir a favoritos',
                                      onPressed: () => _toggleFavorite(song),
                                      icon: AnimatedSwitcher(
                                        duration: const Duration(
                                          milliseconds: 180,
                                        ),
                                        transitionBuilder: (child, animation) =>
                                            ScaleTransition(
                                              scale: animation,
                                              child: child,
                                            ),
                                        child: Icon(
                                          isFavorite
                                              ? Icons.favorite_rounded
                                              : Icons.favorite_border_rounded,
                                          key: ValueKey(isFavorite),
                                          color: isFavorite
                                              ? const Color(0xFFFF5C8A)
                                              : Colors.white,
                                          size: 27,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Más opciones',
                                      onPressed: () => _showMore(song),
                                      icon: const Icon(
                                        Icons.more_horiz_rounded,
                                        color: Colors.white,
                                        size: 29,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 14),
                                PlayerSeekBar(
                                  fallbackDuration: song.duration,
                                  foregroundColor: Colors.white,
                                ),
                                const SizedBox(height: 4),
                                _QualityBadge(
                                  label: qualityLabel,
                                  downloading: isDownloading,
                                  progress: downloadProgress,
                                ),
                                const SizedBox(height: 16),
                                const PlayerControls(
                                  foregroundColor: Colors.white,
                                ),
                                const SizedBox(height: 24),
                                _PlayerActionsBar(
                                  lyricsOpen: _lyricsOpen,
                                  bluetoothName: bluetooth?.name,
                                  onLyrics: () => _showLyrics(song),
                                  onQueue: () => _showQueue(),
                                  onAudioOutput: () =>
                                      _showAudioOutput(bluetooth?.name),
                                ),
                                if (isError)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 16),
                                    child: Container(
                                      padding: const EdgeInsets.all(14),
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: .07,
                                        ),
                                        borderRadius: BorderRadius.circular(18),
                                        border: Border.all(
                                          color: colors.error.withValues(
                                            alpha: .45,
                                          ),
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.wifi_off_rounded,
                                            color: colors.error,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Text(
                                              playbackErrorMessage ?? 'No se pudo reproducir esta canción. Inténtalo de nuevo.',
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontSize: 13,
                                                height: 1.35,
                                              ),
                                            ),
                                          ),
                                          TextButton(
                                            onPressed: () => ref
                                                .read(audioHandlerProvider)
                                                .retryCurrent(),
                                            child: const Text(
                                              'Reintentar',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  const _QualityBadge({
    required this.label,
    required this.downloading,
    required this.progress,
  });

  final String label;
  final bool downloading;
  final double? progress;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: .10)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.graphic_eq_rounded,
              size: 14,
              color: Colors.white.withValues(alpha: .62),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .64),
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                letterSpacing: .2,
              ),
            ),
            if (downloading) ...[
              const SizedBox(width: 8),
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 1.8,
                  color: Colors.white.withValues(alpha: .80),
                ),
              ),
              const SizedBox(width: 4),
              Text(
                '${((progress ?? 0) * 100).round()}%',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .70),
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PlayerActionsBar extends StatelessWidget {
  const _PlayerActionsBar({
    required this.lyricsOpen,
    required this.bluetoothName,
    required this.onLyrics,
    required this.onQueue,
    required this.onAudioOutput,
  });

  final bool lyricsOpen;
  final String? bluetoothName;
  final VoidCallback onLyrics;
  final VoidCallback onQueue;
  final VoidCallback onAudioOutput;

  @override
  Widget build(BuildContext context) {
    final bluetooth = bluetoothName != null;
    final deviceLabel = bluetooth
        ? ((bluetoothName?.trim().isEmpty ?? true)
              ? 'Bluetooth'
              : bluetoothName!.trim())
        : 'Este dispositivo';
    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.white.withValues(alpha: .10)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
      child: Row(
        children: [
          _PlayerAction(
            icon: Icons.lyrics_outlined,
            label: 'Letras',
            active: lyricsOpen,
            onPressed: onLyrics,
          ),
          _PlayerAction(
            icon: Icons.queue_music_rounded,
            label: 'Cola',
            onPressed: onQueue,
          ),
          _PlayerAction(
            icon: bluetooth
                ? Icons.bluetooth_audio_rounded
                : Icons.speaker_rounded,
            label: deviceLabel,
            active: bluetooth,
            onPressed: onAudioOutput,
          ),
        ],
      ),
    );
  }
}

class _PlayerAction extends StatelessWidget {
  const _PlayerAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () {
            HapticFeedback.selectionClick();
            onPressed();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 2),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: active
                        ? Colors.white.withValues(alpha: .16)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    icon,
                    size: 22,
                    color: Colors.white.withValues(alpha: active ? 1 : .82),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: active ? .95 : .62),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
